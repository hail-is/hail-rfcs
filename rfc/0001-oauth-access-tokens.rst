==============
OAuth 2.0 Authorization in the Hail Service
==============

.. author:: Daniel Goldstein
.. date-accepted:: Leave blank. This will be filled in when the proposal is accepted.
.. ticket-url:: Leave blank. This will eventually be filled with the
                ticket URL which will track the progress of the
                implementation of the feature.
.. implemented:: Leave blank. This will be filled in with the first Hail version which
                 implements the described feature.
.. header:: This proposal is `discussed at this pull request <https://github.com/hail-is/hail-rfc/pull/0>`_.
            **After creating the pull request, edit this file again, update the
            number in the link, and delete this bold sentence.**
.. sectnum::
.. contents::
.. role:: python(code)

Motivation
==========

This proposal focuses on the way by which users of Hail services
authorize programmatic access to the Hail API.

The Hail Service authenticates users using the OAuth2 protocol, relying on either
GCP IAM or Azure AD as the identity providers. However, while the Hail Service
relies on these identity providers for authentication, it currently does *not* use them
to authorize access to Hail APIs. The Hail ``auth`` service acts as an Authorization
Server for the Hail API, minting long-lived tokens after the OAuth2 flow that are persisted
on user machines. Minting our own tokens imposes a maintenance and security burden
on the Hail team and any operators of a Hail Service.

This proposal deprecates the use of Hail-minted tokens in favor of using
access tokens from the identity providers listed above to authorize API access.
This removes the security burden of minting and protecting our own authorization
tokens while reducing code complexity since cloud access tokens are already
used within the Hail codebase to access cloud APIs.

Proposed Change Specification
=============================

Currently, requests to the Hail APIs send one of the aforementioned Hail-minted tokens in the
``Authorization`` header of HTTP requests. This token is stored in a well-known
location on the user's disk.
For user machines, this file is persisted during the login flow ``hailctl auth login``.
For use in Batch jobs, the tokens are stored in Kubernetes secrets and delivered
to the Batch Worker as part of the job spec.

This proposal adds the ability for HTTP requests from Hail clients to send
OAuth2 access tokens in the ``Authorization`` header instead of Hail-minted
tokens. The ``auth`` service will:

- Assert the validity, expiration and audience of access tokens and associate
  them with users of the system.
- Support Hail-minted tokens for backwards compatibility with old clients
  for a limited time. Eventually, support for Hail-minted tokens will be dropped.

Hail clients will be updated to use access tokens in requests to Hail APIs. How
they do so is described in the following subsections.


Overview of Relevant OAuth2 Background
--------------------------------------

Prior to discussing the details of the implementation, it is worth covering some
background on OAuth2. Note that much of this functionality is encapsulated in the
Google OAuth and AAD client libraries that we use, but a thorough understanding
is valuable to ensure that we are using them properly.

We'll consider four primary entities in an OAuth2 interaction:

- The user/identity
- The client (e.g. the Hail python library)
- The Authorization Server (Google IAM or AAD)
- The API/Resource Server (the Hail service)

For clients operated by a human user, the client must obtain credentials to act
on behalf of the user before it can perform any further operations.
The client uses an `OAuth2 client secret <https://developers.google.com/identity/protocols/oauth2/native-app>`_
to initiate a web-based flow with the Authorization Server. During this flow, the
user must authenticate and authorize the client to act on the user's behalf with
a given set of capabilities (scopes).

From this point forward, the client can perform operations without manual intervention,
using the credentials granted from the flow in the human case, and using a robot identity's
key or password in the robot case.

When the client wants to perform some operation against the Resource Server, it must
first request an access token from the Authorization Server.
Three important factors to note about the access token are:

- The scopes the token is granted. These specify to the API server the purposes
  for which the token may be used. It is the responsibility of the API server to
  respect the scopes.
- The identity represented by that token. This is either the user or robot identity.
  In JWTs, the identity is uniquely identified by the
  `sub <https://www.rfc-editor.org/rfc/rfc7519#section-4.1.2>`_ (Subject) claim. This prevents
  the token from being used to act on a different identity's behalf. Note that the
  sub need not be globally unique, but it must be unique amongst all subs at this
  identity provider.
- The "intended audience" of the token. What this means exactly varies between
  Google and Azure, but in both cases is represented by the
  `aud <https://www.rfc-editor.org/rfc/rfc7519#section-4.1.3>`_ (Audience) claim.
  It is the responsibility of the resource server to respect this so that it does
  not accept tokens intended for other APIs.

The client should then request a token with the minimal set of scopes required to
perform the desired operation (in our case just enough to identify the user) and with
an audience that will be accepted by the Resource Server. It then sends this token
in the ``Authorization`` header of requests to the Resource Server.

When the Resource Server receives the request, it can verify the validity and
expiration of the token, identify the user through the ``sub`` claim, and finally
accept the token only if its ``aud`` claim is one that the Resource Server recognizes
and permits. This way tokens from that user that were generated and intended
for other systems cannot be replayed against this Resource Server.

Unfortunately Google and Azure have slightly different approaches to this interaction.
Both scenarios will involve installing an OAuth2 client credential on the user's machine
to be used by the Hail python library, and they will involve similar changes to the ``auth``
service. However, their implementations vary slightly when it comes to the audience
claim, so the process to obtain access tokens will look slightly different.
The following sections detail how that process would work with those two identity providers.


Google Implementation
---------------------

When a client application requests an access token from Google IAM, the ``aud``
claim is always set to the unique ID of the client. On a user's machine, ``aud``
would be the client ID of the OAuth2 Client used to obtain that credential. For
service accounts, it would be the unique ID of the service account in IAM. Note
that in the service account case ``aud == sub``, but not in the case of the Hail
python library acting on behalf of a user.

I find this unintuitive, but I suppose this can be interpreted as "the intended
recipient of this token is the application that requested it, and Resource Servers
should maintain a list of trusted applications".

Thus, when the ``auth`` service validates an access token, it must assert that
the ``aud`` claim is *either* the Client ID for the python library OAuth2 Client
or the unique ID of a Hail-owned service account in the system. Doing so protects
against client applications that we don't control impersonating human users to our
system.

Another detail of note is that Google IAM access tokens are *opaque*, so in order
to decode them the ``auth`` server must submit them to a Google API. The ``auth``
service should take care to properly cache requests for no more than one minute
to prevent rate-limiting by Google IAM. Requests to Google IAM scale linearly with
concurrent users, but that is not a concern at time of writing since
Hail services receive single to double digit concurrent users.


Azure Implementation
---------------------

Azure, however, interprets "intended recipient" as the Resource Server for which
a token is destined, and infers that recipient based on the scopes requested
by the client. For example, requesting the scope ``https://management.azure.com/.default``
results in tokens whose ``aud`` claim is the ID of the Graph API. In order to use
non-Azure Resource Servers, AAD allows you to create custom scopes. We register
a custom scope like ``api://<SOME_UNIQUE_ID>`` with the AAD OAuth2 Client application
and then any code that requests that scope will receive a token whose ``aud``
scope is the ID of that OAuth2 Client application.

This simplifies the work of the ``auth`` service, as there is a single audience
it must trust. However, it means that we must communicate this custom scope to
all our environments.

As opposed to the opaque access tokens in Google, Azure access tokens are JWTs.
That means they can be decoded and cryptographically validated by the ``auth``
service without making a network request.


User Machine Configuration Changes
----------------------------------

If we remove Hail-minted tokens, the Hail python client needs a mechanism
for requesting access tokens on behalf of the user. The way to do this is to have
a Desktop OAuth2 client credential that lives on the user's machine that administers
the OAuth2 flow and is later used to request tokens.

Instead of depositing a ``tokens.json`` file during the login flow,
``hailctl auth login`` will instead result in the following file placed in the
user's configuration directory at ``$XDG_CONFIG_HOME/hail/identity.json``.

.. code-block:: json

    {
       "idp": "Google" | "Microsoft",
       ... Optional IDP-Specific OAuth2 client secret ...
    }

This file contains the identity provider the user used to log into the Hail
Service and a OAuth2 client credential file issued by the Hail Service
for that identity provider along with the refresh token. This client credential
will be used in future requests by the client to obtain scoped access tokens
from the identity provider that are intended for the Hail Service. In Azure,
this will include the custom scope that the client needs for requests.

For further information on the details of the OAuth2 flow, see the User Login
Flow Changes section.

If a user does not reauthenticate after updating their Hail version,
the client will continue to use extant ``tokens.json`` file.


Batch Job Configuration Changes
-------------------------------
Batch jobs do not authenticate through an OAuth2 flow in the way that human users do.
The service account keys or metadata server available in batch jobs both provide
ways to easily obtain access tokens. All that the job needs to know is which identity
provider it should use, so it will be provided with the following
identity config: ``{"idp": "Google" | "Microsoft"}``. Instead of writing this to the
filesystem on every job, Batch can provide this through a ``HAIL_IDENTITY_JSON`` environment
variable. Without the presence of a specific OAuth2 client to use for generating tokens,
the Hail library will fall back to the latent credentials in the environment,
e.g. ``GOOGLE_APPLICATION_CREDENTIALS`` or the metadata server.

In Azure, there will be another environment variable ``HAIL_AZURE_OAUTH_SCOPE``
that clients must use to obtain an appropriate audience claim.


User Login Flow Changes
-----------------------

Currently, ``hailctl auth login`` performs a sort of mixed desktop and server
OAuth2 login flow, which occurs in the following sequence:

1. User executes ``hailctl auth login`` via the command line
2. The user's machine prompts the Hail ``auth`` service to initiate a login flow
   by making a request to ``/api/v1alpha/login``. The ``auth`` service responds
   with an authorization URL that ``hailctl`` then opens in a browser.
3. The user authenticates and provides user consent
4. The OAuth2 provider authenticates the user and sends a callack to ``localhost``
   with an authorization code.
5. ``hailctl`` sends that authorization code to the ``auth`` service, which uses
   it to complete the OAuth flow, receiving an ID token, an access token and a refresh token.
6. The ``auth`` service uses the ID token to identify the user and assert that the
   user has an account with the Service.
7. The ``auth`` service mints a token that it sends in the response to ``hailctl``.
8. ``hailctl`` persists the token for future authorization of API calls to the Service.


The proposed ``hailctl auth login`` flow is as follows:

1. User executes ``hailctl auth login`` via the command line
2. ``hailctl`` obtains the OAuth2 client credentials from a well-known, public
   endpoint on the ``auth`` API. Note that it is OK to make this resource public
   as Desktop OAuth2 Client Secrets `are not considered secret <https://developers.google.com/identity/protocols/oauth2/native-app>`_
   as they cannot necessarily store data confidentially on the user's machine.
3. ``hailctl`` performs the full Desktop OAuth flow on the user's machine,
   persisting the ``refresh_token`` it receives at the end of the flow along with
   the OAuth2 client credentials.
4. ``hailctl`` attempts to access the ``/userinfo`` endpoint on the ``auth`` service
   to confirm that the logged in user is registered with the Hail service.


The programmatic OAuth2 flow will use a different OAuth2 client than that used
in the typical Web flow. When conducting a web-based flow, the OAuth2 client credentials
can be kept secret by the server and Google can verify that the request to initiate a
login flow is coming from a source that owns the OAuth2 client. As such, it is valuable to
keep the OAuth2 client actually secret. However, this does not exist in the world of
Desktop applications, as client secrets stored on user devices *cannot be considered secret*.
In order to preserve the integrity of the web-based login, it is best to maintain a separate
OAuth2 client that is issued specifically for desktop applications. There is also an intuitive
argument for why we should generate two OAuth clients, as the Hail python library and the Hail
web service are two distinct applications, and we could in the future want different scopes
in those two environments.

It is worth noting that attackers with access to the user's filesystem can use the
``refresh_token`` to create access tokens. That being said, the access tokens
that an attacker could obtain from this OAuth2 secret can only be used outside of the Hail
Service to obtain the user's email. If an attacker wanted additional scopes they would need
to initate an OAuth2 flow which would require manual user consent for the elevated permissions.
More realistically, an attacker can just as easily obtain ``gcloud`` access tokens that are likely
to be far more privileged. So it is reasonable to say that we are not introducing new
vulnerabilities to the user's machine.


Effect and Interactions
-----------------------

It is worth comparing the privileges obtained in both the current and proposed scenario
to determine if there are any increased risks under the new regime.

For Hail-minted access tokens:

- An attacker who obtains a token can fully impersonate a user to the Hail Service
- The token is *only* authorized to access the Hail Service
- Tokens can be explicitly revoked by the user by executing ``hailctl auth logout`` but
  are otherwise long-lived.

For Hail-audience client secret:

- An attacker can just as easily access the client secret as they can the Hail tokens.
  The attacker can then generate access tokens if the user has previously logged in
  and the refresh token is still valid.
- The audience claim of these access tokens will be the Hail python package, so these
  tokens can only be used against the Hail Service.
- Unlike the Hail-minted tokens, the Bearer token in the requests are short-lived
  access tokens. So any access tokens that might be leaked are unlikely to pose
  a security risk.
- The client can dynamically configure the validity period for access tokens it
  generates.
- The refresh token is also a long-lived credential, but can be invalidated by
  the user revoking it through ``hailctl auth logout``.


Alternatives
------------

An alternative to persisting a Hail-owned client secret on the user's machine
is to use the latent credentials from ``gcloud`` Application Default Credentials.
However, this is seen as an abuse of the OAuth2 model. Using Application Default
Credentials would require that the ``auth`` service accept tokens with the
``gcloud`` audience claim. It would obviate the need to authenticate with the
Hail Service and any entity with a gcloud-generated user access token
would be able to impersonate the user to the Hail Service. Additionally, the
Hail Service, if compromised, could impersonate the user to other APIs that
accept the ``gcloud`` audience claim.

Another alternative is simply to not change our authorization model. Doing nothing
would leave Hail Service operators with the management of token secrets. It would
also make more difficult the integration of Hail services inside other
environments that use access-token based authentication such as the Terra platform.

Not an alternative, but an extension to this model could be encrypting and protecting
access to the OAuth2 client secret using something like Apple Keychain or equivalent
on other operating systems. The user would then be prompted to enter their password
when ``hailctl`` attempts to access the file and would therefore make it obvious to
the user if other applications try to do the same. Given that even ``gcloud`` does
not do this, we are leaving it out of this initial proposal.


Unresolved Questions
--------------------

It is as of yet unclear whether regular rotation of client secrets stored on
client devices should be performed. If that should be the case, we could do so
without much effort because the Hail Service distributes the client secrets in
the first place. We would simply need to configure the ``hailctl`` client to reinitiate
a login flow when the credential expires or is revoked.

It is also unclear whether there is any way to somehow restrict the audience of
service account access tokens in Google as you can in Azure. I think this is a minor
concern as the tokens we'll generate for Hail auth will be strictly scoped.


Endorsements
-------------
(Optional) This section provides an opportunity for any third parties to express their
support for the proposal, and to say why they would like to see it adopted.
It is not mandatory for have any endorsements at all, but the more substantial
the proposal is, the more desirable it is to offer evidence that there is
significant demand from the community.  This section is one way to provide
such evidence.

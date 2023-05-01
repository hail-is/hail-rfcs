========
Hail RFC
========

This repository contains specifications for proposed changes to
`Hail <https://www.hail.is/>`_.
The purpose of the Hail rfc process is to broaden the discussion of the
evolution of Hail.

What is an RFC?
---------------

A Hail RFC is a document describing a proposed change to Hail query, batch,
CI or any systems under `hail <https://github.com/hail-is/hail>`_.

How to start a new proposal
---------------------------

Proposals are written in `ReStructuredText <http://www.sphinx-doc.org/en/stable/rest.html>`_.

Proposals should follow the structure given in the
`ReStructuredText template <https://github.com/hail-is/hail-rfc/blob/main/proposals/0000-template.rst>`_.

See the section `Review criteria <#review-criteria>`_ below for more information
about what makes a strong proposal, and how it will be reviewed.

To start a proposal, create a pull request that adds your proposal as
``proposals/0000-proposal-name.rst``. Use the corresponding
``proposals/0000-template.rst`` file as a template.

If you are unfamiliar with git and GitHub, you can use the GitHub web interface
to perform these steps:

1. Load the proposal template using `this link (ReStructuredText)`__.
2. Change the filename and edit the proposal.
3. Press “Commit new file”

__ https://github.com/hail-is/hail-rfc/new/main?filename=rfc/0000-new-proposal.rst;message=Start%20new%20proposal;value=Notes%20on%20reStructuredText%20-%20delete%20this%20section%20before%20submitting%0A%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%0A%0AThe%20proposals%20are%20submitted%20in%20reStructuredText%20format.%0ATo%20get%20inline%20code%2C%20enclose%20text%20in%20double%20backticks%2C%20%60%60like%20this%60%60%2C%20or%20include%0Ainline%20syntax%20highlighting%20%5Bscala%5D%60like%20this%60.%0ATo%20get%20block%20code%2C%20use%20a%20double%20colon%20and%20indent%20by%20at%20least%20one%20space%0A%0A%3A%3A%0A%0A%20like%20this%0A%20and%0A%0A%20this%20too%0A%0ATo%20get%20hyperlinks%2C%20use%20backticks%2C%20angle%20brackets%2C%20and%20an%20underscore%0A%60like%20this%20%3Chttp%3A//www.hail.is/%3E%60_.%0A%0A%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%0AProposal%20title%0A%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%3D%0A%0A..%20author%3A%3A%20Your%20name%0A..%20date-accepted%3A%3A%20Leave%20blank.%20This%20will%20be%20filled%20in%20when%20the%20proposal%20is%20accepted.%0A..%20ticket-url%3A%3A%20Leave%20blank.%20This%20will%20eventually%20be%20filled%20with%20the%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20ticket%20URL%20which%20will%20track%20the%20progress%20of%20the%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20implementation%20of%20the%20feature.%0A..%20implemented%3A%3A%20Leave%20blank.%20This%20will%20be%20filled%20in%20with%20the%20first%20Hail%20version%20which%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20implements%20the%20described%20feature.%0A..%20header%3A%3A%20This%20proposal%20is%20%60discussed%20at%20this%20pull%20request%20%3Chttps%3A//github.com/hail-is/hail-rfc/pull/0%3E%60_.%0A%20%20%20%20%20%20%20%20%20%20%20%20%2A%2AAfter%20creating%20the%20pull%20request%2C%20edit%20this%20file%20again%2C%20update%20the%0A%20%20%20%20%20%20%20%20%20%20%20%20number%20in%20the%20link%2C%20and%20delete%20this%20bold%20sentence.%2A%2A%0A..%20sectnum%3A%3A%0A..%20contents%3A%3A%0A..%20role%3A%3A%20scala%28code%29%0A%0AHere%20you%20should%20write%20a%20short%20abstract%20motivating%20and%20briefly%20summarizing%20the%0Aproposed%20change.%0A%0AMotivation%0A----------%0AGive%20a%20strong%20reason%20for%20why%20the%20community%20needs%20this%20change.%20Describe%20the%20use%0Acase%20as%20clearly%20as%20possible%20and%20give%20an%20example.%20Explain%20how%20the%20status%20quo%20is%0Ainsufficient%20or%20not%20ideal.%0A%0AA%20good%20Motivation%20section%20is%20often%20driven%20by%20examples%20and%20real-world%20scenarios.%0A%0AProposed%20Change%20Specification%0A-----------------------------%0ASpecify%20the%20change%20in%20precise%2C%20comprehensive%20yet%20concise%20language.%20Avoid%20words%0Alike%20%22should%22%20or%20%22could%22.%20Strive%20for%20a%20complete%20definition.%20Your%20specification%0Amay%20include%2C%0A%0A%2A%20the%20types%20and%20semantics%20of%20any%20new%20library%20interfaces%0A%2A%20how%20the%20proposed%20change%20interacts%20with%20existing%20language%20or%20compiler%0A%20%20features%2C%20in%20case%20that%20is%20otherwise%20ambiguous%0A%0AStrive%20for%20%2Aprecision%2A.%20Note%2C%20however%2C%20that%20this%20section%20should%20focus%20on%20a%0Aprecise%20%2Aspecification%2A%3B%20it%20need%20not%20%28and%20should%20not%29%20devote%20space%20to%0A%2Aimplementation%2A%20details%20--%20the%20%22Implementation%20Plan%22%20section%20can%20be%20used%20for%0Athat.%0A%0AThe%20specification%20can%2C%20and%20almost%20always%20should%2C%20be%20illustrated%20with%0A%2Aexamples%2A%20that%20illustrate%20corner%20cases.%20But%20it%20is%20not%20sufficient%20to%0Agive%20a%20couple%20of%20examples%20and%20regard%20that%20as%20the%20specification%21%20The%0Aexamples%20should%20illustrate%20and%20elucidate%20a%20clearly-articulated%0Aspecification%20that%20covers%20the%20general%20case.%0A%0AExamples%0A--------%0AThis%20section%20illustrates%20the%20specification%20through%20the%20use%20of%20examples%20of%20the%0Alanguage%20change%20proposed.%20It%20is%20best%20to%20exemplify%20each%20point%20made%20in%20the%0Aspecification%2C%20though%20perhaps%20one%20example%20can%20cover%20several%20points.%20Contrived%0Aexamples%20are%20OK%20here.%20If%20the%20Motivation%20section%20describes%20something%20that%20is%0Ahard%20to%20do%20without%20this%20proposal%2C%20this%20is%20a%20good%20place%20to%20show%20how%20easy%20that%0Athing%20is%20to%20do%20with%20the%20proposal.%0A%0AEffect%20and%20Interactions%0A-----------------------%0AYour%20proposed%20change%20addresses%20the%20issues%20raised%20in%20the%20motivation.%20Explain%20how.%0A%0AAlso%2C%20discuss%20possibly%20contentious%20interactions%20with%20existing%20language%20or%20compiler%0Afeatures.%20Complete%20this%20section%20with%20potential%20interactions%20raised%0Aduring%20the%20PR%20discussion.%0A%0ACosts%20and%20Drawbacks%0A-------------------%0AGive%20an%20estimate%20on%20development%20and%20maintenance%20costs.%20List%20how%20this%20affects%0Alearnability%20of%20the%20language%20for%20novice%20users.%20Define%20and%20list%20any%20remaining%0Adrawbacks%20that%20cannot%20be%20resolved.%0A%0AAlternatives%0A------------%0AList%20alternative%20designs%20to%20your%20proposed%20change.%20Both%20existing%0Aworkarounds%2C%20or%20alternative%20choices%20for%20the%20changes.%20Explain%0Athe%20reasons%20for%20choosing%20the%20proposed%20change%20over%20these%20alternative%3A%0A%2Ae.g.%2A%20they%20can%20be%20cheaper%20but%20insufficient%2C%20or%20better%20but%20too%0Aexpensive.%20Or%20something%20else.%0A%0AThe%20PR%20discussion%20often%20raises%20other%20potential%20designs%2C%20and%20they%20should%20be%0Aadded%20to%20this%20section.%20Similarly%2C%20if%20the%20proposed%20change%0Aspecification%20changes%20significantly%2C%20the%20old%20one%20should%20be%20listed%20in%0Athis%20section.%0A%0AUnresolved%20Questions%0A--------------------%0AExplicitly%20list%20any%20remaining%20issues%20that%20remain%20in%20the%20conceptual%20design%20and%0Aspecification.%20Be%20upfront%20and%20trust%20that%20the%20community%20will%20help.%20Please%20do%0Anot%20list%20%2Aimplementation%2A%20issues.%0A%0AImplementation%20Plan%0A-------------------%0A%28Optional%29%20If%20accepted%20who%20will%20implement%20the%20change%3F%20Which%20other%20resources%0Aand%20prerequisites%20are%20required%20for%20implementation%3F%0A%0AEndorsements%0A-------------%0A%28Optional%29%20This%20section%20provides%20an%20opportunity%20for%20any%20third%20parties%20to%20express%20their%0Asupport%20for%20the%20proposal%2C%20and%20to%20say%20why%20they%20would%20like%20to%20see%20it%20adopted.%0AIt%20is%20not%20mandatory%20for%20have%20any%20endorsements%20at%20all%2C%20but%20the%20more%20substantial%0Athe%20proposal%20is%2C%20the%20more%20desirable%20it%20is%20to%20offer%20evidence%20that%20there%20is%0Asignificant%20demand%20from%20the%20community.%20%20This%20section%20is%20one%20way%20to%20provide%0Asuch%20evidence.%0A

.. link generated with
   python3 -c "from urllib.parse import quote;print('https://github.com/hail-is/hail-rfc/new/main?filename=rfc/0000-new-proposal.rst;message=%s;value=%s' % (quote('Start new proposal'), quote(open('rfc/0000-template.rst', 'r').read())))"

The pull request summary should include a brief description of your
proposal, along with a link to the rendered view of proposal document
in your branch. For instance,

.. code-block:: md

    This is a proposal augmenting our existing `Typeable` mechanism with a
    variant, `Type.Reflection`, which provides a more strongly typed variant as
    originally described in [A Reflection on
    Types](http://research.microsoft.com/en-us/um/people/simonpj/papers/haskell-dynamic/index.htm)
    (Peyton Jones, _et al._ 2016).

    [Rendered](https://github.com/bgamari/ghc-proposals/blob/typeable/proposals/0000-type-indexed-typeable.rst)

How to amend an accepted proposal
---------------------------------

Some proposals amend an existing proposal. Such an amendment :

* Makes a significant (i.e. not just editorial or typographical) change, and hence warrants approval by the Hail team
* Is too small, or too closely tied to the existing proposal, to make sense as a new standalone proposal.

Often, this happens
after a proposal is accepted, but before or while it is implemented.
In these cases, a PR that _changes_ the accepted proposal can be opened. It goes through
the same process as an original proposal.

Discussion goals
----------------

Members of the Hail community are warmly invited to offer feedback on
proposals. Feedback ensures that a variety of perspectives are heard, that
alternative designs are considered, and that all of the pros and cons of a
design are uncovered. We particularly encourage the following types of feedback,

- Completeness: Is the proposal missing a case?
- Soundness: Is the specification sound or does it include mistakes?
- Alternatives: Are all reasonable alternatives listed and discussed. Are the pros and cons argued convincingly?
- Costs: Are the costs for implementation believable? How much would this hinder learning the language?
- Other questions: Ask critical questions that need to be resolved.
- Motivation: Is the motivation reasonable?


How to comment on a proposal
-----------------------------

To comment on a proposal you need to be viewing the proposal's diff in "source
diff" view. To switch to this view use the buttons on the top-right corner of
the *Files Changed* tab.

.. figure:: rich-diff.png
    :alt: The view selector buttons.
    :align: right

    Use the view selector buttons on the top right corner of the "Files
    Changed" tab to change between "source diff" and "rich diff" views.

Feedback on a open pull requests can be offered using both GitHub's in-line and
pull request commenting features. Inline comments can be added by hovering over
a line of the diff.

.. figure:: inline-comment.png
    :alt: The ``+`` button appears while hovering over line in the source diff view.
    :align: right

    Hover over a line in the source diff view of a pull request and
    click on the ``+`` to leave an inline comment

For the maintenance of general sanity, try to avoid leaving "me too" comments.
If you would like to register your approval or disapproval of a particular
comment or proposal, feel free to use GitHub's "Reactions"
`feature <https://help.github.com/articles/about-discussions-in-issues-and-pull-requests>`_.

Review criteria
---------------
Here are some characteristics that a good proposal should have.

* *It should be self-standing*.  Some proposals accumulate a long and interesting discussion
  thread, but in ten years' time all that will be gone (except for the most assiduous readers).
  Before acceptance, therefore, the proposal should be edited to reflect the fruits of
  that discussion, so that it can stand alone.

* *It should be precise*, especially the "Proposed change specification"
  section.  Language design is complicated, with lots of
  interactions. It is not enough to offer a few suggestive examples
  and hope that the reader can infer the rest.  Vague proposals waste
  everyone's time; precision is highly valued.

  We do not insist on a fully formal specification. There is no such baseline to
  work from, and it would set the bar far too high.

  Ultimately, the necessary degree of precision is a judgement that the Hail team
  must make; but authors should try hard to offer precision.

* *It should offer evidence of utility*.  Even the strongest proposals carry costs:

  * For programmers: most proposals make the language just a bit more complicated;
  * For maintainers:  most proposals make the implementation a bit more complicated;
  * For future proposers:  most proposals consume syntactic design space add/or add new back-compat burdens, both of which make new proposals harder to fit in.
  * It is much, much harder subsequently to remove an extension than it is to add it.

  All these costs constitute a permanent tax on every future programmer, language designer, and maintainer.
  The tax may well be worth it (a language without polymorphism
  would be simpler but we don't want it), but the case should be made.

  The case is stronger if lots of people express support by giving a "thumbs-up"
  in GitHub. Even better is the community contributes new examples that illustrate
  how the proposal will be broadly useful.
  The Hail team is often faced with proposals that are reasonable,
  but where there is a suspicion that no one other than the author cares.
  Defusing this suspicion, by describing use-cases and inviting support from others,
  is helpful.

* *It should be copiously illustrated with examples*, to aid understanding. However,
  these examples should *not* be the specification.

Below are some criteria that the Hail team and the supporting
community will generally use to evaluate a proposal. These criteria
are guidelines and questions that the Hail team will consider.
None of these criteria is an absolute bar: it is the Hail team's job to weigh them,
and any other relevant considerations, appropriately.

-  *Utility and user demand*. What exactly is the problem that the
   feature solves? Is it an important problem, felt by many users, or is
   it very specialised? The whole point of a new feature is to be useful
   to people, so a good proposal will explain why this is so, and
   ideally offer evidence of some form.  The "Endorsements" section of
   the proposal provides an opportunity for third parties to express
   their support for the proposal, and the reasons they would like to
   see it adopted.

-  *Elegant and principled*. It is tempting to pile feature upon feature, but we
   should constantly and consciously strive for simplicity.

   This is not always easy. Sometimes an important problem has lots of
   solutions, none of which have that "aha" feeling of "this is the Right
   Way to solve this"; in that case we might delay rather than forge ahead
   regardless.

-  *Specification cost.* Does the benefit of the feature justify the
   extra complexity in the language specification? Does the new feature
   interact awkwardly with existing features, or does it enhance them?
   How easy is it for users to understand the new feature?

-  *Implementation cost.* How hard is it to implement?

-  *Maintainability.* Writing code is cheap; maintaining it is
   expensive. Hail is a large piece of software maintained by a small team.
   It is tempting to think that if you propose a feature *and* offer a patch
   that implements it, then the implementation cost to Hail is zero and the
   patch should be accepted.

   But in fact every new feature imposes a tax on future implementors, (a)
   to keep it working, and (b) to understand and manage its interactions
   with other new features. In the common case the original implementor of
   a feature moves on to other things after a few years, and this
   maintenance burden falls on others.

How to build the proposals?
---------------------------

The proposals can be rendered by running::

   make html

This will then create a directory ``_build`` which will contain an ``index.html``
file and the other rendered proposals. This is useful when developing a proposal
to ensure that your file is syntax correct.


Questions?
----------

Feel free to contact any of the members of the Hail team.
See `get help <https://hail.is/gethelp.html>`_ on the website for details.


Acknowledgements
----------------
The structure, wording, templates and configurations has been lifted from
`ghc-proposals/ghc-proposals <https://github.com/ghc-proposals/ghc-proposals>`_.

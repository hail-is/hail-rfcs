# hail team process updates (proposal)

## github issues

### main support channel

#### old template

<img width="1125" alt="Screenshot 2024-01-31 at 12 28 40" src="https://github.com/iris-garden/hail-rfcs/assets/84595986/a49aa5eb-cc6e-4d6a-ac4e-a52c39c1df55">

<img width="824" alt="Screenshot 2024-01-31 at 12 28 52" src="https://github.com/iris-garden/hail-rfcs/assets/84595986/47802f51-7440-4d3a-948d-173537bba786">

#### new template

<img width="746" alt="Screenshot 2024-01-31 at 12 27 21" src="https://github.com/iris-garden/hail-rfcs/assets/84595986/f4863dc4-1e37-46cb-a199-001c1b958f95">

<img width="830" alt="Screenshot 2024-01-31 at 12 28 05" src="https://github.com/iris-garden/hail-rfcs/assets/84595986/5f03e2ab-b686-4375-bf3d-9866397089fb">

* additionally, labels for query support and batch support to be added

## discourse (discuss.hail.is)

### migrate to github issues

* use
  [script](https://github.com/iris-garden/test-process/blob/main/discourse_migration.py)
  to create a github issue for each remaining topic and post a link to it
* create a pinned topic saying that we've migrated
* [disable creation of new topics or posts](https://meta.discourse.org/t/shut-down-the-forum-turn-off-posting/89542/5)
* after a month, shut down the board

## zulip

### consolidate channels

<img width="267" alt="261082794-ceb3798c-0551-4b84-87b0-bf58b89f6263" src="https://github.com/iris-garden/hail-rfcs/assets/84595986/f6e31537-1583-476e-931c-8d985dde0a57">

* `#linalg`, `#test`, `#zulip`
  * no replacement needed
* `#announce`
  * use `#general` instead
* `#workshop`
  * use per-workshop channels like existing `#atgu welcome workshop 2022` instead
* `#cloud support`, `#discussposts`, `#devforumposts`, `#feature requests`,
  `#hail 0.1 support`, `#hail batch support`, `#hail query 0.2 support`
  * use labeled GitHub Issues instead
* new channel: `#time sensitive support`

### open questions

* `#github`: does anyone currently use this instead of normal github notifs?

## slack

### open questions

* are any of these broad slack channels still in use?
  * `#hail-on-terra`, `#hail-single-cell`, `#hail-seqr-database`,
    `#hail-lab-meeting`, `#hail-aou`, `#hail_joint_calling_200ukbb`
* how about these on the atgu slack?
  * `#hail-announcements`, `#port_gnomad_methods_into_hail`

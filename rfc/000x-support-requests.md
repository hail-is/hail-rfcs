# hail team process updates (proposal)

## github issues

### main support channel

* update the template and available labels to allow users to narrow the scope of
  the triage

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

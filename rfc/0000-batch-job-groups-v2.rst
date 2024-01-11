========================
Job Groups in Hail Batch
========================

.. author:: Jackie Goldstein
.. date-accepted:: Leave blank. This will be filled in when the proposal is accepted.
.. ticket-url:: Leave blank. This will eventually be filled with the ticket URL which will track the progress of the implementation of the feature.
.. implemented:: Leave blank. This will be filled in with the first Hail version which implements the described feature.
.. header:: This proposal is `discussed at this pull request <https://github.com/hail-is/hail-rfc/pull/0>`_. **After creating the pull request, edit this file again, update the number in the link, and delete this bold sentence.**
.. sectnum::
.. contents::
.. role:: python(code)

Hail Batch allows users to execute containerized workflows on a
multi-tenant compute cluster. Users submit a single batch which
consists of the set of job specifications to execute and the
dependencies between jobs. A batch can be dynamically updated with
additional jobs. However, there is no notion of structure within a
batch. Therefore, we propose adding a new feature in Batch which
allows users to organize jobs into groups that can be referenced for
key operations such as computing the status, billing information, and
cancellation. The main motivating use case for this feature is Query
on Batch (QoB). QoB needs more fine-grained cancellation abilities in
order to avoid doing unnecessary work after a failure occurs in order
to be comparable in cost to Query on Spark (QoS). The main challenges
of implementing job groups are to make sure key user operations are
still performant while minimizing code complexity on the server and in
the database. We will implement job groups as a nested hierarchical
job group tree.


----------
Motivation
----------

Hail Batch is a multi-tenant batch job processing system. The Hail
team maintains deployments in GCP and Azure. There are also a few
deployments outside of the control of the Hail team as well as alpha
support in Terra. Hail Batch has two main use cases: (1) a batch job
processing system that executes arbitrary bash or Python code in
containerized environments that are generated using a Python client
library that handles file localization and job dependencies in a
user-friendly manner (hailtop.batch) and (2) as the backend for
running Hail Query on Batch (QoB) inside containers running Hail team
approved JVM byte code. Therefore, any new features to the Batch
System should take into account the needs and usage patterns of these
two main use cases.

Typical users of hailtop.batch are looking to execute code for a
stand-alone scientific tool that can be run massively in parallel such
as across samples in a dataset and regions in a genome. Their
workloads usually consist of a single scatter layer with no
dependencies between jobs with sizes on the order of 100s to 100Ks of
jobs. The largest batch that has been processed by the Hail Batch
system is ~16 million jobs. Likewise, QoB consists of a single,
nonpreemptible driver job and subsequent sets of updates of jobs to
the directed acyclic graph (DAG) for subsequent stages of worker
jobs. There is a single job per partition within a stage. The number
of jobs within a stage can be on the order of 100K jobs. For both
types of use cases, Hail Batch needs to be performant in the regime
where each job is a no-op taking 10ms as well as taking hours to
complete. These workload properties are important to keep in mind when
discussing the performance implications of any new features.

The Hail Batch system provides a user interface through both a web
browser and a REST API to interact with batches and check the status
and billing information of a batch, cancel a batch, and list
individual jobs within a batch to get more information on each
job. Right now, there is no organization inside a batch. For example,
the UI page lists the status and total cost for all jobs in the
batch. Recently, we have added code to be able to do an advanced
search for jobs in the batch in order to find specific jobs more
easily. However, the advanced search does not enable a user to see the
organizational structure of their pipeline. For example, you cannot
see in the UI that a QoB pipeline might have a single driver job with
5 stages all executing various parts of the pipeline.

After a focus group with Hail Batch users who are not using QoB, we
realized that their use case does not require a sophisticated
mechanism for organizing jobs in the UI as their pipelines are mainly
just a single scatter. However, users of QoB would benefit from better
organizational structure in the UI. A natural organizational structure
is one of a nested job hierarchical tree where each "session" is like
a child directory at the top level and each "session" contains a
driver job and then children directories corresponding to each stage
of the execution pipeline. Therefore, a single interactive Python or
notebook session corresponds to a single batch and every new query is
organized within the batch. Without any organizational structure, the
jobs for all queries would be concatenated together making it
difficult to see what job corresponded to what query. Even more
challenging is the current implementation creates a new batch after a
user cancels a currently running workflow despite being in the same
Python interactive session.

In addition, the lack of fine-grained cancellation is detracts from
the QoB experience for both users and developers. QoB cannot cancel a
subset of jobs (i.e. cancel all the worker jobs without cancelling the
driver job itself) which means we can't use more sophisticated
cancellation features in Batch like cancelling the batch after N
failures have been seen (fail fast). This means QoB users will spend
more than necessary for failed batches and experience longer feedback
loops between when a query is submitted and they get the result back,
especially for large datasets. For developers, we have to special-case
how we detect when a batch is complete by subtracting 1 from the
number of jobs that we need to wait to complete so we do not have the
driver job wait for itself to complete.

When considering how to improve the experience for both regular Hail
Batch and QoB users, we asked broader questions of what does a batch
represent? Is it more akin to an active workspace that users can
continually submit jobs to as desired? Or does it represent a single
execution pipeline that can be amended as the pipeline progresses?
What kind of organizational structures are needed? Do we want a flat
structure where jobs can be given as many arbitrary user-defined
labels as desired or do we want a hierarchical tree where each job
belongs to a given location or path in the tree and is a member of all
of the groups up the tree hierarchy.

The goal of this new feature is to improve the user and developer
experience for QoB while maintaining the performance of the overall
system and not adding extra unnecessary complexity and developer
overhead to our code base. While it would have been nice to support a
more expressive and flexible way of interacting with jobs in a batch,
we ultimately decided the extra complexity needed in the
implementation outweighed the benefits to users. Therefore, we decided
to implement job groups as a hierarchical tree that can be later
incorporated into the UI.


----------------------------
How the Current System Works
----------------------------

The current Batch system primarily consists of a front-end and a
driver web server that are running in a Kubernetes cluster. The
front-end handles user requests such as creating new batches and
cancelling batches. The driver's primary function is to provision new
resources or worker VMs in response to user demand and then schedule
jobs to execute on workers with free resources.

In separate developer documentation, we have described in detail how
the entire Batch system works. For the purposes of understanding the
changes necessary to implement job groups, we will focus on how the
following key operations are currently implemented here as these are
the operations that must be performant in any job groups
implementation:

**********
Job States
**********

The table `batches_n_jobs_in_complete_states` tracks the total number
of jobs that are completed plus columns for the number of jobs in each
specific terminal state (cancelled, failed, succeeded). This table is
initialized at 0 when creating a batch. When a job is marked complete,
this table is incremented accordingly based on the job's completion
state.


************
Cancellation
************

The table `batch_inst_coll_cancellable_resources` keeps track of the
number of cancellable "Ready" and "Running" jobs and cores in order to
do an O(1) update to the `user_inst_coll_resources` table. The
`user_inst_coll_resources` table is necessary for quickly computing
the fair share of resources between users (VMs to provision, free
cores to schedule on, and individual-level job cancellation
operations). The `jobs_after_update` trigger makes sure the counts of
cancellable jobs is up-to-date after a job is created or the job state
changes. The `cancel_batch` stored procedure subtracts the aggregated
cancellable resource counts from the
`batch_inst_coll_cancellable_resources` table to the
`user_inst_coll_resources` table upon a cancellation event. Whether a
batch has been cancelled is maintained in the table
`batches_cancelled` table.


*******
Billing
*******

The table `aggregated_batch_resources_v2` keeps track of the
aggregated usage per resource per batch. This table is kept up-to-date
via two triggers: `attempt_resources_after_insert` and
`attempts_after_update`. When we insert new resources for an attempt,
the `attempt_resources_after_insert` trigger adds new records or
updates existing records for that batch into the
`aggregated_batch_resources_v2` table for any usage of resources that
has already occurred. Likewise, the `attempts_after_update` trigger
updates the `aggregated_batch_resources_v2` when the duration of the
attempt is updated in the database using a rollup time for
intermediate billing updates.


-----------------------------
Proposed Change Specification
-----------------------------

We will add the concept of a job group throughout the Hail Batch
system including the client libraries, the server, and the database. A
job group is defined to be a set of jobs. A batch contains multiple
job groups in a nested hierarchical structure. A job can only belong
to one job group. However, that job is also implicitly a member of all
job groups that its job group is a child of. There is always a root
job group that is equivalent to a batch that contains all jobs in the
batch. A job group can be queried to list all of the jobs in the
group, get the aggregated status of all jobs in the group including
state and billing information as well as provide a mechanism for
cancelling all the jobs in the group. This interface provides the
minimum functionality necessary to be able to wait for completion of
and cancel a set of jobs which are the QoB use case
requirements. Although we will not change the UI to support job groups
here, the underlying job groups structure proposed can easily be used
to address the UI issues described in the Motivation section.

More concretely, we will create two new tables: `job_groups` and
`job_group_self_and_ancestors`. The `job_groups` table stores information about
the job group such as the n_jobs, callback, cancel_after_n_states,
time_created, and time_completed. The `job_group_self_and_ancestors` table stores
the parent child relationships between job groups densely as an
ancestors table. The following tables will now be parameterized by
both (batch_id, job_group_id) instead of (batch_id) with the default
value for job_group_id being 0, which is the root job group:

- `batches_cancelled`
- `aggregated_batch_resources_v2`
- `batches_inst_coll_cancellable_resources`
- `batch_attributes`
- `batches_n_jobs_in_complete_states`

The following are the primary keys for key Batch concepts. Note that the
primary key for a job has not changed and is not parameterized by the job
group ID.

- batch: (`id`)
- job: (`batch_id`, `job_id`)
- job_group: (`batch_id`, `job_group_id`)

In addition, note that the `batch_updates` table is not parameterized
by a job group id because an update is a separate concept and an
update can contain jobs from multiple job groups. The update is just
the staged "transaction" of changes to be made to the batch rather
than the job organization.

The front end will need the following new REST endpoints:

- GET /api/v1alpha/batches/{batch_id}/job_groups
- GET /api/v1alpha/batches/{batch_id}/job_groups/{job_group_id}
- POST /api/v1alpha/batches/{batch_id}/job_groups
- PATCH
  /api/v1alpha/batches/{batch_id}/job_groups/{job_group_id}/cancel


We describe the following key operations in more detail below.

- Job Group Creation
- Getting the Status
- Cancellation
- Billing
- Job Group Completion


******************
Job Group Creation
******************

A job group is created upfront and is empty. Each job group has an
identifier that is keyed by (batch_id, job_group_id). It also has a
human-readable string path identifier. The root job group is "/" and
always has job group ID equal to 1. All job groups must be explicitly
created by the user and all parent job groups must be created before
their child job groups. In other words, we will not support the
equivalent of `mkdir -p`. Subsequently, when jobs are created, the
request must define which job group the job is a member of. Note that
job groups are independent of batch updates -- a job can be added to
an already existing job group from a previous update.

The client will create job groups as part of a batch update
operation. This is analogous to how jobs are currently submitted.  The
reason for creating jobs in an atomic operation rather than as a
separate operation is to preserve atomicity in the event of a
failure. From the user's perspective, they assume that `b.run()` is an
atomic operation. If an error occurs during submission, then the user
shouldn't see partially submitted jobs or job groups in the
UI. Instead, they shouldn't "exist" until the update has been
committed. The `batch_updates` table will have two new fields that are
used to reserve a block of job group IDs: `start_job_group_id` and
`n_job_groups`.  The client can then reference relative `in_update`
job group IDs within the update request and all job group IDs within
the update are guaranteed to be contiguous. By using the
`batch_updates` framework and creating a reservation through an
update, we allow multiple clients to be creating job groups to the
same batch simultaneously.


******************
Getting the Status
******************

There is no change in how states are tracked from the current system
as we are reusing the existing `batches_n_jobs_in_complete_states`
table by adding a new key which is the job group ID. We know the root
job group is equivalent to the entire batch and can query for that row
specifically when interested in a batch. The update when marking a job
complete is still one query, but is more complicated with a join on
the new `job_group_parents` table that propagates the state increment
to the corresponding rows in the job group tree. To ensure this
operation is fast, we will limit the depth of the job group tree to 5.


************
Cancellation
************

An entry for the new job group is inserted as an additional row into
the `batch_inst_coll_cancellable_resources` table upon job group
creation. The `jobs_after_update` trigger will update the rows after a
job state change, but the queries are more complicated because we need
to update all rows for job groups the job is a member of. We use the
new `job_group_parents` table to propagate the updates up the job
group tree. When a job group is cancelled, we subtract the number of
cancellable cores in that job group from all parent job groups up the
tree and then delete all rows corresponding to the job group and child
job groups from the `batch_inst_coll_cancellable_resources`
table. This deletion operation has to delete O(n_children) job groups,
so we need to put a limit on the total number of job groups allowed in
the batch to 10K to ensure the deletion query can complete in less
than a second.


*******
Billing
*******

The `attempt_after_update` and `attempt_resources_after_insert`
triggers will be modified to increment all rows in the
`aggregated_batch_resources_v2` table corresponding to a job group
that job is a member of in the tree. To ensure this operation is fast,
we will limit the depth of the job group tree to 5.


********************
Job Group Completion
********************

When a job is marked complete, all job groups the job is a member of
are updated in the `batches_n_jobs_in_complete_states` table. We also
check to see if the number of jobs in the job group is equal to the
number completed. We are guaranteed that the job that sees the number
of jobs equals the number completed is the last job to complete
despite no locking being done. We then execute the callback for any
newly completed job groups. The amount of extra overhead in the mark
job complete SQL procedure compared to what we have now is
O(n_job_groups) the job is a member of, which is bounded to be 5.


--------
Examples
--------

We will use the Python client implemented in ``aioclient.py`` to demonstrate the interface.

First, we create a batch with a job group "session1" and no jobs in it.

.. code::python

    bb = client.create_batch()
    session1 = bb.create_job_group(name='session1')
    b = bb.submit()

Next, we create a job group for a query we want to execute and add a driver job to it.

.. code::python

    q1 = bb.create_job_group('query1', parent=session1)
    driver_j = q1.create_job(name='driver')
    bb.submit()

Next, we want to add an update to the batch with a stage of worker
jobs and say for the stage to cancel itself if there's at least one
failure.

.. code::python

    bb = client.update_batch(b.id)
    stage1 = bb.create_job_group(name='stage1', parent=q1, cancel_after_n_failures=1)
    for i in range(5):
        stage1.create_job(name=f'worker{i}')
    bb.submit()

We then want to wait for the stage to complete:

.. code::python

    stage1.wait()

Once it completes, we want to check the cost of the stage:

.. code::python

    status = stage1.status()
    cost = status['cost']

We then submit another stage ("stage2"), but this one is taking a long
time. We want to cancel it!

.. code::python

    stage2 = b.get_job_group('/session1/query1/stage2')
    stage2.cancel()


-----------------------
Effect and Interactions
-----------------------

My proposed changes address the issues raised in the motivation by
providing the following features:

1. Expose a way to quickly cancel a subset of jobs in a batch.
2. Expose a way to quickly cancel a subset of jobs in a batch after a
   specified number of failures in the group.
3. Expose a way to quickly find the status of a subset of
   jobs in a batch.
4. Expose a tree hierarchy structure for jobs to improve the user
   experience in both the UI and for QoB interactive sessions.

There are no interactions with existing features. This feature
proposal is purely an addition to what we have in our system currently
and maintains backwards compatibility.


-------------------
Costs and Drawbacks
-------------------

The development cost for this feature is high although substantial
prototyping has already been done in this space. There are a lot of
places in the code base this feature touches such as the database
tables, triggers, and stored procedures, the new REST API interface
and implementation on the Batch front end, and all of the Python and
Scala client libraries. Writing tests for this feature is time
consuming as there are a lot of cases to consider because we have a
number of different code paths for creating and updating a batch and
we want to make sure billing and cancellation are done properly in
different scenarios.

We will need to write a series of database migrations. Most database
operations are fast because we are instantly adding columns with
default values of 1. However, the job_groups and job_group_parents
tables need to be populated from scratch by copying the relevant
information from the existing `batches` table.

Backwards compatibility is not an issue in this plan.

The maintenance costs for this feature are moderate. There is another
level of abstraction in our data model that must be accounted for when
adding new features in the future or planning a future rewrite of the
entire system. The SQL queries are also more complicated as updates
need to propagate up and down the job group tree.

The proposed simplifications to how cancellation are done will
increase future developer productivity as this has always been a
tricky and confusing part of our system especially with how it relates
to always_run jobs.


------------
Alternatives
------------

1. The existing workaround QoB uses when waiting on a wave of worker
   jobs to complete is to poll for when the number of completed jobs is
   equal to the number of jobs in the batch minus 1 to compensate for the
   driver job. This logic is not straightforward. There are no existing
   workarounds for a driver job to be able to cancel a wave of worker
   jobs without cancelling itself.

2. We do not implement a job group tree. Jobs can optionally belong to
   a job group. Job groups are disjoint sets. Counterintuitively, this
   design is actually more complicated to implement than a nested job
   group hierarchy. In addition, we would not have a tree
   representation for future UI optimizations.

3. We implement a job group tree, but do not have a root job group
   that is equivalent to the current batch. The database
   representations in this approach would duplicate all of the
   batch-related tables for job groups. This duplication would add
   more opportunities for error and we'd need to write more
   complicated queries to traverse the tree. The proposed approach
   will be easier to maintain with minimal extra database overhead.

4. We implement job groups as an arbitrary set of jobs. Jobs can
   belong to multiple job groups. Although the interface for this
   design allowed more flexibility for future use cases, the
   implementation required a significantly more complicated
   cancellation strategy. The benefits of increased flexibility did
   not outweigh the extra code complexity.


--------------------
Unresolved Questions
--------------------

None.

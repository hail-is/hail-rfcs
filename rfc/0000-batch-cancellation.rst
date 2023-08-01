===========================
Batch Cancellation Strategy
===========================

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
dependencies between jobs. A major part of the Batch system is
cancellation. A cancellation event can be initiated by the user or by
the system and causes all currently running jobs in the batch to be
terminated and no further jobs can be executed (unless they are set to
always_run). This feature is important for stopping workflows that are
not behaving as expected and for controlling costs. For example, a
user might want to cancel a batch if they notice all of their jobs are
failing or their jobs are taking substantially longer than
expected. The system also cancels batches if the billing limit for the
project has been exceeded or the user has specified they want their
batch to be automatically cancelled after N failures. The current
implementation of cancellation in Batch relies on a series of tables
that keep track of the number of jobs that are **cancellable** with
different job states such as running, ready, and creating. When a user
cancels a batch, a single database operation instantly changes the
workload demands on the system causing the autoscaler and scheduler to
react immediately to the cancellation event by not spinning up
resources for the cancelled jobs and not scheduling the jobs on
existing workers. While this implementation is extremely performant,
the database structures necessary to bookkeep the number of resources
in each state is not flexible for new features we'd like to add to the
Batch system such as job groups. It also is tricky to understand and
modify this part of the code base leading to more developer overhead
and slower feature development. This proposal reviews how cancellation
works in the current system and compares options for other
cancellation implementations before recommending a new simpler
implementation.


----------
Motivation
----------

Cancellation is a key operation in the Batch system. It must be as
fast as possible to avoid provisioning resources for jobs that users
no longer want to run as well as not impeding other users (or batches)
from being able to have their jobs run. The current implementation of
cancellation does not allow for any flexibility in which jobs are
cancelled. This lack of fine-grained control over which jobs are
running in a batch is an impediment to the Query on Batch (QoB) use
case. QoB wants to be able to cancel all worker jobs in a stage
automatically after one failure without having to cancel the entire
batch which includes the driver job. The lack of being able to cancel
a stage after one failure is one of the last remaining features needed
for QoB to have feature parity with Query on Spark (QoS). Not being
able to cancel a QoB batch after one failure leads to increased user
costs. There are no current work arounds for this lack of
functionality. Therefore, we need to add more fine-grained
cancellation abilities to the Batch interface. In addition, we
independently need a simpler, easier to maintain implementation of
cancellation in the Batch system in order to increase our development
speed on new features and reduce the complexity of our code base. With
the QoB use case as the primary motivation, we seek to implement a
different cancellation strategy in the Batch system that will provide
the foundation for other features that will need more fine-grained
cancellation abilities such as being able to cancel a subset of jobs
that match a user-defined filtering string.


----------------------------
How the Current System Works
----------------------------

The current Batch system consists of a front-end and a driver web
server that are running in a Kubernetes cluster. The front-end handles
user requests such as creating new batches and cancelling batches. The
driver's primary function is to have an autoscaler that provisions new
resources or worker VMs in response to user demand as well as a
scheduler that schedules jobs to execute on workers with free
resources.

Demand in the system is measured as the total number of cores
requested by jobs that are "Ready" to run. "Ready" means all jobs that
are parent dependencies of the job of interest have finished and the
job is ready to be executed on a worker. For jobs that are not set to
always run, all parents must have succeeded for the job to be
"Ready". Otherwise, the job's state is automatically set to
"Cancelled". However, this is not the case for jobs that are set to
always run -- these jobs run regardless of the completion state of
their parents and will continue to run even if the entire batch has
been cancelled. (Aside: a feature to add more fine grained control to
the "always run" functionality has been explored in the past and is
something that can be revisited again especially since always_run jobs
will continue to run even if the billing limit for the project has
been exceeded). Note that a job can be cancelled due to failed parent
dependencies even if the batch has not been "cancelled".

The driver executes a query that scans the head of the job queue to
count the current amount of ready cores across all users and decides
how many worker VMs to provision with some optimizations to take into
account region preferences and user fair share of the cluster. In
order to avoid having one user starve other users from getting their
jobs run, we use the following fair share algorithm to determine user
shares. We start with the user who has the fewest cores running. We
then allocate as many cores as possible that are live in the cluster
until we reach the number of cores the next user has currently
running. We then divide up the remaining cores equally amongst the two
users until we reach the number of cores the next user has running. We
repeat until we have either exhausted all free cores in the cluster or
have satisfied all user resource requests. These fair share
allocations are then translated into a concrete number of jobs that
can be scheduled per user in each autoscaling loop. We then find the
sum of CPU resources requested for each user's share of jobs and then
apply some further optimizations to account for which regions a job
can run in to come up with the final number of worker VMs that should
be provisioned. The query to get the number of ready cores in the fair
share algorithm is fast because we aggregate across a global table
``user_inst_coll_resources`` that has a limited number of rows
maintaining counts of the number of ready cores per instance
collection and user.

The key insight in our current system for a fast cancellation
implementation is to be able to do an O(1) update of the
``user_inst_coll_resources`` table that keeps track of the number of
ready cores and jobs upon cancelling the batch by subtracting the
number of **cancellable** resources and jobs for that batch. This way
both the autoscaler and scheduler instantly see this change in demand
with their respective fair share algorithms. In addition, the
autoscaler will not provision unnecessary resources for the cancelled
batch as the query that scans the head of the jobs table will ignore
jobs that are "Ready" but in batches that have been
cancelled. Likewise, the SQL query the scheduler uses will ignore
"Ready" jobs for batches that have been cancelled and the fair share
algorithm will instantly adapt to the change in demand from the
cancelled batch to schedule other users and batches fairly.

More concretely, there are two tables that keep track of resources:

- ``user_inst_coll_resources``: Keeps track of the total number of
  jobs and cores for each user and instance collection for jobs in
  Ready, Running, and Creating states as well as the number of
  cancelled jobs in each state. Note this table is not parameterized
  by batch ID.
- ``batch_inst_coll_cancellable_resources``: Keeps track of the total
  number of **cancellable** jobs and cores for jobs in Ready, Running,
  and Creating states. Note this table is parameterized by
  batch id. The numbers in this table do not include counts for
  **always_run** jobs as they cannot be cancelled.

These two tables are tokenized for fast concurrent
updates. Tokenization means that the value for a single key in the
database is represented by up to 200 rows in order to avoid
serialization of updates. Therefore, to compute the number of jobs or
free cores, the query must do an aggregation for all rows for a given
key which can be up to 200 rows.

These two database tables are kept up to date with a trigger on the
``jobs`` table after updates. This trigger increments and decrements
the corresponding rows in these tables based on the previous job state
and the new job state. The code in the trigger is extremely
complicated as it has to take into account the current job state,
whether the batch has been cancelled, whether the job has been
cancelled (failed parent dependencies), and whether the job is
**always_run**. This trigger is currently ~170 lines and contains many
nested if-else statements that are easy to make mistakes on when
refactoring the code.

When a batch is cancelled by either the user or the system
("cancel_after_n_failures" or billing limits have been reached), the
following occurs:

1. A row for that batch id is inserted into a table that keeps track
   of the batches that have been cancelled.
2. The number of **cancellable** ready cores and number of ready jobs
   for that batch are calculated by aggregating over the
   ``batch_inst_coll_cancellable_resources`` table and then
   subtracting those counts from the corresponding values in the
   ``user_inst_coll_resources`` table.
3. The rows pertaining to that batch id are deleted from the
   ``batch_inst_coll_cancellable_resources`` table.
4. Background canceller processes on the driver query the database for
   jobs that are either Running, Creating, or Running and are in
   cancelled batches and not **always_run** and then cancels them
   individually. The canceller uses a slightly different fair share
   algorithm to determine the number of jobs to cancel per user in a
   fair share manner.

As a historical note, the ``user_inst_coll_resources`` table that kept
track of the n_ready_cores was a critical part of the autoscaler
before changes in October 2022 were made to consider only the head of
the job queue and compute the number of ready cores on the fly rather
than from the aggregated global value. However, the fields in the
``user_inst_coll_resources`` table are still used by the fair share
algorithms, so we cannot remove these tables altogether.

In summary, the current system is able to efficiently adapt to a
cancellation event in O(1) operations, but the database structures
that enable this efficiency are difficult to maintain due to the
complexity of the trigger that does the count adjustments and the
database structure is designed for only an entire batch to be
cancelled.


-----------------------------
Proposed Change Specification
-----------------------------

**************
Implementation
**************

Given the design of our current system, any changes to how
cancellation works need to adhere to the following constraints:

1. There must be a mechanism in the database that can be updated in an
   O(1) database operation to indicate a batch has been cancelled.
2. Queries that scan "Ready" jobs must be fast and respond to a
   cancellation event instantaneously to avoid unnecessary
   provisioning of resources.
3. The data the fair share calculation uses must be updated
   instantaneously after a cancellation event or be updated within
   some time window that balances cluster efficiency with code
   complexity or the fair share algorithm must be redesigned entirely.

The proposed changes to the database are to:

1. Create a new table ``user_inst_coll_resources_by_batch`` that is
   almost identical to ``user_inst_coll_resources``, but parameterized
   by an extra field (batch id) and splits the number of ready jobs to
   "n_ready_always_run_jobs", "n_ready_cancellable_jobs" and likewise
   for cores and also removes the counts of "n_cancelled_*" fields.
2. Remove the existing ``batch_inst_coll_cancellable_resources``
   table.
3. Remove the `n_cancelled_ready_jobs`, `n_cancelled_running_jobs`
   etc. columns from the ``user_inst_coll_resources`` table.
4. Update the jobs after update trigger to not update the old
   cancellable resources table or the fields from Step 3 and instead
   update the new ``user_inst_coll_resources_by_batch`` table taking
   into account the **always_run** flag of the job.
5. Modify ``cancel_batch`` to just insert a row into the
   ``batches_cancelled`` table and no longer do the update to the
   ``user_inst_coll_resources`` table that subtracted the number of
   newly cancelled resources.
6. Add a new trigger to the batches table that deletes all rows from
   ``user_inst_coll_resources_by_batch`` for that batch when the batch
   state is set to "completed"


The proposed changes to the driver are:

1. Change the fair share algorithm in the autoscaler to query the new
   ``user_inst_coll_resources_by_batch`` table and ignore the values
   for "n_ready_cancellable_jobs" for batches that have been cancelled
   when computing the total aggregated values while still accounting
   for "n_ready_always_run_jobs" for cancelled batches.
2. Change the fair share algorithm in the scheduler to query the new
   ``user_inst_coll_resources_by_batch`` table and ignore the values
   for "n_ready_cancellable_jobs" for batches that have been cancelled
   when computing the total aggregated values while still accounting
   for "n_ready_always_run_jobs" for cancelled batches. The fair share
   proportions per user are cached for 5 seconds at a time in order to
   be able to have a longer running fair share computation using the
   larger ``user_inst_coll_resources_by_batch`` table with more
   records.
3. Change the fair share algorithm for the canceller to query the new
   ``user_inst_coll_resources_by_batch`` table and only include rows
   for batches that have been cancelled and use only the
   "n_ready_cancellable_jobs" when computing the total aggregated
   values.


There are no proposed changes to the batch driver UI page for either
the individual instance collection pages or the global User Resources
page.


*****************
Safety Mechanisms
*****************

The number of records in the new table
``user_inst_coll_resources_by_batch`` will be proportional to the
number of "active" batches running in the system rather than the
number of users. This could be a huge liability if we have a user
submit 100Ks of batches at once, which has occurred in the past. We
will mitigate this by having all queries that use the
``user_inst_coll_resources_by_batch`` table to compute fair share only
consider the first 50 "running" batches per user when computing fair
share. To do this efficiently, we will either need to write a query
that takes the union of subqueries that is O(n_users) or iterate
through the list of users on the driver and make a query per user with
a bounded gather to compute the fair share statistics per user in
parallel. The current query on the ``user_inst_coll_resources`` table
takes 0.02 seconds. If we multiply the total work by 50, then we'll be
at our target of 1 second.


--------
Examples
--------

An example of a cancellation event propagating through the system:

1. User cancels the batch by sending a request to the front end.
2. The front end inserts a row for that batch into
   ``batches_cancelled``.
3. The front end sends a request to the driver notifying that a
   cancellation event has occurred.
4. The autoscaler computes the fair share from the new
   ``user_inst_coll_resources_by_batch`` table as described
   above. When computing the head of the job queue to determine the
   number of ready cores per region, all cancellable "Ready" jobs are
   skipped in the result set for the cancelled batch.
5. The scheduler computes the fair share from the new
   ``user_inst_coll_resources_by_batch`` table as described above and
   ignores cancellable "Ready" jobs that are in a cancelled batch.
6. The canceller computes the new fair share allocations per user as
   described above. The canceller will identify cancelled "Ready" jobs
   that are not always run and marks the job as cancelled in the
   database and will identify cancelled "Running" jobs and unschedules
   those jobs and marks them as cancelled.


-----------------------
Effect and Interactions
-----------------------

There are no backwards compatibility concerns on the user-side
although this proposal does have a database migration. The UI should
be identical to how it is currently and display the same exact
information. We will want to use the cached fair share computed values
to display the number of ready and running cores and jobs per user as
the new table can take up to 1 seconds to compute on.


-------------------
Costs and Drawbacks
-------------------

This plan is reasonably simple to implement. The hardest part of the
plan is populating the new table ``user_inst_coll_resources_by_batch``
and modifying the existing database trigger without making
errors. Populating the new table will be tricky if we cannot simply
create the new table with a single query. Otherwise, we will have to
figure out how to do a live migration and that will take a lot more
time and developer effort. The queries used by the fair share
algorithms will be substantially more complicated and we will need to
benchmark their performance adding to development costs and
maintenance overhead.

The drawbacks to this plan are the fair share SQL query has to be more
complicated and we will no longer consider the entire job queue when
provisioning resources as we limit each user to 50 batches that we'll
consider. This could mean users will see lower throughputs if they
have lots of small batches. There should be no impact on Hail team
costs from this lower throughput as the scheduler should be just as
efficient as it is now.


------------
Alternatives
------------


*****************************
Option 1: Eliminate Fast-Path
*****************************

We could eliminate a fast path for cancellation
completely and rely on cancelling jobs one by one in the
canceller. However, this option is a non-starter because for large
batches, we will provision a lot of extra resources and the user
will incur costs for jobs they did not want running. As the
canceller cannot process jobs that need to be cancelled fast enough
to deplete the "Ready" job quickly enough to guarantee a large batch
will be completely cancelled in an acceptable time range. For
example, cancelling a 16 million job batch would take 22 hours if we
cancel 200 jobs per second.


***********************************
Option 2: Compute Values on the Fly
***********************************

We could compute the number of ready jobs and cores on the fly to
cancel when we receive a cancellation request rather than storing
counts ahead of time in the database. However, this option is not
tenable for large batches. If we can read 50K records per second, it
would take 5 minutes to aggregate and count the number of resources
that are cancelled. Even if we could handle long running queries,
we'd still need to lock the entire table for that batch for 5
minutes. Maybe that is an acceptable amount of waste of resources
even with a large cluster running? If the cluster costs $500 per
hour at peak, that would be a $42 cost to the Hail team.


****************************************************
Option 3: Reenvision the Driver with a Queue Manager
****************************************************

Completely redesign how the driver works by adding a
new queue manager. A new job state "Queued" is added and all jobs
that end up being executed go from Pending -> Queued -> Ready ->
Running -> {Success, Error, Failed, Cancelled}. The queue manager is
responsible for updating the job state from Queued -> Ready within a
loop. We bound the number of "Ready" jobs such that cancellation can
happen on jobs one by one without requiring extensive bookkeeping on
the number of ready jobs and their always_run state. Each user gets
a background process that iterates through the "Queued" jobs that
are not in cancelled batches or are set to always run. Each
background process "submits" the update request to a new rate
limiter that only allows 200 requests / second (maximum steady state
scheduling rate) and limits the number of "Ready" jobs to a given
number that can be cancelled within 30 seconds. The rate limiter
uses the proportions of users with ready jobs to determine the
frequency to allow their requests when rate limiting is in order. I
have not decided on the exact algorithm for computing the fair share
throttling proportions, but that should not be too hard to do. A
crude example is a user with 0% of the cluster allocated to them
should have 100 times more requests succeed than a user with 100% of
the cluster in a simple two user example.

With this model, we do not have to worry about tracking the number of
cancellable ready jobs to be able to do an O(1) database update
operation. Instead, the queue manager makes sure cancellation can
happen within an acceptable amount of time by bounding the total
number of "Ready" jobs. The benefits long-term of this model are we
can have more complicated SQL queries for selecting the optimal job
composition to satisfy constraints on regions, maximum number of
concurrent jobs, and burn rate limits without having to have exact
calculations for fair share (the rate limiter handles the fair
share). The autoscaler SQL query can be very simple because it does
not have to globally optimize the head of the job queue taking regions
into account. The actual autoscaling algorithm can be more
sophisticated as it just has to consider a subset of jobs that have
been pre-selected. Finally, the scheduler can be significantly
faster. The query that it uses just needs to find jobs that are
"Ready" without worrying about fair share, cancellation, and always
run. We can get better performance with higher throughputs on the
scheduling query (we don't have to go batch by batch). We can also
eventually use skip locks to have multiple scheduling loops going so
we don't have to wait for 50 jobs to complete scheduling before
querying the database for the next set of jobs that are ready to be
scheduled.

I think this option is better than the current proposed set of changes
in this RFC. However, the cost of development for this approach is
substantial and we need to do something simpler in the short term in
order for QoB to be able to efficiently cancel a subset of jobs.


-----------------------
Extension to Job Groups
-----------------------

This proposal only considers a simpler cancellation strategy for our
current system where job groups do not exist. In a world where job
groups exist (QoB use case), we would need to keep track of whether a
job group is in the process of being cancelled. We assume a job group
is "cancelling" if the job group has been set to cancelled and the
number of jobs does not equal the number of completed jobs. A batch
would be assumed to be "cancelled" for the purposes of the fair share
computation if any job groups are in the process of "cancelling" or
the batch has been explicitly cancelled.

The job groups extension to the cancellation proposal requires the
following job-group specific cancellation infrastructure in the
database:

- ``job_groups`` -- stores the state of the job group as well as the
  option for cancel_after_n_failures
- ``job_groups_n_job_states`` -- keeps track of the number of jobs in
  each state.
- ``job_groups_cancelled`` -- records whether a job group has been
  cancelled

The driver will need to be modified in the following way:

- The exact queries for the scheduler, autoscaler, and canceller will
  need to query whether a job belongs to a cancelled batch OR a
  cancelled job group. This should still be a fast query with a
  lateral join or an "EXISTS" condition, but I'm not 100% sure given
  the additional WHERE condition that is not indexed on the jobs
  table.

Because we mask the cancellable ready resources for the entire batch
even if we're only cancelling one job group, we will potentially
reduce the throughput for running jobs for the entire batch,
especially if the number of jobs in the job group is large and the
entire batch is large and other users are using the cluster. For
example, the worst case I can envision is a batch with 16 million jobs
with a job group with 15 million jobs that need to be cancelled. It
will take almost 21 hours to fully cancel the job group. In the
meantime, all other 1 million jobs will potentially be scheduled at a
lower throughput than Batch is capable of because the fair share
calculation is not seeing the extra 1 million jobs. However, this
scenario is unlikely to occur and is guaranteed to not occur in the
QoB use case.

One concern is we could deadlock the batch if an always run job in a
cancelled job group depends on a job not in that job group. The
deadlock will not occur because the fair share algorithm always gives
a non-zero share for each user. The scheduler and autoscaler will
still try and schedule jobs that are not in the cancelled job group.

Lastly, one consequence of this design is the UI table will no longer
reflect the actual state of the system because the number of ready
resources displayed does not equal the true number of ready
resources. We will need to think carefully about how to display
information about the job states and the user resources in the UI
going forward.


--------------------
Unresolved Questions
--------------------

1. I think the best implementation option is different when
   considering job groups and the QoB use case and what our longer
   term team goals are. If we decide to have job groups be a nested
   hierarchial tree of jobs, then this proposal may not be the optimum
   anymore. I am hesitant to consider each of these changes in
   isolation.

2. I think we should consider Option 2 as a possible solution if my
   ballpark estimates are correct on the potential costs to the Hail
   team and explore Option 3 more in parallel as a way to simplify the
   entire system, address outstanding bugs, and provide a foundation
   for faster feature additions. However, the solution I have proposed
   in this RFC is the simplest short term solution that satisfies the
   design constraints if Option 2 is not tenable.
 

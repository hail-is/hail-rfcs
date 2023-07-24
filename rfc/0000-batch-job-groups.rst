========================
Job Groups in Hail Batch
========================

.. author:: Jackie Goldstein
.. date-accepted::
.. ticket-url::
.. implemented::
.. header:: This proposal is `discussed at this pull request <https://github.com/hail-is/hail-rfc/pull/0>`_.
            **After creating the pull request, edit this file again, update the
            number in the link, and delete this bold sentence.**
.. sectnum::
.. contents::
.. role:: python(code)

Hail Batch allows users to execute containerized workflows on a
multi-tenant compute cluster. Users submit a single batch which
consists of the set of job specifications to execute and the
dependencies between jobs. A batch can be dynamically updated with
additional jobs. However, there is no notion of structure within a
batch. Therefore, we propose adding a new feature in Batch which
allows users to organize jobs into groups that can be referenced
together for key operations such as computing the status, billing
information, and cancellation. The main motivating use case for this
feature is Query on Batch (QoB). QoB needs more fine-grained
cancellation abilities in order to improve the developer experience as
well as avoid doing unnecessary work after a failure occurs in order
to be comparable in cost to Query on Spark (QoS). The main challenges
of implementing job groups are to make sure key user operations are
still performant while minimizing code complexity on the server and in
the database. In this proposal, we explore two different
implementations of job groups: (1) A nested hierarchical job tree
structure and (2) an arbitrary set of jobs that is equivalent to
tagging or labeling jobs. After weighing the benefits and tradeoffs of
each approach with regards to expressivity, performance, and code
complexity, we propose that job groups should be implemented as an
arbitrary set of jobs in the Batch system with an additional
light-weight hierarchical job group tree layer that can be implemented
later on to improve performance for defining a job group in QoB and
enhance the user experience. This overall vision for job groups does
not preclude simpler approaches that build up to the full
functionality described here.

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
types of use cases, Hail Batch needs to work in the regime where each
job is a no-op taking 10ms as well as taking hours to complete. These
workload properties are important to keep in mind when discussing the
performance implications of any new features.

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
5 stages all executing various parts of the pipeline. It is difficult
for users and Hail developers to figure out where a failing job
corresponds to in the pipeline based on searching for jobs in the
current UI.

After a focus group with Hail Batch users who are not using QoB, we
realized that their use case does not require a sophisticated
mechanism for organizing jobs in the UI as their pipelines are mainly
just a single scatter. However, users of QoB would greatly benefit
from better organizational structure in the UI. A natural
organizational structure is one of a nested job hierarchical tree
where each "session" is like a child directory at the top level and
each "session" contains a driver job and then children directories
corresponding to each stage of the execution pipeline. Therefore, a
single interactive Python or notebook session corresponds to a single
batch and every new query is organized within the batch. Without any
organizational structure, the jobs for all queries would be
concatenated together making it difficult to see what job corresponded
to what query. Even more challenging is the current implementation
creates a new batch after a user cancels a currently running workflow
despite being in the same Python interactive session. It is extremely
confusing to figure out what batch to look at to understand whether a
pipeline completed successfully. Furthermore, the code we write to
implement QoB is unwieldy due to the inability to wait on a subset of
jobs to complete. We also cannot cancel a subset of jobs (i.e. cancel
all the worker jobs without cancelling the driver job itself) which
means we can't use more sophisticated cancellation features in Batch
like cancelling the batch after N failures have been seen (fail
fast). The lack of fine-grained cancellation impedes development on
QoB and causes unnecessary spending as well as longer lag times for
QoB users when their pipelines have already failed, but continue to
run to completion.

When considering how to improve the experience for both regular Hail
Batch and QoB users, we asked broader questions of what does a batch
represent? Is it more akin to an active workspace that users can
continually submit jobs to as desired? Or does it represent a single
execution pipeline that can be amended as the pipeline progresses?
What kind of organizational structures are needed? Do we want a flat
structure where jobs can be given as many arbitrary user-defined
labels as desired or do we want a hierarchical tree where each job
belongs to a given location or path in the tree and is a member of all
of the groups up the tree hierarchy. This is equivalent to a directory
tree in UNIX. Cancellation must be propagated down the tree while
billing information must be aggregated up the tree. The implementation
of a hierarchy tree is not overwhelmingly difficult once an efficient
representation is implemented in the database. However, the lack of
flexibility may preclude future use cases. For example, we might want
to know what the most expensive parts of a pipeline are or cancel jobs
that are specific to a given cohort in the dataset rather than all
jobs.

The goal of this new feature is to improve the user and developer
experience for QoB while maintaining the performance of the overall
system and not adding extra unnecessary complexity and developer
overhead to our code base as well as building the foundation for a
more expressive and flexible way of interacting with jobs in a batch
for future use cases.


----------------------------
How the Current System Works
----------------------------

The Batch system is a set of services and infrastructure components
that work in concert to allow users to submit requests describing
workloads or sets of jobs to run and then executes the jobs on a set
of worker VMs. The Batch system consists of the following Kubernetes
services and cloud infrastructure components:

- Kubernetes Services
  - Gateway
  - Internal Gateway
  - Auth
  - Batch Front End (batch)
  - Batch Driver (batch-driver)
- Worker VMs
- MySQL Database
- Cloud Storage
- Container Registry

The exact implementation details of each component will be described
separately in a different developer document (does not exist yet).


~~~~~~~~~~~~~~~
Batch Lifecycle
~~~~~~~~~~~~~~~

1. A user submits a request to the Batch front end service to create a
   batch along with job specifications.
2. The Batch front end service records the batch and job information
   into a MySQL database and writes the job specifications to cloud
   storage.
3. The Batch driver notices that there is work available either
   through a push request from the Batch front end or by polling the
   state in the MySQL database and spins up worker VMs.
4. The worker VMs startup and notify the Batch driver they are active
   and have resources to run jobs.
5. The Batch driver schedules jobs to run on the active workers.
6. The worker VM downloads the job specification from cloud storage,
   downloads any input files the job needs from cloud storage, creates
   a container for the job to execute in, executes the code inside the
   container, uploads any logs and output files that have been
   generated, and then notifies the Batch driver that the job has
   completed.
7. Once all jobs have completed, the batch is set to complete in the
   database. Any callbacks that have been specified on batch
   completion are called.
8. Meanwhile, the user can find the status of their batch through the
   UI or using a Python client library to get the batch status, cancel
   the batch, list the jobs in the batch and their statuses, and wait
   for the batch or an individual job to complete. The implementation
   of the wait operation is by continuously polling the Batch Front
   End until the batch state is "complete".


~~~~~~~~~~
Data Model
~~~~~~~~~~

The core concepts in the Batch data model are billing projects,
batches, jobs, updates, attempts, and resources.

A **billing project** is a mechanism for imposing cost control and
enabling the ability to share information about batches and jobs
across users. Each billing project has a list of authorized users and
a billing limit. Any users in the billing project can view information
about batches created in that billing project. Developers can
add/delete users in a billing project and modify billing limits. Right
now, these operations are manually done after a Batch user submits a
formal request to the Hail team. Note that the Hail billing project is
different than a GCP billing project.

A **batch** is a set of **jobs**. Each batch is associated with a
single billing project. A batch also consists of a set of
**updates**. Each update contains a distinct set of jobs. Updates are
distinct submissions of jobs to an existing batch in the system. They
are used as a way to add jobs to a batch. A batch is always created
with 0 updates and 0 total jobs. To add jobs to a batch, an update
must be created with an additional API call and the number of jobs in
the update must be known at the time of the API call. The reason for
this is because an update reserves a block of job IDs in order to
allow multiple updates to a batch to be submitted simultaneously
without the need for locking as well as for jobs within the update to
be able to reference each other before the actual job IDs are
known. Once all of the jobs for a given batch update have been
submitted, the update must be committed in order for the jobs to be
visible in the UI and processed by the batch driver.

A job can have **attempts**. An attempt is an individual execution
attempt of a job running on a worker VM. There can be multiple
attempts if a job is preempted. If a job is cancelled before it has a
chance to run, it will have zero attempts. An attempt has the
**instance** name that it ran on, the start time, and the end
time. The end_time must always be greater than the start_time. All
billing tracking is done at the level of an attempt as different
attempts for the same job can have different resource pricing if the
VM configurations are different (4 core worker vs 16 core worker).

Billing is tracked by **resources**. A resource is a product (example:
preemptible n1-standard-16 VM in us-central1) combined with a version
tag. Each resource has a rate that is used to compute cost when
multiplied by the usage of the resource. Resource rates are in units
that are dependent on the type of resource. For example, VM rates are
measured in mCPU*hours. Each attempt has a set of resources associated
with it along with their usage in a resource-dependent set of
units. For example, a 1 core job has a usage value of 1000 (this value
is in mCPU). To compute the aggregate cost of a job, we sum up all of
the usages multiplied by the rates and then multiplied by the duration
the attempt has been running.

~~~~~~~~~~~~~
State Diagram
~~~~~~~~~~~~~

A job can be in one of the following states:

- Pending: 1+ parent jobs have not completed yet
- Ready: No pending parent jobs.
- Creating: Creating a VM for job private jobs.
- Running: Job is running on a worker VM.
- Success: Job completed successfully.
- Failed: Job failed.
- Cancelled: Job was cancelled either by the system, by the user, or
  because at least one of its parents failed.
- Error: Job failed due to an error in creating the container, an out
  of memory error, or a Batch bug (ex: user tries to use a nonexistent
  image).

The allowed state transitions are: Pending -> Ready Ready ->
{Creating, Running, Cancelled} Creating -> {Running, Cancelled}
Running -> {Success, Failed, Error, Cancelled}

A job's initial state depends on the states of its parent jobs. If it
has no parent jobs, its initial state is Ready.

A batch can be in one of the following states:

- completed: All jobs are in a completed state {Success, Failed,
  Error, Cancelled}
- running: At least one job is in a non-completed state {Pending,
  Ready, Running}

The batch and job states are critical for database performance and
must be indexed appropriately.


~~~~~~~~~~~~~~~
Batch Front End
~~~~~~~~~~~~~~~

The Batch Front End service (batch) is a stateless web service that
handles requests from the user. The front end exposes a REST API
interface for handling user requests such as creating a batch,
updating a batch, creating jobs in a batch, getting the status of a
batch, getting the status of a job, listing all the batches in a
billing project, and listing all of the jobs in a batch. There are
usually 3 copies of the batch front end service running at a given
time to be able to handle requests to create jobs in a batch with a
high degree of parallelism. This is necessary for batches with more
than a million jobs.


**************************************
Flow for Creating and Updating Batches
**************************************

The following flow is used to create a new batch or update an existing
batch with a set of job specifications:

1. The client library submits a POST request to create a new batch at
   ``/api/v1alpha/batches/create``. A new entry for the batch is
   inserted into the database along with any associated tables. For
   example, if a user provides attributes (labels) on the batch, that
   information is populated into the ``batch_attributes`` table. A new
   update is also created for that batch if the request contains a
   reservation with more than 1 job. The new batch id and possibly the
   new update id are returned to the client.

2. The client library submits job specifications in 6-way parallelism
   in groups of 100 jobs for the newly created batch update as a POST
   request to
   ``/api/v1alpha/batches/{batch_id}/updates/{update_id}/jobs/create``. The
   front end service creates new entries into the jobs table as well
   as associated tables such as the table that stores the attributes
   for the job.

3. The user commits the update by sending a POST request to
   ``/api/v1alpha/batches/{batch_id}/updates/{update_id}/commit``. After
   this, no additional jobs can be submitted for that update. The
   front end service executes a SQL stored procedure in the database
   that does some bookkeeping to transition these staged jobs into
   jobs the batch driver will be able to process and run.

The flow for updating an existing batch is almost identical to the one
above except step 1 submits a request to
``/api/v1alpha/batches/{batch_id}/updates/create``.

There are also two fast paths for creating and updating batches when
there are fewer than 100 jobs at
``/api/v1alpha/batches/{batch_id}/create-fast`` and
``/api/v1alpha/batches/{batch_id}/update-fast``.


************************
Listing Batches and Jobs
************************

To find all matching batches and jobs either via the UI or the Python
client library, a user provides a query filtering string as well as an
optional starting ID. The server then sends the next 50 records in
response and it is up to the client to send the next request with the
ID of the last record returned in the subsequent request.


~~~~~~~~~~~~
Batch Driver
~~~~~~~~~~~~

The Batch Driver is a Kubernetes service that creates a fleet of
worker VMs in response to user workloads and has mechanisms in place
for sharing resources fairly across users. It also has many background
processes to make sure orphaned resources such as disks and VMs are
cleaned up, billing prices for resources are up to date, and
cancelling batches with more than N failures if specified by the
user. The service can be located on a preemptible machine, but we use
a non-preemptible machine to minimize downtime, especially when the
cluster is large. There can only be one driver service in existence at
any one time. There is an Envoy side car container in the batch driver
pod to handle TLS handshakes to avoid excess CPU usage of the batch
driver.


********************
Instance Collections
********************

The batch driver maintains two different types of collections of
workers. There are **pools** that are multi-tenant and have a
dedicated worker type that is shared across all jobs. Pools can
support both preemptible and nonpreemptible VMs. Right now, there are
three types of machine types we support that correspond to low memory
(~1GB memory / core), standard (~4GB memory / core), and high memory
(~8GB memory / core) machines. These are correspondingly the
"highcpu", "standard", and "highmem" pools. Each pool has its own
scheduler and autoscaler. In addition, there's a single job private
instance manager that creates a worker VM per job and is used if the
worker requests a specific machine type. This is used commonly for
jobs that require more memory than a 16 core machine can provide.


**********
Fair Share
**********

In order to avoid having one user starve other users from getting
their jobs run, we use the following fair share algorithm. We start
with the user who has the fewest cores running. We then allocate as
many cores as possible that are live in the cluster until we reach the
number of cores the next user has currently running. We then divide up
the remaining cores equally amongst the two users until we reach the
number of cores the next user has running. We repeat until we have
either exhausted all free cores in the cluster or have satisfied all
user resource requests.


**********
Autoscaler
**********

At a high level, the autoscaler is in charge of figuring out how many
worker VMs are required to run all of the jobs that are ready to run
without wasting resources. The simplest autoscaler takes the number of
ready cores total across all users and divides up that amount by the
number of cores per worker to get the number of instances that are
required. It then spins up a maximum of 10 instances each time the
autoscaler runs to avoid cloud provider API rate limits. This approach
works well for large workloads that have long running jobs. It is not
very efficient if there's many short running jobs and the driver
cannot handle the load from a large cluster or the workload is large
but runs quickly.

Due to differences in resource prices across regions and extra fees
for inter-region data transfer, the autoscaler needs to be aware of
the regions a job can run in when scaling up the cluster in order to
avoid suboptimal cluster utilization or jobs not being able to be
scheduled due to a lack of resources.

The current autoscaler works by running every 15 seconds and executing
the following operations to determine the optimal number of instances
to spin up per region:

1. Get the fair share resource allocations for each user across all
   regions and figure out the share for each user out of 300 (this
   represents number of scheduling opportunities this user gets
   relative to other users).
2. For every user, sort the "Ready" jobs by regions the job can run in
   and take the first N jobs where N is equal to the user share
   computed in (1) multiplied by the autoscaler window, which is
   currently set to 2.5 minutes. The logic behind this number is it
   takes ~2.5 minutes to spin up a new instance so we only want to
   look at a small window at a time to avoid spinning up too many
   instances. It also makes this query feasible to set a limit on it
   and only look at the head of the job queue.
3. Take the union of the result sets for all of the users in (2) in
   fair share order. Do another pass over the result set where we
   assign each job a scheduling iteration which represents an estimate
   of which iteration of the scheduler that job will be scheduled in
   assuming the user's fair share.
4. Sort the result set by user fair share and the scheduling iteration
   and the regions that job can run in. Aggregate the free cores by
   regions in order in the result set. This becomes the number of free
   cores to use when computing the number of required instances and
   the possible regions the instance can be spun up in.


*********
Scheduler
*********

The scheduler finds the set of jobs to schedule by iterating through
each user in fair share order and then scheduling jobs with a "Ready"
state until the user's fair share allocation has been met. The result
set for each user is sorted by regions so that the scheduler matches
what the autoscaler is trying to provision for. The logic behind
scheduling is not very sophisticated so it is possible to have a job
get stuck if for example it requires 8 cores, but two instances are
live with 4 cores each.

Once the scheduler has assigned jobs to their respective instances, in
groups of 50, the scheduler performs the work necessary to grab any
secrets from Kubernetes, update the job state and add an attempt in
the database, and then communicate with the worker VM to start running
the job. There must be a timeout on this scheduling attempt that is
short (1 second) in order to ensure that a delay in one job doesn't
cause the scheduler to get stuck waiting for that one job to be
finished scheduling. We wait at the end of the scheduling iteration
for all jobs to finish scheduling. If we didn't wait, then we might
try and reschedule the same job multiple times before the original
operation to schedule the job in the database completes.


*****************
Job State Updates
*****************

There are three main job state update operations:
- SJ: Schedule Job
- MJS: Mark job started
- MJC: Mark job completed

SJ is a database operation (stored procedure) that happens on the
driver before the job has been scheduled on the worker VM. In the
stored procedure, we check whether an attempt already exists for this
job. If it does not, we create the attempt and subtract the free cores
from the instance in the database. If it does exist, then we don't do
anything. We check the batch has not been cancelled or completed and
the instance is active before setting the job state to Running.

MJS is a database operation that is initiated by the worker VM when
the job starts running. The worker sends the start time of the attempt
along with the resources it is using. If the attempt does not exist
yet, we create the attempt and subtract the free cores from the
instance in the database. We then update the job state to Running if
it is not already and not been cancelled or completed already. We then
update the start time of the attempt to that given by the
worker. Lastly, we execute a separate database query that inserts the
appropriate resources for that attempt into the database.

MJC is a database operation that is initiated by the worker VM when
the job completes. The worker sends the start and end time of the
attempt along with the resources it is using. If the attempt does not
exist yet, we create the attempt and subtract the free cores from the
instance in the database. We then update the job state to the
appropriate completed state if it is not already and not been
cancelled or completed already. We then update the start and end times
of the attempt to that given by the worker. We then find all of the
children of the completed job and subtract the number of pending
parents by one. If the child job(s) now have no pending parents, they
are set to have a state of Ready. We also check if this is the last
job in the batch to complete. If so, we change the batch state to
completed. Lastly, we execute a separate database query that inserts
the appropriate resources for that attempt into the database.

When we are looking at overall Batch performance, we look at the
metrics of SJ and MJC rates per second for heavy workloads (ex: 1000s
of no-op true jobs). We should be able to handle 80 jobs per second,
but the goal is ultimately 200 jobs per second.


*********
Canceller
*********

The canceller consists of three background loops that cancel any
ready, running, or creating jobs in batches that have been cancelled
or the job specifically has been cancelled (ie. a parent failed). Fair
share is computed by taking the number of cancellable jobs in each
category and dividing by the total number of cancellable jobs and
multiplying by 300 jobs to cancel in each iteration with a minimum of
20 jobs per user.


***************
Billing Updates
***************

To provide users with real time billing and effectively enforce
billing limits, we have the worker send us the job attempts it has
running as well as the current time approximately every 1 minute. We
then update the rollup_time for each job which is guaranteed to be
greater than or equal to the start time and less than or equal to the
end time. The rollup time is then used in billing calculations to
figure out the duration the job has been running thus far.


****************
Quota Exhaustion
****************

There is a mechanism in GCP by which we monitor our current quotas and
assign jobs that can be run in any region to a different region if
we've exceeded our quota.


**********************
Cloud Price Monitoring
**********************

We periodically call the corresponding cloud APIs to get up to date
billing information and update the current rates of each product used
accordingly.


~~~~~~~~
Database
~~~~~~~~

The batch database has a series of tables, triggers, and stored
procedures that are used to keep track of the state of billing
projects, batches, jobs, attempts, resources, and instances. We
previously discussed how the database operations SJ, MJS, and MJC
work.

There are three key principles in how the database is structured.
1. Any values that are dynamic should be separated from tables that
   have static state. For example, to represent that a batch is
   cancelled, we have a separate ``batches_cancelled`` table rather
   than adding a cancelled field to the ``batches`` table.
2. Any tables with state that is updated in parallel should be
   "tokenized" in order to reduce contention for updating rows. For
   example, when keeping track of the number of running jobs per user
   per instance collection, we'll need to update this count for every
   schedule job operation. If there is only one row representing this
   value, we'll end up serializing the schedule operations as each one
   waits for the exclusive write lock. To avoid this, we have up to
   200 rows per value we want to represent where each row has a unique
   "token". This way concurrent transactions can update rows
   simultaneously and the probability of serialized writes is
   equivalent to the birthday problem in mathematics. Note that there
   is a drawback to this approach in that queries to obtain the actual
   value are more complicated to write as they include an aggregation
   and the number of rows to store this in the database can make
   queries slower and data more expensive to store.

Key tables have triggers on them to support billing, job state counts,
and fast cancellation which will be described in more detail below.


~~~~~~~
Billing
~~~~~~~

Billing is implemented by keeping track of the resources each attempt
uses as well as the duration of time each attempt runs for. It is
trivial to write a query to compute the cost per attempt or even per
job. However, the query speed is linear in the number of total
attempts when computing the cost for a batch by scanning over the
entire table which is a non-starter for bigger batches. Therefore, we
keep an ``aggregated_batch_resources`` table where each update to the
attempt duration timestamps or inserting a new attempt resource
updates the corresponding batch in the table. This table is
"tokenized" as described above to prevent serialization of attempt
update events. Likewise, we have similar aggregation tables for
billing projects as well as billing project by date. There are two
triggers, one on each of the ``attempts`` and ``attempt_resources``
table that perform the usage updates and insert the appropriate rows
to these billing tables every time the attempt rollup time is changed
or a new resource is inserted for an attempt. Having these aggregation
tables means we can query the cost of a billing project, billing
project by date, batch, or job by scanning at most 200 records making
this query fast enough for a UI page.


~~~~~~~~~~~~~~~~~~
Job State Tracking
~~~~~~~~~~~~~~~~~~

To quickly be able to count the number of ready jobs, ready cores,
running jobs, running cores, creating jobs, and creating cores for
computing fair share, we maintain a very small "tokenized" table that
is parameterized by user and instance collection. The values in this
table are automatically updated as a job's state is changed through
the job state diagram. The updates to the ``user_inst_coll_resources``
table happen in a trigger on the ``jobs`` table.


~~~~~~~~~~~~
Cancellation
~~~~~~~~~~~~

A user can trigger a cancellation of a batch via the cancel button in
the UI or a REST request. The batch system also monitors how much has
been spent in a billing project. Once that limit has been exceeded,
all running batches in the billing project are cancelled.

Cancellation is the most complicated part of the Batch system. The
goal is to make cancellation as fast as possible such that we don't
waste resources spinning up worker VMs and running user jobs that are
ultimately going to get cancelled. Therefore, we need a way of quickly
notifying the autoscaler and scheduler to not spin up resources or
schedule jobs for batches that have been cancelled. We set a "flag" in
the database indicating the batch has been cancelled via the
``batches_cancelled`` table. This allows the query the scheduler
executes to find Ready jobs to run to not read rows for jobs in batches that
have been cancelled thereby avoiding scheduling them in the first
place. We also execute a similar query for the autoscaler. The only
place where we need to quickly know how many cores we have that are
ready and have not been cancelled is in the fair share calculation via
the ``user_inst_coll_resources`` table. To accomplish a fast update of
this table, we currently keep track of the number of **cancellable**
resources per batch in a tokenized table
``batch_inst_coll_cancellable_resources`` such as the number of
cancellable ready cores. When we execute a cancellation operation, we
quickly count the number of cancellable ready cores or other similar
values from the ``batch_inst_coll_cancellable_resources`` table and
subtract those numbers from the ``user_inst_coll_resources`` table to
have an O(1) update such that the fair share computation can quickly
adjust to the change in demand for resources.

The background canceller loops iterate through the cancelled jobs as
described above and are marked as Cancelled in the database and
handled accordingly one by one.

Once a batch has been cancelled, no subsequent updates are allowed to
the batch.


~~~~~~~~~~~~
Known Issues
~~~~~~~~~~~~

- The current database structure serializes MJC operations because the
  table ``batches_n_jobs_in_complete_states`` has one row per batch
  and each MJC operation tries to update the same row in this
  table. This proposal aims to fix this performance bottleneck while
  implementing job groups.
- ``commit_update`` is slow for large updates because we have to
  compute the job states by scanning the states of all of a job's
  parents.
- If a large batch has multiple distinct regions specified that are not
  interweaved, the autoscaler and scheduler can deadlock.


-----------------------------
Proposed Change Specification
-----------------------------

We will add the concept of a job group throughout the Hail Batch
system including the client libraries, the server, and the database. A
job group is defined to be an arbitrary set of jobs. A batch can
contain multiple job groups. A job can belong to multiple job
groups. A job group can be queried to list all of the jobs in the
group, get the aggregated status of all jobs in the group including
state and billing information as well as provide a mechanism for
cancelling all the jobs in the group. This interface provides the
minimum functionality necessary to be able to wait for completion of
and cancel a set of jobs which are the QoB use case requirements.

In addition, QoB users would like to be able to visualize and easily
find jobs in the UI grouped together in a hierarchical structure. To
accomplish this, we will also implement a light-weight organizational
layer (job tree) on top of the base job groups infrastructure. A job
tree is implemented as a set of job groups with special invariants. A
job group in a job tree can have parent and child job groups. A single
job can belong to multiple job groups with the caveat that all job
groups it is a member of in the tree must be in the same lineage. For
example, if job group 1 represents '/' and job group 2 represents
'/foo' and job group 3 represents '/bar', then a job cannot be a
member of both 2 and 3, but it can be a member of 1 and 2 or 1 and 3.

Any proposal that implements job groups needs to ensure all of these
operations are performant:

- Job Group Creation
- Getting the Status
- Cancellation
- Job Completion


~~~~~~~~~~~~~~~~~~
Job Group Creation
~~~~~~~~~~~~~~~~~~

A job group can be created with three different code paths. The first
is to create an empty job group upfront and then the client explicitly
specifies which groups the job belongs to during job creation.  The
second is to create an empty job group and then update the job group
with any existing jobs that should be a member of the group. The third
is to specify an arbitrary query filter string (example: "cohort =
scz1") that will be used to select any previously created jobs of
interest to add to the group.

The first and second code paths are simple, easy to reason about, and
efficient in terms of HTTP requests, server logic, and database
overhead. The extra database overhead is creating the new job group
record, inserting entries for assigning jobs to their respective job
group(s) and doing any aggregation updates which is
O(n_job_groups). The amount of HTTP requests is the same as the
current create/update flow as the job groups specs will be sent within
the same create/update requests. However, the client has to be more
sophisticated to assign which job groups a job should belong to and
vice versa when trying to implement a more complicated group
definition.

The third code path is desirable for its expressivity and
flexibility. The assignment of jobs to the job group happens
automatically on the server so the client can be very simple. It is
important to note that this is an arbitrary query and not a matching
"rule". It is not possible to create arbitrary "rules" upfront and add
matching new jobs to the groups automatically on the server. For
example, if we have 1000 job group rules, we'd have to test every new
job to see whether it belongs to any of the 1000 job groups by
executing an arbitrary matching query. This approach will never be
performant! Instead, we create the job group based on jobs that have
already been created at that point in time (filter on existing jobs
rather than as a matching rule that is executed on each new job that
is created). The implementation for this operation is to take a query
filter string / job group definition and then find all matching jobs
for that filter condition and assign them to the new job group. The
creation operation will return a job group ID that can be used for
subsequent polling and cancellation operations. A big concern with
this approach is its O(n_jobs) and will be slow for large batches and
it's likely the request will timeout before Batch can process the
request. This use case necessitates the need for longer running
idempotent async operations that the user can poll for completion of
(for example, creating disks in GCP). A poor man's implementation for
this operation is to have the client list jobs matching the query filter
and then the client explicitly creates the new job group specifying the
listed jobs.

For the QoB use case, we know upfront which group we want to assign
jobs to. Therefore, we will only implement the first interface for
creating a job group and save the later interfaces for future work.


~~~~~~~~~~~~~~~~~~
Getting the Status
~~~~~~~~~~~~~~~~~~

Getting the status of a job group is a single HTTP request that
executes an O(1) database query to do a small aggregation on the table
that keeps track of the number of jobs in each state and the billing
tables. The user must know the job group ID corresponding to the group
or the server needs to have a mechanism for translating a job group
"name" into an ID to query for.


~~~~~~~~~~~~
Cancellation
~~~~~~~~~~~~

Cancelling the job group is a single HTTP request and an O(1) database
insert operation. The job group ID is inserted into a table that
tracks which job groups have been cancelled.

The autoscaler and scheduler avoid trying to spin up resources for
jobs in job groups that have been cancelled, but the individual job
has not been cleaned up yet by ignoring any jobs that are in cancelled
batches or job groups (identical to the current behavior). For an
accurate fair share computation, the modified
``user_inst_coll_resources`` table keeps track of the number of ready
jobs, running jobs, etc. per user, per instance collection, and now
**per batch**. When a batch has been cancelled or a job group is
actively being cancelled, then those rows of the table pertaining to
the specific batch are skipped. This design is a rework of the current
cancellable resources tables. Because we don't need to track the
cancellable states of every job group, we can have job groups that
don't follow a tree like structure and still be able to cancel them
quickly and not have any performance regressions or incorrect fair
share computations that affect other user's resource allocations and
cluster efficiency.

The canceller looks for ready or running jobs in batches that have
been cancelled or in any job group that has been cancelled and then
cancels each job one at a time (identical to the current behavior).

Note that because we've added a new field to the
``user_inst_coll_resources`` table and parameterized it by batch id,
we'll need to add more garbage collection to remove those rows for
batches that have been completed (see below). In addition, this design
means that a cancellation of one job group has temporarily prevented
the entire batch from being seen by the autoscaler and scheduler. I
think for the most common use case, this constraint is okay. Most
batches are small and the QoB use case has all running jobs in the
same job group so there is no change in behavior from what we
currently do.


~~~~~~~~~~~~~~
Job Completion
~~~~~~~~~~~~~~

When a job is marked complete, all job groups the job is a member of
are checked to see if the number of jobs in the job group is equal to
the number completed. We are guaranteed that the job that sees the
number of jobs equals the number completed is the last job to complete
despite no locking being done. We then execute the callback for any
newly completed job groups. The amount of extra overhead in the mark
job complete SQL procedure compared to what we have now is
O(n_job_groups) the job is a member of, which will need some sort of
bound on it. This is because we have to update values in the billing
tables and the table that keeps track of the job states per job group
for each job group the job is a member of. When the batch is
completed, we will delete the extra rows from the
``user_inst_coll_resources`` to make sure that table is as fast as
possible (O(n_active_batches)).


~~~~~~~~~~~~~~~
Job Group Trees
~~~~~~~~~~~~~~~

A job group tree consists of a tree structure where a job group can
have children job groups where each child job group has a partition of
the jobs in the parent job group. Therefore, a job is a member of its
specific job group plus all of the parent job groups forming a tree
structure. Each job group is identified by a path that starts with "/"
which represents the root job group. The implementation consists of
two tables that are used to perform operations on the tree and map a
path identifier to the job group of interest:

- ``job_group_tree``
- ``job_group_tree_parents``

The implementation of cancellation for job groups in the job group
tree is to also cancel any children job groups by simply inserting the
child job group IDs into the ``job_groups_cancelled``
table. Aggregations for billing and job states propagating up the job
group tree are taken care of automatically as we've densely defined a
job group being a member of all job groups including the parents.

This additional layer can be implemented **later** on as it is not
crucial for QoB functionality. Instead, it will provide a nicer user
experience for both QoB and regular Hail Batch users.


--------
Examples
--------

Although QoB is the primary use case for this feature, we will use the
Python client interface implemented in ``aioclient.py`` in order to
demonstrate the utility of this feature. The examples below are for
the longer term vision. We do not have to implement all of this
functionality right away.

First, we create a batch with a job group "driver" with a single
driver job.

.. code::python

    bb = client.create_batch()
    driver_jg = bb.create_job_group(name='driver')
    driver = driver_jg.create_job(name='driver')
    b = bb.submit()

Next, we want to add an update to the batch with a stage of worker
jobs and say for the stage to cancel itself if there's at least one
failure.

.. code::python

    bb = client.update_batch(b.id)
    stage1 = bb.create_job_group(name='stage1', cancel_after_n_failures=1)
    for i in range(5):
        stage1.create_job(name=f'worker{i}')
    bb.submit()

We then want to wait for the stage to complete:

.. code::python

    stage1 = b.get_job_group('stage1')
    stage1.wait()

Once it completes, we want to check the cost of the stage which should
return quickly as the value is precomputed:

.. code::python

    status = stage1.status()
    cost = status['cost']

We then submit another stage ("stage2"), but this one is taking a long
time. We want to cancel it!

.. code::python

    stage2 = b.get_job_group('stage2')
    stage2.cancel()

The functionality above is sufficient for QoB. However, a nicer user
experience in the UI with a hierarchy tree is shown with the following
workflow:

.. code::python

    bb = client.create_batch()
    job_tree = bb.job_tree()
    session = job_tree.create_path('/session1')
    driver = session.create_job(name='driver')
    stage1 = job_tree.create_path('/session1/stage1')
    for i in range(5):
        stage1.create_job(name=f'worker{i}')
    b = bb.submit()

Oh no! The query is taking too long. Let's cancel the entire session,
but not the batch in case there's multiple simultaneous queries
happening:

.. code::python

   session = b.job_tree().get_path('/session1')
   session.cancel()
   session.wait()

A user wants to track how much it costs to run the PCA part of the
pipeline for multiple queries:

.. code::python

    bb = client.create_batch()
    job_tree = bb.job_tree()
    session = job_tree.create_path('/session1')
    driver = session.create_job(name='driver')

    stage1 = job_tree.create_path('/session1/stage1')
    for i in range(5):
        stage1.create_job(name=f'worker{I}', attributes={'pca': '1'})

    stage2 = job_tree.create_path('/session1/stage2')
    for i in range(10):
        stage2.create_job(name=f'worker{I}', attributes={'pca': '1'})

    stage3 = job_tree.create_path('/session1/stage3')
    for i in range(10):
        stage3.create_job(name=f'worker{I}', attributes={'vep': '1'})

    b = bb.submit()
    b.wait()

    pca = b.create_job_group('"pca"')
    status = pca.status()
    pca_cost = status['cost']


Finally, let's select the jobs in that group that cost more than $5
each:

.. code::python

    for j in pca.list_jobs('cost > 5'):
        print(j)


For completeness, if we want to manually add jobs to an arbitrary
preexisting job group, we can do the following. However, I don't think
this will be a common use case and we can implement it **later** on:

.. code::python

    bb = client.create_batch()
    for i in range(5):
        bb.create_job(name=f'worker{i}')
    b = bb.submit()

    random_jg = client.create_job_group(b.id, 'random')
    for j in b.list_jobs():
        if random.random() > 0.5:
            random_jg.add_job(j['job_id'])
    random_jg.update()


-----------------------
Effect and Interactions
-----------------------

My proposed changes address the issues raised in the motivation by
providing the following features:

1. Expose a way to quickly cancel a subset of jobs in a batch.
2. Expose a way to quickly cancel a subset of jobs in a batch after a
   specified number of failures in the group.
3. Expose a way to quickly find the cost and status of a subset of
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
and implementation on the Batch front end, how the driver handles
cancellation in the scheduler, autoscaler, and canceller, and all of
the Python and Scala client libraries. Writing tests for this feature
is time consuming as there are a lot of cases to consider because we
have a number of different code paths for creating and updating a
batch and we want to make sure billing and cancellation are done
properly in different scenarios. In addition, any UI changes are
extremely time consuming because they cannot be easily tested. The UI
changes will come **later** on.

Compared to previous features such as open batches, this proposal does
not require extensive, long running database migrations to transform
existing tables. The only complicated part is to parameterize the
existing ``user_inst_coll_resources`` table with the batch ID or
create a new table entirely by scanning the batches table with an
explicit lock. It would be easiest to create a separate table entirely.

Other challenges are to make sure the SQL aggregation triggers are
correctly implemented and the more complicated autoscaler, scheduler,
and canceller SQL queries are written correctly. However, this would
be the case for any plan that implemented job groups.

Backwards compatibility is not an issue in this plan.

The way this feature is designed in this proposal will make it easy to
add components in smaller chunks and the full vision does not need to
be realized in order to provide QoB with the necessary features it
needs. However, I am concerned that regardless of how small the actual
conceptual change is, the number of lines and distinct places this
change will touch in the code base will make the review process
challenging. There is tension between breaking up changes into smaller
chunks and having the entire vision fleshed out and working. We will
either have to accept larger PRs or accept that there could be bugs
that are found in later PRs that will need to be fixed that would have
been caught if we were merging a fully working feature all at once.

The maintenance costs for this feature are moderate. There is another
level of abstraction in our data model that must be accounted for when
adding new features in the future or planning a future rewrite of the
entire system. The UI will also need to be more complicated when we
expose a nested directory hierarchy to the users.

The proposed simplifications to how cancellation are done will
increase future developer productivity as this has always been a
tricky and confusing part of our system especially with how it relates
to always_run jobs.


------------
Alternatives
------------

The existing workaround QoB uses when waiting on a wave of worker jobs
to complete is to poll for when the number of completed jobs is equal
to the number of jobs in the batch minus 1 to compensate for the
driver job. This logic is not straightforward. There are no existing
workarounds for a driver job to be able to cancel a wave of worker
jobs without cancelling itself.

An alternate design to my proposed change has already been piloted and
influenced the current design. The alternate design is a batch is the
root job group in a job group tree and all operations on batches are
implemented in terms of job groups. Jobs can only belong to one job
group that is a node in the job group tree. The user assigns jobs to a
job group in a path-like structure. All tables that were parameterized
by batch ID are now parameterized by batch ID and job group ID. In the
long run, this design is not as flexible as allowing users to assign
jobs to multiple job groups or select jobs into a job group using an
arbitrary query. This plan is more costly to implement due to making
sure all of the the database transformations are correct. There are
also more complicated SQL queries with using the job tree data
structure to be able to correctly propagate billing and job state
information up the tree and cancellation down the tree. The benefits
of this approach are there are less edge cases and code paths to worry
about with regards to job group creation and there is simplicity in a
job group being analogous in implementation to how batches are
implemented in the current system and that a job can only belong to
one job group. Ultimately, I decided the proposed approach will be
easier and quicker to get implemented and merged into the code base
and will be more flexible for future use cases despite it being a
bigger change to how our current system works than the explicit job
group tree proposal -- consistent with feedback I got on the original
proposal.

We could also implement job groups where a job is assigned to a single
arbitrary job group with no notion of hierarchy. The implementation
would be very similar to what I have proposed although the assumption
that a job belongs to at most one job group does make the SQL queries
simpler. I can see this as an intermediate step to get to the full
vision, but I want to make sure that if we commit to this approach
that it does not impede the longer term vision I have outlined above.


--------------------
Unresolved Questions
--------------------

- How do we handle long-running operations for job group creation when
  the user can give an arbitrary query to execute?

- What are the safety mechanisms we need in place for this current
  proposal to ensure there is a limit on the number of job groups a
  job can be a member of?

- Is it safe to parameterize ``user_inst_coll_resources`` or an almost
  identical table by batch_id?  Will this cause problems in the
  future? How do we make ourselves confident that we can safely
  modify/clone this table and maintain acceptable performance when
  computing fair share and populating the UI?

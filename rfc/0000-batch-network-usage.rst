==================================
Billing for Network Usage in Batch
==================================

.. author:: Jackie Goldstein
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


**********
Motivation
**********

Hail Batch is a multitenant elastic batch job processing system that
executes user pipelines on a fleet of worker VMs. Jobs execute
arbitrary commands inside of a container on a worker VM. Users are
billed for their share of the cost for cpu, memory, storage costs, IP
fees, and an additional service fee. However, Hail Batch does not
currently bill for network usage from the external internet in the
user's container. These costs are billed to the operators of Batch and
not to the users leaving a financial vulnerability that users can
exploit. To address this vulnerability, we will add a new resource for
bytes sent and received by the user over the network within our
existing billing system.


****************************
How the Current System Works
****************************

The current billing system works by having six tables in the database
that are used in concert to determine how much a user has spent.

1. ``products``
2. ``latest_product_versions``
3. ``resources``
4. ``attempts``
5. ``attempt_resources``
6. ``aggregated_{batch,job,billing_project_user,billing_project_user_by_date}_resources_v2``


Resource Identity
=================

A resource is composed of a product and a version. A product is a
specific item (i.e. SKU) that we bill for. An example product is
"compute/n1-preemptible/us-central1". Each product has multiple
versions associated with it that track how much the product cost at a
given timepoint. The version is usually the timestamp in which the
product was first billed at that rate. The ``latest_product_versions``
table keeps track of the current version for each product in the
database. A resource is the combination of a product + version and has
a rate associated with it. The rate is in a relevant unit for the
product over time in milliseconds. For example, CPU is tracked in
mcpu * msec.  Certain products are tracked by the share of the VM to
compute the cost. These values are stored as integers where 100% is
stored as 1024 and the rate is computed to take shares out of 1024. We
use integers to avoid floating point imprecision as much as
possible. Resources are stored as unique integer IDs and are
referenced by their integer ID throughout the database.


Computing Resource Usage
========================

To compute how much of a resource an attempt has used, we store a row
for each resource used by each attempt that has an associated
quantity. The units of the quantity are specific to the resource
associated with it. For example, a compute resource has a quantity
that is in units of mCPU. Memory has a quantity that is in units of
MiB.  All quantities must be integer values. To get the usage of the
resource, we store the start time and end time in the ``attempts``
table for each attempt. Therefore, the total ``usage`` of a resource
can be computed by ``quantity * duration``. There are four aggregated
billing tables that then store the overall usage across billing
projects, batches, and jobs. Two database triggers
(``attempts_after_update`` and ``attempt_resources_after_insert``) are
responsible for making sure the aggregated resource tables are up to
date by taking the change in duration and multiplying it by the
quantity of resource.


Computing Cost
==============

The aggregated billing tables are tokenized such that multiple
attempts can add their usage to the aggregation table
simultaneously. Therefore, an example query to compute the overall
cost used is shown below for a job:

.. code::text

    SELECT batch_id, job_id, resource, COALESCE(CAST(COALESCE(SUM(`usage`), 0) AS SIGNED) * rate, 0) AS cost
    FROM aggregated_job_resources_v2
    LEFT JOIN resources ON aggregated_job_resources_v2.resource_id = resources.resource_id
    WHERE aggregated_job_resources_v2.batch_id = 2 AND aggregated_job_resources_v2.job_id = 1
    GROUP BY batch_id, job_id, resource;


Real-Time Billing
=================

Real time billing is implemented by having the worker VM send updates
every minute to the driver with the last known timestamp an attempt
has been running for.  The driver then updates the ``rollup_time`` in
the ``attempts`` table which then updates the aggregation tables
within the ``attempts_after_update`` trigger.


Network Bandwidth Tracking
==========================

We use iptable to mark packets with which network namespace they
originated from or are destined to. We track how many bytes have been
transferred by polling iptables periodically. We then display the
upload and download bandwidths to the user on the UI page.

The relevant iptable commands are:

.. code::text

    iptables -w {IPTABLES_WAIT_TIMEOUT_SECS} -t mangle -A PREROUTING --in-interface {self.veth_host} -j MARK --set-mark 10 && \
    iptables -w {IPTABLES_WAIT_TIMEOUT_SECS} -t mangle -A POSTROUTING --out-interface {self.veth_host} -j MARK --set-mark 11

    iptables -t mangle -L -v -n -x -w | grep "{self.veth_host}" | awk '{{ if ($6 == "{self.veth_host}" || $7 == "{self.veth_host}") print $2, $6, $7 }}'

    
*****************************
Proposed Change Specification
*****************************

We will make the following changes to the system to support billing
for network traffic:

1. There will be a new network bandwidth product added to the
   ``products`` table.
2. The rate in the ``resources`` table for the network bandwidth
   product will depend on the cloud provider and be in cost per byte
   transferred. We will add a new column to the ``resources`` table to
   distinguish resources where the rate is `by_time` or `by_unit`.
3. The quantity stored for the new product in the
   ``attempt_resources`` table will be equal to the current total
   number of bytes transferred for that attempt.
4. The ``attempts_after_update`` and
   ``attempt_resources_after_insert`` trigger will be modified such
   that resources that are `by_time` will use the change in duration
   when updating the usage while resources that are `by_unit` will
   instead have ``usage = quantity``.
5. The billing updates from the worker VM to the driver will contain
   the total number of bytes egressed (from VM to outside world) over
   the network for each attempt since the attempt began. The driver
   will then try and update the quantity for these attempts using
   ``INSERT ... ON DUPLICATE KEY UPDATE``.

Computing costs remains the same since `cost = usage * rate` and the
egress bytes are correctly accounted for in the `usage` and `rate`.

To start, we will only bill for outbound bytes in the main container
regardless of the destination of the packet. To protect ourselves from
extra charges for data transferred in the output container, we will
only allow output files to be copied to the same cloud as the worker
is currently running in.


***********************
Effect and Interactions
***********************

My proposed change addresses the problem of billing for network egress
usage in the main container in a coarse manner by ignoring the packet
destination.


*******************
Costs and Drawbacks
*******************

There are no performance costs to this plan on the Batch system. We
already track bytes sent out of the container's network and already
have the billing infrastructure in place.  The only problem with this
plan is we are overcharging in the following cases:

1. We are overcharging users who write files to Google Cloud Storage
   within the main container.

We are also limiting the ability of users to write output files from
one cloud to a different cloud.


************
Alternatives
************

There are no other alternative designs within our current framework.


********************
Unresolved Questions
********************

What is our strategy for tracking the destination of outbound packets
to bill only those destined for the external internet? What iptables
marks can we add and how do we distinguish packet destinations? This
plan is punting on how to get more fine-grained egress information for
now.


************
Endorsements
************

Not applicable.

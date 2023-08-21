==============================
Extra Structure Within a Batch
==============================

.. author:: Dan King
.. date-accepted::
.. ticket-url::
.. implemented::
.. header:: This proposal is `discussed at this pull request <https://github.com/hail-is/hail-rfcs/pull/8>`_.
.. sectnum::
.. contents::
.. role::



Motivation
----------

Hail team has been receiving reports of VCFs containing array fields whose elements can be
missing. In particular, there appear to be two new fields: ``AS_VQSLOD`` and ``AS_YNG`` which often
have the value `.,.` aka an array of size two with two missing elements.

Hail does not support arrays with missing elements because the VCF spec is `officially ambigious
<https://github.com/samtools/hts-specs/issues/737>`__ on whether `.` is a missing array or an array
with one missing element (i.e. does it mean `null` or `[null]`).

First reported on `Zulip
<https://hail.zulipchat.com/#narrow/stream/123010-Hail-Query-0.2E2-support/topic/checkpoint.20with.20missing.20fields>`__.

Proposed Change Specification
-----------------------------

Hail should parse all unambiguous cases and error only on ambiguity. VCF array fields are defined,
implicitly, in `VCF 4.3 Section 1.4.2 <https://samtools.github.io/hts-specs/VCFv4.3.pdf>`__:

    The Number entry is an Integer that describes the number of values that can be included with the
    INFO field. For example, if the INFO field contains a single number, then this value must be 1;
    if the INFO field describes a pair of numbers, then this value must be 2 and so on. There are
    also certain special characters used to define special cases:

    - A: The field has one value per alternate allele. The values must be in the same order as
      listed in the ALT column (described in section 1.6).

    - R: The field has one value for each possible allele, including the reference. The order of the
      values must be the reference allele first, then the alternate alleles as listed in the ALT
      column.

    - G: The field has one value for each possible genotype. The values must be in the same order as
      prescribed in section 1.6.2 (see Genotype Ordering).

    - . (dot): The number of possible values varies, is unknown or unbounded.

Let's analyze the cases:

+------------------------------------+-----------------------------------------+
|Number                              |Meaning of "."                           |
+====================================+=========================================+
|0 or >=2                            |N/A                                      |
+------------------------------------+-----------------------------------------+
|1                                   |N/A, because Number=1 is not an array.   |
+------------------------------------+-----------------------------------------+
|A, with 0 or >=2 alternate alleles  |N/A                                      |
+------------------------------------+-----------------------------------------+
|A with 1 alternate allele           |Ambiguous.                               |
+------------------------------------+-----------------------------------------+
|R with >=1 alternate alleles        |N/A                                      |
+------------------------------------+-----------------------------------------+
|R with 0 alternate alleles          |Ambiguous.                               |
+------------------------------------+-----------------------------------------+
|G with >=1 alternate alleles        |N/A                                      |
+------------------------------------+-----------------------------------------+
|G with 0 alternate alleles          |Ambiguous.                               |
+------------------------------------+-----------------------------------------+
|.                                   |Ambiguous.                               |
+------------------------------------+-----------------------------------------+

The R and G cases which are ambiguous can only occur at reference-only sites (because there are zero
alternate alleles). This seems unlikely to happen in the wild as GVCFs typically have at least the
``<NON_REF>`` alternate allele.

The A case might be fairly common. We'll need a way for the user to specify how to interpet that.

The "Number=." case is probably the most common ambiguous case. Again, the user will need to specify
how to interpret that.

We propose these modest modifcations to the ``import_vcf`` signature:

1. Mark ``array_elements_required`` as deprecated.

2. Add ``disambiguate_single_dot: Dict[str, Callable[[Expression], Expression]]``. For each row in
   the VCF, for each INFO field ``f`` with an ambiguous field value, ``import_vcf`` calls
   ``disambiguate_single_dot(f)`` and passes the row as the argument. All the ambiguous fields have
   the missing value. See the first example below.

And the following changes of semantics:

1. For each unambiguous case, parse a comma-separated list of values as an array of possibly missing
   values. This currently raises an error. For example, ".,." and "3,." are now parsed as
   ``hl.array(hl.missing(...), hl.missing(...))`` and ``hl.array(3, hl.missing(...))``. They
   previously raised an error.

2. For each unambigious array case, parse a "." as a missing value of type array.

3. For the three statically known-length ambiguous cases (all except the "Number=." case), for each
   field f, if the field's string is ".", evaluate ``disambiguate_single_dot[f](the_row)`` and use
   the value as the value of field f.

4. For the "Number=." case, if there is at least one comma, parse the field's string as an array of
   possibly missing values. If the string is not ".", parse aas a (size one) array of possibly
   missing values. If the string is "." follow the instructions in (3).

Examples
--------

Assume that ``FOO``, ``BAR``, ``BAZ``, and ``QUX`` are all have ``Type=Integer`` and
``Number=.``. Consider parsing the following VCF line:

::

    chr1   1 .   A   T  .   . FOO=3;BAR=.;BAZ=.,.;QUX=.    GT:AD:GQ:RGQ

The ``BAR`` and ``QUX`` fields are ambiguous. For both ``BAR`` and ``QUX``, we evaluate their
``disambiguate_single_dot`` expression on the following row:

::

    hl.Struct(
        FOO=3,
	BAR=hl.missing(hl.tint32),
	BAZ=[hl.missing(hl.tint32), hl.missing(hl.tint32)],
	QUX=hl.missing(hl.tint32),
    )

The resulting value for each field replaces its currently missing value.

After this change, this VCF (reported by James Nemesh in Zulip):

::

    ##fileformat=VCFv4.2
    ##FILTER=<ID=PASS,Description="All filters passed">
    ##FILTER=<ID=ExcessHet,Description="Site has excess het value larger than the threshold">
    ##FILTER=<ID=LowQual,Description="Low quality">
    ##FILTER=<ID=NO_HQ_GENOTYPES,Description="Site has no high quality variant genotypes">
    ##FILTER=<ID=low_VQSLOD_INDEL,Description="Site failed INDEL model sensitivity cutoff (99.0), corresponding with VQSLOD cutoff of -1.3625">
    ##FILTER=<ID=low_VQSLOD_SNP,Description="Site failed SNP model sensitivity cutoff (99.7), corresponding with VQSLOD cutoff of -2.2757">
    ##FORMAT=<ID=AD,Number=R,Type=Integer,Description="Allelic depths for the ref and alt alleles in the order listed">
    ##FORMAT=<ID=FT,Number=1,Type=String,Description="Genotype Filter Field">
    ##FORMAT=<ID=GQ,Number=1,Type=Integer,Description="Genotype Quality">
    ##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
    ##FORMAT=<ID=RGQ,Number=1,Type=Integer,Description="Unconditional reference genotype confidence, encoded as a phred quality -10*log10 p(genotype call is wrong)">
    ##INFO=<ID=AC,Number=A,Type=Integer,Description="Allele count in genotypes, for each ALT allele, in the same order as listed">
    ##INFO=<ID=AF,Number=A,Type=Float,Description="Allele Frequency, for each ALT allele, in the same order as listed">
    ##INFO=<ID=AN,Number=1,Type=Integer,Description="Total number of alleles in called genotypes">
    ##INFO=<ID=AS_QUALapprox,Number=1,Type=String,Description="Allele-specific QUAL approximations">
    ##INFO=<ID=AS_VQSLOD,Number=A,Type=String,Description="For each alt allele, the log odds of being a true variant versus being false under the trained gaussian mixture model">
    ##INFO=<ID=AS_YNG,Number=A,Type=String,Description="For each alt allele, the yay/nay/grey status (yay are known good alleles, nay are known false positives, grey are unknown)">
    ##INFO=<ID=QUALapprox,Number=1,Type=Integer,Description="Sum of PL[0] values; used to approximate the QUAL score">
    #CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	1	2	3	4	5	6	7	8	9	10	11	1
    chr16   8538153 .   A   AAAAAC,AAAAAAC  .   NO_HQ_GENOTYPES AC=2,3;AF=0.111,0.167;AN=18;AS_QUALapprox=0|31|49;AS_VQSLOD=.,.;AS_YNG=.,.;QUALapprox=17    GT:AD:GQ:RGQ    ./. ./. ./. 0/2:14,0,2:6:8  0/2:10,0,1:17:17    ./. 0/1:18,1,0:10:21    ./. ./. 0/0:.:40    0/0:.:20    0/1:16,1,0:2:10 ./. ./. 0/0:.:20    0/0:.:40    0/2:17,0,1:24:24    ./.

is imported without error and contains exactly one row, this row (I've elided the entries):

::
    hl.Struct(
        locus=hl.Locus('chr16', 8538153),
        alleles=["A", "AAAAAC", "AAAAAAC"],
	NO_HQ_GENOTYPES=True,
	AC=[2, 3]
	AF=[0.111, 0.167]
	AN=18
	AS_QUALapprox=[0, 31, 49]
	AS_VQSLOD=[hl.missing(hl.tstr), hl.missing(hl.tstr)]
	AS_YNG=[hl.missing(hl.tstr), hl.missing(hl.tstr)]
	QUALapprox=17
        entries=[...]
    )

Effect and Interactions
-----------------------

This change makes `import_vcf` succeed in several cases that it would error. The particular subset
of VCFs reported by our users would not error.

Users who previously used ``array_elements_missing=False`` now experience deprecation warnings which
encourage them to switch to the new disambiguation system.

VCFs which previously did not error will parse in exactly the same way.

Users with "Number=." fields still experience errors unless they provide a disambiguation expression.

Costs and Drawbacks
-------------------

1. Adds a small amount of new Python code to handle the ambiguous cases. We rely on the already
   implemented support for ``array_elements_missing=False`` to correctly parse comma-separated lists.

2. Reduces complexity for users with VCFs that have unambiguous A-number fields. These VCFs now
   parse without error to a table of well-defined, sensible values.

3. We do not address the deeper issue of ambiguity of "." in VCF.

Alternatives
------------

We have separately `proposed
<https://github.com/samtools/hts-specs/issues/737#issuecomment-1662490048>` a modest extension to
the VCF spec which resolves the ambiguity with a bit of backwards incompatibility. In our
experience, changing the VCF spec is a long and complex process. After spec modification, our
upstream data generators would need to start using the new spec. We estimate this process would take
at least two years and possibly much longer. In the meantime, our users would repeatedly encounter
the same annoying error on every new VCF they receive from upstreams generating array fields with
missing elements.

Unresolved Questions
--------------------

None.

Implementation Plan
-------------------

Dan King will implement.

Endorsements
-------------

---
title: Example data and code
parent: svCapture
has_children: false
nav_order: 30
published: true
---

## {{page.title}}

We provide a complete working example of a job configuration file and 
associated data set for testing your svCapture installation. 
Instructions below lead you through all steps to get running.

### Create a working directory for the svCapture demo

Working from whatever folder you'd like:

```sh
mkdir svCapture-demo
cd svCapture-demo
```

The entire demo will take place in this directory so you can easily delete it later.

### Install everything first

Follow the [installation instructions](https://wilsontelab.github.io/svx-mdi-tools/docs/installation/code.html)
to create:
- a multi-suite MDI installation
- an alias to the MDI utility called _mdi_

If you choose a different type of installation, please adjust all commands as needed.

Then, [build the required conda runtime environments](https://wilsontelab.github.io/svx-mdi-tools/docs/installation/runtime.html)
and [download the hg38 reference genome](https://wilsontelab.github.io/svx-mdi-tools/docs/installation/genome.html)
into the demo directory.  If you install the genome into a different directory, you will need 
to edit the job file, below.

### Obtain the demo data, scripts, and support files

Example data, which are too big for the svx-mdi-tools git repository,
can be downloaded from Mendeley Data using the following command:

```sh
wget PENDING
```

Reads in the FASTQ files were obtained from cell line HCT116 from
a tagmentation svCapture library in which the central
400 kb of the WWOX gene on human chr16 was subjected to probe capture.
Reads were filtered to include only chr16 and downsampled
to 1M read pairs to keep the demo small and fast.

The total file size is ~XXX MB.

### Examine the svCapture job configuration file

```sh
cat svCapture-demo.yml
```

Pipeline options are specified in an extended YAML format 
that support variables and option declarations
common to multiple pipeline actions. See the file comments for details.
 
The demo job file is configured to work entirely
from your working demo directory - you would change paths when doing real work,
or if you installed the hg38 genome into a different location, above.
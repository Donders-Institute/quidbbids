Troubleshooting
===============

This guide is intended to help you troubleshoot common issues that may arise when using QuIDBBIDS. If you encounter an error, please check the following sections to see if your problem is addressed. If not, you can seek further assistance as described in the "More help" section below.

Installation
------------
When encountering execution errors it is helpful to know whether your dependencies are installed with the right versions. If you have installed QuIDBBIDS using git, then best way to verify the installation is to run ``WIP``. Some commonly reported issues are:

WIP
^^^
WIP

Workflow
--------
The first step in workflow troubleshooting is to look at the warnings and messages printed out in the
terminal (they are also saved to disk in the ``QuIDBBIDS/logs`` output folder). Make sure you are OK with
the warnings (they are meaningful and not to be ignored) and do not continue with a next step until all
errors are resolved. Below you can find answers to some commonly reported issues.

WIP
^^^
WIP

Irregular data acquisition
--------------------------

Some acquisitions need to be excluded
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Use the ``include`` and ``exclude`` bidsfilters to select which raw BIDS data enter the workflow. They are
set in the configuration under ``config.General.BIDS.include`` and ``config.General.BIDS.exclude``: edit
them as JSON in the Inclusion editor (``quidb.edit_inclusion()``, the :guilabel:`Inclusion` button in the
Workflow Control Panel) or in the config file ``[bidsdir]/derivatives/QuIDBBIDS/code/config.json``
(``General.BIDS.include.value`` / ``General.BIDS.exclude.value``). Example::

   sub-01/fmap/
   ├── sub-01_acq-famp_run-1_TB1map.nii.gz    % complete acquisition
   ├── sub-01_acq-famp_run-2_TB1map.nii.gz    % interrupted re-scan (aborted)

Exclude the interrupted run by extending the ``include`` and/or ``exclude`` filters, for instance with:

.. code-block:: json

   "include": {"run": ["1", ""]}
   "exclude": {"modality": "fmap", "run": "2", "suffix": "TB1map"}
   "exclude": {"modality": "fmap", "run": "^(2|3)$"}

More help
---------
If this guide does not help to solve your problem, then you can `search on github <https://github.com/Donders-Institute/QuIDBBIDS/issues?q=>`__
for open and/or closed issues to see if anyone else has encountered similar problems before. If not, feel
free to help yourself and others by opening a new github issue or post your question on `NeuroStars <https://neurostars.org/tag/quidbbids>`__
(tag: #quidbbids).

Please provide as much information as possible, including the version of QuIDBBIDS you are using and the exact error
message you are getting. If possible, include a minimal example of your data and code that reproduces the error.

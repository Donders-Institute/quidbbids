Data structure
==============

QuIDBBIDS organises data according to the BIDS (Brain Imaging Data Structure) standard 
`specification <https://bids.neuroimaging.io/>`__. BIDS prescribes a derivatives subfolder in 
which processed data is stored. QuIDBBIDS uses this folder to store its two output types:

1. ``./derivatives/QuIDBBIDS_work``. In here all temporary files and workitems are stored that are
   produced during execution of the workflow. All items are re-used or re-produced if the workflow is
   re-executed. This folder can be deleted after processing is finished.
2. ``./derivatives/QuIDBBIDS``. In here all final output files (products) are stored, organized according 
   to BIDS derivatives specification. This folder should be kept after processing is finished.

Next to the output files, in the ``QuIDBBIDS`` folder you can find two subfolders with additional data:

1. ``code/config.json``. A copy of the default configuration file with the actual settings that 
   were used to produce the data. This is important for reproducibility of results.
2. ``logs``. A folder that contains worker specific log files, including error messages if any 
   issues were encountered.

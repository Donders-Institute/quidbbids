Data structure
==============

QuIDBBIDS organises data according to the BIDS (Brain Imaging Data Structure) standard 
`specification <https://bids.neuroimaging.io/>`__. BIDS prescribes a derivatives subfolder in 
which processed data is stored. QuIDBBIDS uses this folder to store its two output types:

1. ``./derivatives/QuIDBBIDS_work``. In here all temporary files and workitems are stored that are
   produced during execution of the workflow. All items are reused or reproduced if the workflow is
   re-executed. This folder can be deleted after processing is finished.
2. ``./derivatives/QuIDBBIDS``. In here all final output files (deliverables) are stored, organized according 
   to BIDS derivatives specification. This folder should be kept after processing is finished.

Next to the output files, in the ``QuIDBBIDS`` folder you can find two subfolders with meta data:

1. ``code``. A (copy of the default) configuration and workflow files with the actual settings that 
   were used to produce the data. This is important for reproducibility of results.
2. ``logs``. A folder that contains worker specific log files, including error messages if any 
   issues were encountered.

The overall folder structure looks like this (for a single subject)::

    my_BIDS_dataset/                         # raw BIDS input data
    ├── dataset_description.json
    ├── participants.tsv
    ├── sub-100/
    │   └── anat/
    │       └── ...
    └── derivatives/
        ├── QuIDBBIDS_work/                  # intermediate workitems (can be deleted)
        │   ├── CHANGES
        │   ├── dataset_description.json
        │   ├── README.md
        │   └── sub-100/
        │       ├── anat/                    # json sidecars are omitted for clarity
        │       │   ├── sub-100_run-1_desc-minimal_label-brain_mask.nii.gz
        │       │   ├── sub-100_run-1_part-mag_desc-ME4D_MEGRE.nii.gz
        │       │   ├── sub-100_run-1_part-phase_desc-ME4D_MEGRE.nii.gz
        │       │   ├── sub-100_run-1_space-MP2RAGE_desc-UNIT1corrected_M0map.nii.gz
        │       │   ├── sub-100_run-1_space-MP2RAGE_desc-UNIT1corrected_R1map.nii.gz
        │       │   ├── sub-100_run-1_space-MP2RAGE_desc-UNIT1corrected_T1w.nii.gz
        │       │   └── ...
        │       ├── fmap/
        │       │   ├── sub-100_acq-famp_run-1_desc-corrected_space-raw_TB1map.nii.gz
        │       │   ├── sub-100_acq-anat_run-1_desc-corrected_space-raw_TB1map.nii.gz
        │       │   └── ...
        │       ├── B1prepWorker.done        # status files
        │       ├── MEGREprepWorker.done
        │       └── ...
        └── QuIDBBIDS/                       # final deliverables (keep for analysis)
            ├── CHANGES
            ├── code/                        # config & workflow files used
            │   ├── config.json              # actual config file used
            │   ├── workflow.mat             # workflow settings used
            │   ├── workflow.png             # workflow diagram
            │   └── workflow_mask.png        # workflow diagram with masked-out items
            ├── dataset_description.json
            ├── logs/                        # worker log files
            │   ├── diary_sub-100.txt        # full (HPC) diary log for subject 100
            │   ├── diary_sub-101.txt
            │   ├── diary_workflow.txt       # full diary log for the whole workflow
            │   ├── B1prepWorker/
            │   │   ├── sub-100.log          # worker-specific logs for subject 100
            │   │   └── sub-101.log
            │   ├── MEGREprepWorker/
            │   │   ├── sub-100.log
            │   │   └── sub-101.log
            │   └── ...
            ├── README.md
            └── sub-100/
                └── anat/                    # (tagged) deliverables
                    ├── sub-100_run-1_tag-manualtest_Chimap.nii.gz
                    ├── sub-100_run-1_tag-manualtest_R2starmap.nii.gz
                    ├── sub-100_run-1_space-MP2RAGE_desc-UNIT1corrected_tag-manualtest_T1w.nii.gz
                    └── ...

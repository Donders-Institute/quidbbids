QuIDBBIDS 101 — First R2* and Chi Maps
=======================================
From raw multi-echo GRE data to quantitative maps in a few lines of code

Objective
---------

- Learning the basic workflow: **initialise -> configure -> run**.
- Producing your first R2* and Chi maps from raw multi-echo GRE data.

Tagret audience
---------------  
- who is new to QuIDBBIDS
- wants to compute R2* and Chi maps from raw multi-echo GRE data

Estimated time
------------------  
About ---minutes

Prerequisites
------------------
Install QuIDBBIDS(and its dependencies), in your MATLAB environment,
you can find the installation instruction on the :doc:`/installation` page 

.. note::
 
   Make sure that the QuIDBBIDS folder (without subfolders) is on your MATLAB path.
   You can verify this by typing ``qb.QuIDBBIDS`` in the MATLAB command window — it
   should not return an error.

You will also need a BIDS formatted dataset that contains multi-echo GRE (MEGRE) data magnitude and phase images.
If you don't have one, you can use the test dataset provided ....

.. tip::
 
   You can use `BIDScoin <https://bidscoin.readthedocs.io>`__ to convert your raw DICOM
   data to BIDS format.


Introduction
------------
In this tutorial, we will go through a simple workflow : computing **R2* map** and a **Chi map** from raw MEGRE data. 
We will use the ``R2starWorker`` and ``QSMWorker`` for this purpose, which are part of the QuIDBBIDS toolbox.
Under the hood, QuIDBBIDS uses `SEPIA <https://sepia-documentation.readthedocs.io>`__ for the QSM processing pipeline.

The key idea is that you tell QuIDBBIDS *what you want* (the output maps) and it figures out 
*how to make them* by automatically assembling the right processing pipeline including brain masking, echo merging, phase unwrapping,
background field removal etc.

Exercises
---------

.. contents:: 
   :local:
   :depth: 1

Exercise 1 — Explore your data
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

QuIDBBIDS expects your data to follow the `BIDS standard <https://bids-specification.readthedocs.io>`__.
For this tutorial, the input dataset should look something like this:

.. code-block:: text
 
   my_bids_dataset/
   ├── dataset_description.json
   ├── README
   ├── sub-100/
   │   └── anat/
   │       ├── sub-100_run-1_echo-1_part-mag_MEGRE.nii.gz
   │       ├── sub-100_run-1_echo-1_part-mag_MEGRE.json
   │       ├── sub-100_run-1_echo-1_part-phase_MEGRE.nii.gz
   │       ├── sub-100_run-1_echo-1_part-phase_MEGRE.json
   │       ├── sub-100_run-1_echo-2_part-mag_MEGRE.nii.gz
   │       ├── ...
   │       └── sub-100_run-1_echo-N_part-phase_MEGRE.json
   └── sub-101/
       └── ...

Each subject has magnitude and phase images for multiple echoes, stored as separate NIfTI files
with accompanying JSON sidecars that contain acquisition parameters such as echo times.

Exercise 2 — Run QuIDBBIDS
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Now that we have our data ready, we can run QuIDBBIDS to compute the R2* and Chi maps.
Open MATLAB and follow these steps:

1. **Initialise QuIDBBIDS** — Point it at your BIDS dataset: 

.. code-block:: matlab
 
      quidb = qb.QuIDBBIDS('/path/to/my_bids_dataset');
 
   This scans the dataset and discovers all subjects, sessions, and available data types.

2. **Tell it what you want** — Request R2* and Chi maps as output products:
 
   .. code-block:: matlab
 
      quidb.products = ["Chimap", "R2starmap"];
 
   But how do you know what products are available, and which workers can make them?
   Click below to find out.
 
   .. dropdown:: Exploring available products and workers
      :color: info
 
      **See all available products**
 
      To see everything QuIDBBIDS can produce, type:
 
      .. code-block:: matlab
 
         >> quidb.workitems
            Chimap               : Magnetic susceptibility map derived from QSM reconstruction
            FMW_exrate           : Exchange rate map in Free <-> Myelin Water analysis
            [...]                : [...]
 
      **Inspect a worker's resume**
 
      Each worker has a "resume" that describes what it can make and what it needs as input.
      For example, to see what the ``QSMWorker`` does:
 
      .. code-block:: matlab
 
         >> quidb.resumes.QSMWorker
                 handle: @qb.workers.QSMWorker
                   name: "QSMWorker"
            description: "I am your SEPIA expert that can make shiny QSM and R2-star images for you"
                  makes: ["R2starmap"  "T2starmap"  "S0map"  "Chimap"  ...]
                  needs: ["ME4Dmag"  "ME4Dphase"  "brainmask"]
                usesGPU: 0
              preferred: 0
 
      The ``makes`` field lists all the products this worker can produce, and ``needs`` lists the
      inputs it requires (which other workers will provide automatically).
 
      **List all workers**
 
      To see all available workers, type:
 
      .. code-block:: matlab
 
         >> quidb.resumes
 
   .. dropdown:: Exploring and editing configuration settings
      :color: info
 
      **From the command line**
 
      All processing settings are accessible via ``quidb.config``, organised per worker:
 
      .. code-block:: matlab
 
         >> quidb.config
                  General: [1×1 struct]
             B1prepWorker: [1×1 struct]
            MP2RAGEWorker: [1×1 struct]
              R1R2sWorker: [1×1 struct]
                MCRWorker: [1×1 struct]
                QSMWorker: [1×1 struct]
 
      Drill down into any worker to see its settings. Each setting has a ``value`` and a
      ``description``:
 
      .. code-block:: matlab
 
         >> quidb.config.MEGREprepWorker.denoising.method
               value: ""
         description: 'Denoising method to apply to the raw data. Options: "MPPCA", "tMPPCA", ""'
 
         >> quidb.config.MEGREprepWorker.denoising.method.value = "MPPCA";
 
      **Using the graphical config editor**
 
      If you prefer a GUI, you can open the configuration editor:
 
      .. code-block:: matlab
 
         >> quidb.editconfig()
 
      .. figure:: /_static/configeditor.png
 
         The QuIDBBIDS configuration editor. Left panel: settings organised by worker.
         Right panel: description and editable value for the selected parameter.

   

    

3. **Select the worker** — Since multiple workers can produce these maps, tell QuIDBBIDS
   which one to use. For standard MEGRE data, the ``QSMWorker`` (which uses SEPIA) is the
   right choice:
 
   .. code-block:: matlab
 
      quidb.resumes.QSMWorker.preferred = true;

4. **(Optional) Enable denoising** — For example, enable MPPCA denoising on the input images:
 
   .. code-block:: matlab
    quidb.config.MEGREprepWorker.denoising.method.value = "MPPCA";

    You can browse all available settings with ``quidb.config``.
    
5. **Run!** — Create the manager and start the workflow:
 
   .. code-block:: matlab
 
      mgr = quidb.manager();
      mgr.start_workflow();

   QuIDBBIDS will now process each subject in your dataset. It automatically handles all
   intermediate steps: creating brain masks, merging echoes, running SEPIA for phase
   unwrapping, background field removal, R2* fitting, and dipole inversion for QSM.  

**Putting it all together** — here is the complete script:
.. code-block:: matlab
 
   %% QuIDBBIDS 101 — Compute R2* and Chi maps from mGRE data
 
   quidb = qb.QuIDBBIDS('/path/to/my_bids_dataset');
 
   quidb.products = ["Chimap", "R2starmap"];

   quidb.resumes.QSMWorker.preferred = true;
 
   mgr = quidb.manager();

   mgr.start_workflow();

.. tip::
 
   If you have access to a high-performance computing (HPC) cluster, you can enable parallel
   processing across subjects by adding::
 
      quidb.config.General.useHPC.value = true;



Exercise 3 — Inspect the results
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
 
1. **Find the output** — After the workflow completes, your results are stored in the BIDS
   derivatives directory:

   .. code-block:: text
 
      my_bids_dataset/
      └── derivatives/
          └── QuIDBBIDS/
              └── sub-100/
                  └── anat/
                      ├── sub-100_..._Chimap.nii.gz
                      └── sub-100_..._R2starmap.nii.gz

   The intermediate working files (brain masks, merged echoes, etc.) are stored separately
   under ``derivatives/QuIDBBIDS_work/``.

2. **View the maps** — Open the results in your favourite NIfTI viewer. For example, using
   FSLeyes from the terminal:


3. **(Optional) Generate a QC report** — If you have
   `BIDScoin <https://bidscoin.readthedocs.io>`__ installed, you can generate slice-overview
   reports to quickly check all subjects:
 
   .. code-block:: bash
 
      cd /path/to/my_bids_dataset
      slicereport derivatives/QuIDBBIDS/ anat/*R2starmap* -r report_R2starmap --options i 5 50
      slicereport derivatives/QuIDBBIDS/ anat/*Chimap*    -r report_Chimap    --options i -0.15 0.3

What's next?
------------
 
Congratulations — you have computed your first quantitative maps with QuIDBBIDS!
From here you can:
 
- **Add more products** — Request ``"R1map"``, ``"MWFmap"``, or ``"MP2RAGE_T1w"`` depending
  on your data
- **Customise processing** — Explore all settings with ``quidb.config`` or the
  :doc:`graphical config editor </GUI>`
- **Scale up** — Enable HPC processing to run all subjects in parallel
- **Read the docs** — Check out the :doc:`/CLI` and :doc:`/architecture` pages to understand how it works under the hood and how to customise it for your needs.
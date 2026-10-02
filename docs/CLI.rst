Command Interface
=================

The QuIDBBIDS workflow can be executed directly from the MATLAB command line, scripts or functions. The paragraphs
below describe a minimal example of how to initialize and run a QuIDBBIDS workflow for all subjects in a BIDS dataset, 
requesting R1, R2*, and MWF maps as output:

Initializing QuIDBBIDS
----------------------

To initialize the QuIDBBIDS coordinator, create a ``QuIDBBIDS`` object by providing the path to your BIDS dataset.

.. code-block:: matlab

   >> quidb = qb.QuIDBBIDS('/path/to/bids/dataset');       % Initialize QuIDBBIDS coordinator
   >> quidb.catalog()                                      % See e.g. what QuIDBBIDS can make, given the input data
      Chimap       : Magnetic susceptibility map derived from phase or quantitative susceptibility mapping (QSM) reconstruction
      M0map        : Proton density (M0) map derived from GRE or similar acquisitions
      ME4Dmag      : 4D magnitude image stack from a multi-echo GRE acquisition
      ME4Dphase    : 4D phase image stack from a multi-echo GRE acquisition
      MP2RAGE_T1w  : T1-weighted MP2RAGE image generated from the MP2RAGE sequence
      [..]         : [..]

   >> quidb.resumes.R2R1R2sWorker                          % NB: Only ever edit the `preferred` field
           handle: @qb.workers.R1R2sWorker
             name: "R1R2sWorker"
      description: [24×1 string]
            makes: ["R2starmap" "M0map" "R1map"]
            needs: ["ME4Dmag" "TB1map_GRE" "brainmask"]
          usesGPU: 1
        preferred: 0

   >> quidb.deliverables = ["R1map", "R2starmap", "MWFmap"];   % Specify the output items
   >> quidb.resumes.R2R1R2sWorker.preferred = true;            % Specify the worker that makes the R1/R2starmap

Edit settings and options
-------------------------

All configuration settings and options for processing the data of your dataset can be set per worker by 
modifying the ``config`` properties of your ``QuIDBBIDS`` object. For instance, to inspect the ``NumberShots`` 
parameter of the MP2RAGEWorker and modify it to ``192``, and use your HPC you can do:

.. code-block:: matlab

   >> quidb.config
            General: [1×1 struct]
       B1prepWorker: [1×1 struct]
      MP2RAGEWorker: [1×1 struct]
        R1R2sWorker: [1×1 struct]
          MCRWorker: [1×1 struct]
          QSMWorker: [1×1 struct]

   >> quidb.config.MP2RAGEWorker.NumberShots
          value: ''
    description: 'Number of shots (NZslices) in inversion segment; not usually in JSON. See: 
    https://bids-specification.readthedocs.io/en/stable/appendices/qmri.html#numbershots-metadata-field'

   >> quidb.config.MP2RAGEWorker.NumberShots.value = 192;
   >> quidb.config.General.useHPC.value = true;

Run the workflow
----------------

Finally, to run the workflow, initialize the manager from your ``QuIDBBIDS`` object and start the workflow:

.. code-block:: matlab

   >> mgr       = quidb.manager();                    % Initialize the manager to get work done
   >> mgr.force = ["B1prepWorker", "MP2RAGEWorker"];  % Reuse existing workitems except for these workers and their dependencies
   >> mgr.start_workflow()                            % Start the workflow

A more advanced example of a CLI workflow can be found in this `manual test script <https://github.com/Donders-Institute/quidbbids/blob/main/tests/mantest_dccn.m>`__.

Getting help
------------

For getting more help on the various classes, methods and properties, you can use MATLAB's built-in documentation
browser:

.. code-block:: matlab

   >> doc qb.QuIDBBIDS

Additionally, you can get help about the workers and workitems using the ``qb.workers.help`` function:

.. code-block:: matlab

   >> qb.workers.help(["R1map", "localfmask"])
   R1map      : Longitudinal relaxation rate (R1) map (R1 = 1/T1)
   localfmask : Local field mask for susceptibility mapping

   >> qb.workers.help('QSMWorker')
   QSMWorker : Quantitative Susceptibility Mapping (QSM) and R2* relaxometry worker using the SEPIA toolbox.

   QSMWorker performs QSM reconstruction and R2* mapping from multi-echo GRE magnitude and phase data.
   QSM is a post-processing technique that converts MRI phase data into quantitative susceptibility maps,
   enabling the study of tissue magnetic properties such as iron content, calcium, and myelin.
   [..]

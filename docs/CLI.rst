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
   >> quidb.workitems                                      % See e.g. what QuIDBBIDS can make
      "Chimap" "FMW_exrate" "FW_M0map" "FW_R1map" [...]

   >> quidb.resumes.R2R1R2sWorker                          % NB: Only ever edit the `preferred` field
           handle: @qb.workers.R1R2sWorker
             name: "R1R2sWorker"
      description: [24×1 string]
            makes: ["R2starmap" "M0map" "R1map"]
            needs: ["echos4Dmag" "TB1map_GRE" "brainmask"]
          usesGPU: 1
        preferred: 0

   >> quidb.products = ["R1map", "R2starmap", "MWFmap"];   % Specify the output items
   >> quidb.resumes.R2R1R2sWorker.preferred = true;        % Specify the worker that makes the R1/R2starmap

Edit settings and options
-------------------------

All configuration settings and options for processing the data of your dataset can be set per worker by 
modifying the ``config`` properties of your ``QuIDBBIDS`` object. For instance, to inspect the ``NumberShots`` 
parameter of the MP2RAGEWorker and modify it from ``176`` to ``192``, and use your HPC you can do:

.. code-block:: matlab

   >> quidb.config
            General: [1×1 struct]
       B1prepWorker: [1×1 struct]
      MP2RAGEWorker: [1×1 struct]
        R1R2sWorker: [1×1 struct]
          MCRWorker: [1×1 struct]
          QSMWorker: [1×1 struct]

   >> quidb.config.MP2RAGEWorker.NumberShots
          value: 176
    description: 'Number of shots (NZslices) in inversion segment; not usually in JSON. See: 
    https://bids-specification.readthedocs.io/en/stable/appendices/qmri.html#numbershots-metadata-field'

   >> quidb.config.MP2RAGEWorker.NumberShots.value = 192;
   >> quidb.config.General.useHPC.value = true;

Run the workflow
----------------

Finally, to run the workflow, initialize the manager from your ``QuIDBBIDS`` object and start the workflow:

.. code-block:: matlab

   >> mgr       = quidb.manager();  % Initialize the manager to get work done
   >> mgr.force = false;            % Tell the manager to reuse existing workitems (= default)
   >> mgr.start_workflow()          % Start the workflow

For getting more help on the various classes, methods and properties, you can use MATLAB's built-in documentation
browser:

.. code-block:: matlab

   >> doc qb.QuIDBBIDS

A more advanced example of a CLI workflow can be found in this `manual test script <https://github.com/Donders-Institute/quidbbids/blob/main/tests/mantest_dccn.m>`__.

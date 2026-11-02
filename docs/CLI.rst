Command Interface
=================

The QuIDBBIDS workflow can be executed directly from the MATLAB command line, scripts or functions. The paragraphs
below describe a minimal example of how to initialize and run a QuIDBBIDS workflow for all subjects in a BIDS dataset, 
requesting R1, R2*, and MWF maps as output:

.. note::

   QuIDBBIDS also provides GUIs for interactive workflow setup and execution — see :doc:`GUI` for details and
   screenshots. Because ``QuIDBBIDS`` is a handle class, a GUI opened on your object always shares its state, so
   GUI and command line stay in sync. Available calls:

   .. code-block:: matlab

      >> qb.QuIDBBIDS()            % Start the main GUI (Workflow Control Panel)
      >> quidb.start_GUI()         % ...or open it on an existing QuIDBBIDS object
      >> quidb.edit_inclusion()    % BIDS include/exclude filter editor
      >> quidb.set_deliverables()  % Deliverables catalog
      >> quidb.edit_config()       % Config editor (standalone: qb.configeditor())

Initializing QuIDBBIDS
----------------------

To initialize the QuIDBBIDS coordinator, create a ``QuIDBBIDS`` object by providing the path to your BIDS dataset.

.. code-block:: matlab

   >> quidb = qb.QuIDBBIDS('/path/to/bids/dataset');     % Initialize QuIDBBIDS coordinator
   >> quidb.catalog()                                    % See e.g. what QuIDBBIDS can make, given the input data
      Chimap       : Magnetic susceptibility map derived from phase or quantitative susceptibility mapping (QSM) reconstruction
      M0map        : Proton density (M0) map derived from GRE or similar acquisitions
      ME4Dmag      : 4D magnitude image stack from a multi-echo GRE acquisition
      ME4Dphase    : 4D phase image stack from a multi-echo GRE acquisition
      MP2RAGE_T1w  : T1-weighted MP2RAGE image generated from the MP2RAGE sequence
      [..]         : [..]

   >> quidb.resumes.R2R1R2sWorker                        % NB: Only ever edit the `preferred` field
           handle: @qb.workers.R1R2starWorker
             name: "R1R2starWorker"
      description: [24×1 string]
            makes: ["R2starmap" "M0map" "R1map"]
            needs: ["ME4Dmag" "TB1map_GRE" "brainmask"]
          usesGPU: 1
        preferred: 0

   >> quidb.deliverables = ["R1map", "R2starmap", "MWFmap"];   % Specify the output items
   >> quidb.resumes.R2R1R2sWorker.preferred = true;            % Specify the worker that makes the R1/R2starmap

.. tip::

   ``deliverables`` entries may contain regular expressions, e.g. ``quidb.deliverables = ".*map"`` requests all
   workitems ending in "map".

The full constructor signature is ``qb.QuIDBBIDS(bidsdir, outputdir, workdir, configfile)``. By default the output
is written to ``[bidsdir]/derivatives/QuIDBBIDS``, intermediate working data to ``[bidsdir]/derivatives/QuIDBBIDS_work``,
and the configuration is read from / written to ``[outputdir]/code/config.json`` — pass ``outputdir``, ``workdir`` or
``configfile`` to override these. Passing ``configfile = "default"`` deletes any previously saved config and
workflow files and starts from the default configuration.

To restrict which raw BIDS data enter the workflow, set the include/exclude filters (BIDS entities such as subjects,
sessions, suffix) via ``config.General.BIDS.include`` / ``config.General.BIDS.exclude`` before initialising, or edit
them interactively with ``quidb.edit_inclusion()`` (see :doc:`GUI`).

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
        R1R2starWorker: [1×1 struct]
          MCRWorker: [1×1 struct]
          QSMWorker: [1×1 struct]

   >> quidb.config.MP2RAGEWorker.NumberShots
          value: ''
    description: 'Number of shots (NZslices) in inversion segment; not usually in JSON. See: 
    https://bids-specification.readthedocs.io/en/stable/appendices/qmri.html#numbershots-metadata-field'

   >> quidb.config.MP2RAGEWorker.NumberShots.value = 192;
   >> quidb.config.General.useHPC.value = true;

To explicitly write the current settings back to the configuration file, use ``quidb.get_config(quidb.config)``
(this also happens automatically when the workflow starts).

Saving and resuming workflow settings
-------------------------------------

The coordinator and manager can save their state (deliverables, resumes, team, force, ...) to a ``workflow.mat``
file next to the config file, and reload it later — e.g. to resume an interrupted workflow in a new session:

.. code-block:: matlab

   >> quidb.save_properties()           % Save coordinator settings
   >> quidb.manager.save_properties()   % Save manager settings (after get_manager)
   >> quidb.load_properties()           % Reload them later
   >> quidb.manager.load_properties()

Note that ``start_workflow()`` saves the settings automatically before running.

Run the workflow
----------------

Finally, to run the workflow, initialize the manager from your ``QuIDBBIDS`` object and start the workflow:

.. code-block:: matlab

   >> quidb.get_manager()                                      % Initialize the manager to get work done
   >> quidb.manager.force = ["B1prepWorker", "MP2RAGEWorker"]; % Reuse existing workitems except for these workers and their dependencies
   >> quidb.manager.start_workflow()                           % Start the workflow for all subjects

To run the workflow only for specific subjects, pass them to ``start_workflow``:

.. code-block:: matlab

   >> quidb.manager.start_workflow(["sub-01", "sub-02"])       % Only these subjects

For fully scripted (non-interactive) runs, disable the interactive popups (worker selection, lockfile cleanup) with:

.. code-block:: matlab

   >> quidb.interactive = false;    % Set before get_manager(); the manager inherits it

Staged runs
-----------

You can run the workflow in stages: change ``deliverables`` (and settings) between ``start_workflow()`` calls and
only the new deliverables will be computed — existing workitems in the work directory are reused. This is useful to
run e.g. the CPU part first and the GPU part later with different HPC resources:

.. code-block:: matlab

   >> quidb.deliverables = "MWFmap";                                    % CPU-only part
   >> quidb.config.General.HPC.value = {'memreq', 20e9, 'timreq', 48*36e2};
   >> quidb.get_manager(); quidb.manager.start_workflow()

   >> quidb.deliverables = ["R1map", "R2starmap", "Chimap", "MWFmap"];  % GPU part
   >> quidb.config.General.HPC.value = {'memreq', 20e9, 'timreq', 10*36e2, 'options', '--partition=gpu --gres=gpu:1'};
   >> quidb.get_manager(); quidb.manager.start_workflow()

The ``HPC`` setting is passed to ``qsubfeval()``, so it accepts any qsub option (memory, walltime, GPU partitions,
etc.). To distinguish outputs of different runs, set a tag: ``quidb.config.General.tag.value = "run1"`` (it is
added to the deliverable filenames).

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
   QSMWorker : Quantitative Susceptibility Mapping (QSM) and R2* relaxometry worker using the SEPIA
   toolbox.

   QSMWorker performs QSM reconstruction and R2* mapping from multi-echo GRE magnitude and phase data.
   QSM is a post-processing technique that converts MRI phase data into quantitative susceptibility
   maps, enabling the study of tissue magnetic properties such as iron content, calcium, and myelin.
   [..]

   needs:   ME4Dmag, ME4Dphase, brainmask
   usesGPU: false

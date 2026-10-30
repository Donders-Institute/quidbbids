Graphical User Interface
========================

The main window: Workflow Control Panel
---------------------------------------
QuIDBBIDS provides a main graphical user interface (GUI) — the *Workflow Control Panel* — for users that prefer
an interactive approach to workflow configuration and execution. To launch it, initialize the QuIDBBIDS coordinator
without input arguments and select your BIDS folder in the file dialog:

.. code-block:: matlab

   >> quidb = qb.QuIDBBIDS();    % Select your BIDS folder to launch the Workflow Control Panel

If you initialized QuIDBBIDS from the command line, you can open the Workflow Control Panel at any time with:

.. code-block:: matlab

   >> quidb = qb.QuIDBBIDS('/path/to/bids/dataset');   % Initialize in CLI mode
   >> quidb.start_GUI()                                % Open the Workflow Control Panel

The Workflow Control Panel is organized in the areas shown in the figure below:

.. figure:: ./_static/workflow_control_panel.png
   :alt: The Workflow Control Panel

   The Workflow Control Panel: setup buttons on the left, the workflow graph in the center, the workflow control
   buttons (Load/Save/Start) at the bottom left, and a summary table of the dataset and settings at the bottom right.

* **Left panel — setup buttons.** These buttons guide you through the workflow setup step by step; they are
  enabled or disabled depending on how far you are in the setup process:

  * *Inclusion* — Edit the BIDS include/exclude filter that selects which raw data are used in the workflow.
    Opens the inclusion editor GUI (see below).
  * *Catalog* — Select your deliverables (output items such as ``R1map`` and ``MWFmap``) from the catalog of
    workitems that the available workers can produce for your dataset. Opens the deliverables GUI (see below).
    Selecting deliverables builds the workflow team and draws the workflow graph in the center panel.
  * *Config* — Edit the processing settings and options per worker. Opens the config editor GUI (see below).
  * *Outputdir* — Set the directory where the output data (deliverables) will be saved.
  * *Workdir* — Set the directory where intermediate working data will be saved.
  * *Reset* — Clear all deliverables and reset the workflow graph and configuration to the defaults.

* **Center panel — workflow graph.** A graphical representation of the workflow for your dataset (center of the
  figure above): raw input data at the top (grey nodes prefixed with ``raw*``, e.g. ``rawMEGRE``), the selected team
  of workers in the middle (blue nodes), and the output deliverables at the bottom (orange nodes, e.g. ``Chimap``
  and ``R1map``). The graph is redrawn automatically when you change the inclusion filter or the deliverables.
  Hover over a node to see what it does; click a worker node to force recomputing its output, or click a workitem
  node to add/remove it from the deliverables.

* **Bottom-right — info table.** A summary of the BIDS dataset and current workflow settings: number of
  subjects/sessions, the selected deliverables, and the output and working directories.

* **Bottom-left panel — workflow control buttons:**

  * *Load* — Load previously saved workflow settings (both the coordinator and the manager properties).
  * *Save* — Save your current workflow settings.
  * *Start* — Save the settings and start the workflow. All buttons are disabled while the workflow runs; when
    the workflow has completed, an info dialog is shown.

The sub-GUIs described in the sections below are launched from the buttons in the Workflow Control Panel, but can
also be called directly from the MATLAB command window.

Inclusion editor
----------------
The *Inclusion* button in the Workflow Control Panel (or calling ``edit_inclusion()``) opens a GUI to edit the
include and exclude filters that determine which raw BIDS data are included in the workflow:

.. code-block:: matlab

   >> quidb.edit_inclusion()   % Opens the BIDS inclusion editor GUI

The GUI shows two JSON text areas — one for the include filter and one for the exclude filter — next to a tree
view of your BIDS dataset. As you edit the filters, the tree is updated live and included files and folders are
tagged with a green-dot icon. Use *Reset* to restore the original filters, *Cancel* to discard your changes, or
*Done* to apply them. When applied, the BIDS dataset is re-indexed with the new filter and the workflow graph in
the Workflow Control Panel is redrawn.

.. figure:: ./_static/include_editor.png
   :alt: The BIDS inclusion editor

   The inclusion editor: include/exclude filters as JSON (left) and the BIDS data tree with included items tagged
   by green dots (right).

Deliverables catalog
--------------------
The *Catalog* button in the Workflow Control Panel (or calling ``set_deliverables()``) opens a GUI with a table
of all workitems that the available workers can produce for your dataset, together with their descriptions:

.. code-block:: matlab

   >> quidb.set_deliverables()   % Opens the deliverables selection GUI

Tick the checkboxes of the deliverables you want (e.g. ``R1map`` and ``MWFmap``) and press *Done* (or *Reset* to
restore the previous selection, *Cancel* to discard). If multiple workers can produce one of your deliverables, a
worker-selection GUI pops up in which you can choose the worker to use, showing each candidate's description, the
workitems it needs, and the workitems it makes.

.. figure:: ./_static/catalog.png
   :alt: The deliverables catalog

   The deliverables catalog: all workitems that the available workers can produce for your dataset, with their
   descriptions, and checkboxes to select the desired deliverables.

Processing settings and options
-------------------------------
All configuration settings and options for processing the data can be set per worker with a GUI — the config
editor — which can be launched from the *Config* button in the Workflow Control Panel, by calling the
``edit_config()`` method from your ``QuIDBBIDS`` object, or by directly calling the ``configeditor()`` function:

.. code-block:: matlab

   >> quidb.edit_config()  % Opens a GUI to edit the settings of your dataset
   >> qb.configeditor()    % Opens a GUI to edit the settings of any dataset

.. figure:: ./_static/configeditor.png
   :alt: The QuIDBBIDS config editor

   Left panel: The General QuIDBBIDS settings as well as the settings for the individual workers. In this
   example the user navigated to a ``QSMWorker`` SEPIA menu item (e.g. ``QSM.qsm`` or ``QSM.unwrap``) — editing
   its value opens the native SEPIA GUI (see below). Right panel: the description of the
   selected parameter (top) with a box to edit its current value (bottom). Other (non-SEPIA) parameters can be
   edited directly in the value box.

The ``QSMWorker`` (QSM) and ``R2starWorker`` (R2* relaxometry) both use the SEPIA toolbox, which comes with its own
collection of settings. If a ``QSMWorker`` or ``R2starWorker`` setting represents a SEPIA menu item (i.e., an option
that defines a set of SEPIA processing options rather than just a single setting — e.g. the ``unwrap``, ``bfr``,
``qsm`` or ``r2s`` subtrees, as in the figure above), QuIDBBIDS launches a minimal native SEPIA GUI, allowing you to
adjust the SEPIA settings in there. Settings that are not menu items (e.g., numerical parameters) can be edited
normally in the value box.

General settings
~~~~~~~~~~~~~~~~
The settings in ``General`` apply to all Workers and workflow in general. Here you can add your settings to use
any parallel compute resources, for instance whether or how to use your HPC cluster or GPU. A few settings are of 
particular interest:

   * ``tag``. A custom tag that is added to the deliverables, e.g. to distinguish or compare the results when using
     different parameter settings. In such use cases, you could iteratively: (1) update the config parameter(s) and
     output tag, (2) delete or force the workitems that need to be re-computed from the work-folder (3) execute the
     workflow. In this way unaffected work-items in the work-folder can be reused, while the deliverables are save
     with different tags in the output-folder.
     
   * ``useHPC`` / ``HPC``. Set ``useHPC`` to ``true`` to run the workflow on an HPC cluster, submitting each job
     with ``qsubfeval()`` (requires the qsub toolbox). The ``HPC`` setting holds the resource requirements as a
     name-value cell array that is passed on to ``qsubfeval()`` — by default ``["memreq", 10e9, "timreq", 36000]``,
     i.e. 10 GB memory and 10 hours walltime per job (see ``config_default.json``).

   * ``useParallel``. Set to ``true`` to process subjects in parallel on the local machine with ``parfeval()``
     (this option is ignored when ``useHPC`` is ``true``).

Run the workflow
----------------

To run the workflow from the GUI, press the *Start* button in the Workflow Control Panel. This saves your settings
and starts the workflow; all buttons are disabled while the workflow runs.

Alternatively, from the command line, initialize the manager and start the workflow:

.. code-block:: matlab

   >> quidb.get_manager()
   >> quidb.manager.start_workflow()   % NB: See the CLI section to forcefully re-running (subtrees of) workflows

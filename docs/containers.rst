Containers
==========

QuIDBBIDS is distributed as a native MATLAB toolbox (see :doc:`installation`), but it can also be run as a
containerized app. This is useful for users who encounter issues with installing QuIDBBIDS and its dependencies
(e.g. SEPIA), that do not have a MATLAB license, or that want to run QuIDBBIDS in a cloud environment.

The containerized QuIDBBIDS app serves two use cases, each available in a GUI and a CLI variant.

1. **Licensed.** If you have a MATLAB license, you can run full MATLAB inside the container exactly as on
   your desktop: start it with ``matlab`` and drive QuIDBBIDS from the GUI or MATLAB command line, where
   QuIDBBIDS and its dependencies already have been installed.

2. **License-free.** If you do not have a MATLAB license, you can run the (MCR compiled) QuIDBBIDS executable
   that is shipped with the container. It calls the same methods you would call in MATLAB (see :doc:`CLI` and
   :doc:`GUI`): with the BIDS directory as argument it runs in CLI mode, and when started without arguments it
   opens the same Workflow Control Panel GUI as desktop MATLAB.

   .. note:: The compiled executable may not be able to run all configurable QSM (SEPIA) workflows, as some of
      them may involve non-free licenses or dynamic path modifications that are not supported in the compiled app.

Getting the image
-----------------

Prebuilt images are published with each QuIDBBIDS release: as a Docker image on the Docker Hub registry, and as
an Apptainer/SIF image in the GitHub registry. Pull the one matching the release you want (here ``<version>``).
Each image is built for the same fixed MATLAB release (e.g. R2026a), which is also the release of the compiled
app inside it:

.. code-block:: console

   # Apptainer
   apptainer pull oras://ghcr.io/donders-institute/quidbbids:<version>
   # Or download from the release page (https://github.com/Donders-Institute/quidbbids/releases)

   # Docker -- requires root privileges (prefix with `sudo` command if needed)
   docker pull quidbbids:<version>

To build the image yourself from source, see ``containers/apptainer.def`` / ``containers/Dockerfile``;
compiling the standalone app with ``mcc`` then requires a MATLAB license at build time
(``MLM_LICENSE_FILE=port@license-server``), and SEPIA's non-git dependencies must be placed in
``containers/sepia/external/`` (e.g. ``segue``, ``mrisc``).

Running a workflow
------------------

In all commands below, your BIDS dataset is mounted to a ``/data/bids`` folder inside the container
(``--bind /data/bids:/data/bids`` for Apptainer, ``-v /data/bids:/data/bids`` for Docker). Here
``/data/bids`` is just the conventional mount point for the BIDS dataset root folder on the host,
e.g. ``/home/me/mystudy/bids``; the container sees it at the same path. Anything QuIDBBIDS writes goes to
``/data/bids/derivatives/QuIDBBIDS`` (and ``..._work``) by default, i.e. back into your host folder.

Another thing to note is that containerized GUIs need an X display. If the container runs on a remote
host, connect with ``ssh -X`` (or ``-Y``) so the display of your local machine is forwarded; if the
connection is rejected, run ``xhost +`` on the machine running the X server (your local desktop). On
Apptainer, the host environment and sockets are usually passed through automatically. On Docker you must
pass them explicitly: ``-e DISPLAY=$DISPLAY`` and ``-v /tmp/.X11-unix:/tmp/.X11-unix`` (see the examples
below). On Wayland desktops this works transparently via XWayland.

Licensed (full MATLAB)
~~~~~~~~~~~~~~~~~~~~~~

Start an interactive MATLAB inside the container and drive QuIDBBIDS from the MATLAB :doc:`CLI`
or with a :doc:`GUI`, exactly as in a normal MATLAB session with QuIDBBIDS and its dependencies
fully installed and on the path. Just pass your license server at run time via ``MLM_LICENSE_FILE``.

.. code-block:: console

   # Apptainer
   apptainer exec --env MLM_LICENSE_FILE=27000@your-license-server \
       --bind /data/bids:/data/bids quidbbids-<version>.sif matlab

   # Docker (``-it`` for the terminal; the X11 flags are only needed for the GUI)
   docker run --rm -it -e DISPLAY=$DISPLAY -e MLM_LICENSE_FILE=27000@your-license-server \
       -v /tmp/.X11-unix:/tmp/.X11-unix -v /data/bids:/data/bids --entrypoint matlab quidbbids:<version>

License-free (compiled MCR app)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Graphical User Interface
^^^^^^^^^^^^^^^^^^^^^^^^

The default run command executes the compiled QuIDBBIDS app, without launching a MATLAB window (no license
needed at run time). With no arguments it opens the Workflow Control Panel GUI (folder picker, as in
:doc:`GUI`): you pick the BIDS dataset, choose the deliverables and settings in the panel, and press start
to run the workflow -- all the same as in desktop MATLAB:

.. code-block:: console

   # Apptainer
   apptainer run --bind /data/bids:/data/bids quidbbids-<version>.sif

   # Docker
   docker run --rm -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
       -v /data/bids:/data/bids quidbbids:<version>

Command-line Interface
^^^^^^^^^^^^^^^^^^^^^^

With the BIDS directory as the first (positional) argument, the app runs in :doc:`CLI` mode -- useful for
automated processing or batch jobs. With no MATLAB window or GUI, pass all run configuration as options
at once; the workflow manager is started automatically. Available options (passed after the positional
bidsdir argument):

- ``--outputdir PATH`` -- output dir (default: ``BIDSDIR/derivatives/QuIDBBIDS``)
- ``--workdir PATH`` -- work dir (default: ``BIDSDIR/derivatives/QuIDBBIDS_work``)
- ``--configfile PATH`` -- config file (e.g. ``BIDSDIR/code/quidbbids_config.json``)
- ``--deliverables LIST`` -- comma-separated deliverables (e.g. ``MWFmap,Chimap``)
- ``--subjects LIST`` -- comma-separated subjects to process (default: all)
- ``--prefer LIST`` -- workers to prefer for resumes
- ``--force LIST`` -- workers to force re-run
- ``--set KEY=VALUE`` -- set ``config.<KEY>.value`` (repeatable), e.g.
  ``--set MEGREprepWorker.brainmask.method=hd-bet``
- ``--help`` -- show the full help

.. code-block:: console

   # Apptainer
   apptainer run --bind /data/bids:/data/bids quidbbids-<version>.sif /data/bids \
       --deliverables MWFmap,Chimap --configfile /data/bids/code/quidbbids_config.json

   # Docker
   docker run --rm -v /data/bids:/data/bids quidbbids:<version> \
       /data/bids --deliverables MWFmap,Chimap --configfile /data/bids/code/quidbbids_config.json

For the full list of flags, run the app with ``--help``, e.g. ``apptainer run quidbbids-<version>.sif --help``
or ``docker run --rm quidbbids:<version> --help``.

.. note::

   - GPU workers (``MCR_GPUWorker``, ``R1R2starWorker``): add ``--nv`` (Apptainer) or ``--gpus all`` (Docker);
     if CUDA libraries are missing, build from ``mathworks/matlab-deep-learning`` instead of ``mathworks/matlab``.
   - In-container HPC submission (``config.General.useHPC``) needs the scheduler's ``qsub`` binary, which is
     not included; submit from the host instead.

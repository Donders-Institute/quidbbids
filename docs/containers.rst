Containers
==========

QuIDBBIDS is distributed as a native MATLAB toolbox (see :doc:`installation`), but it can also be run as a
containerized app. This is useful for users that encounter issues with installing QuIDBBIDS and its dependencies
(e.g. SEPIA), that do not have a MATLAB license, or that want to run QuIDBBIDS in a cloud environment.

The containerized QuIDBBIDS app serves two use cases, each available in a GUI and a CLI variant.

1. **Licensed.** If you have a MATLAB license, you can run full MATLAB inside the container exactly as on
   your desktop: start it with ``matlab`` and drive QuIDBBIDS from the GUI or MATLAB command line (see
   :doc:`GUI` and :doc:`CLI`), with the QuIDBBIDS source tree already on disk at ``/opt/quidbbids``.

2. **License-free.** If you do not have a MATLAB license, you can run the (MCR compiled) QuIDBBIDS executable
   that is shipped with the container. Its command-line interface mirrors the native API (``quidbbids --help``
   lists the flags), and when started without arguments it opens the same Workflow Control Panel GUI as desktop
   MATLAB. It should be noted that the compiled executable may not be able to run all configurable QSM/R2star
   (SEPIA) workflows, as some may involve dynamic path modifications that are not supported in the compiled app.

The GUI variants of both use cases need an X display (X11 forwarding - may need ``xhost +``; on Wayland desktops
this should work unchanged via XWayland).

Getting the image
-----------------

Prebuilt images are published with each QuIDBBIDS release: as a Docker image on Docker Hub and as an
Apptainer/SIF file in the GitHub release assets. Pull the one matching the release you want (here
``v1.0.0``). Each image is built for a fixed MATLAB release (e.g. R2026a), which is also the release of the
compiled app inside it:

.. code-block:: console

   # Apptainer
   apptainer pull oras://ghcr.io/donders-institute/quidbbids:<version>
   # Or download from the release page (https://github.com/Donders-Institute/quidbbids/releases)

   # Docker - requires root privileges (prefix with `sudo` command if needed)
   docker pull quidbbids:<version>

To build the image yourself from source, see ``containers/apptainer.def`` / ``containers/Dockerfile``;
compiling the standalone app with ``mcc`` then requires a MATLAB license at build time
(``MLM_LICENSE_FILE=port@license-server``), and SEPIA's non-git dependencies must be placed in
``containers/sepia/external/`` (e.g. ``segue``, ``mrisc``).

Running
-------

Below are example commands for running the containerized QuIDBBIDS app. In all cases, bind your BIDS
dataset folder to ``/data/bids`` inside the container (``--bind /data/bids:/data/bids`` for Apptainer,
``-v /data/bids:/data/bids`` for Docker). Here ``/data/bids`` is just the conventional mount point for the
BIDS dataset *root* on the host, e.g. ``/home/me/mystudy/bids``; the container sees it at the same path,
so pass ``--bidsdir /data/bids`` to the app. Anything QuIDBBIDS writes goes to
``/data/bids/derivatives/QuIDBBIDS`` (and ``..._work``) by default, i.e. back into your host folder via the
bind; use ``--outputdir``/``--workdir`` to redirect elsewhere.

The compiled app's command-line interface mirrors the native MATLAB API (see :doc:`CLI`): ``--bidsdir``
(required in CLI mode), ``--outputdir``, ``--workdir``, ``--configfile``, ``--deliverables``,
``--subjects``, ``--prefer``, ``--force``, and repeatable ``--set KEY=VALUE`` (sets
``config.<KEY>.value``, e.g. ``--set MEGREprepWorker.brainmask.method=hd-bet``). With no arguments the
GUI mode starts (a folder picker opens, as in :doc:`GUI`). For the full list of flags, run the app with
``--help``, e.g. ``apptainer run quidbbids-v1.0.0.sif --help`` or ``docker run --rm quidbbids:v1.0.0 --help``.

Apptainer usage
~~~~~~~~~~~~~~~

.. code-block:: console

   # 1. full MATLAB (licensed): interactive MATLAB terminal; use the GUI or the MATLAB command line
   #    as on your desktop (see :doc:`GUI` and :doc:`CLI`)
   apptainer exec --env MLM_LICENSE_FILE=27000@your-license-server \
       --bind /data/bids:/data/bids quidbbids-v1.0.0.sif matlab

   # 2a. compiled app, GUI (license-free; no arguments = GUI mode, folder picker; X11 forwarding)
   apptainer run --bind /data/bids:/data/bids quidbbids-v1.0.0.sif

   # 2b. compiled app, CLI (license-free)
   apptainer run --bind /data/bids:/data/bids quidbbids-v1.0.0.sif --bidsdir /data/bids --deliverables MWFmap,Chimap \
       --set MEGREprepWorker.brainmask.method=hd-bet

Docker usage
~~~~~~~~~~~~

.. code-block:: console

   # 1. full MATLAB (licensed): interactive MATLAB terminal (-it for the TTY); use the GUI or the
   #    MATLAB command line as on your desktop (see :doc:`GUI` and :doc:`CLI`)
   docker run --rm -it -e DISPLAY=$DISPLAY -e MLM_LICENSE_FILE=27000@your-license-server \
       -v /tmp/.X11-unix:/tmp/.X11-unix -v /data/bids:/data/bids --entrypoint matlab quidbbids:v1.0.0

   # 2a. compiled app, GUI (license-free, X11 forwarding)
   docker run --rm -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
       -v /data/bids:/data/bids quidbbids:v1.0.0

   # 2b. compiled app, CLI (license-free)
   docker run --rm -v /data/bids:/data/bids quidbbids:v1.0.0 \
       --bidsdir /data/bids --deliverables MWFmap,Chimap \
       --set MEGREprepWorker.brainmask.method=hd-bet --set VFAprepWorker.brainmask.method=hd-bet

.. note::

   - GPU workers (``MCR_GPUWorker``, ``R1R2starWorker``): add ``--nv`` (Apptainer) or ``--gpus all`` (Docker);
     if CUDA libraries are missing, build from ``mathworks/matlab-deep-learning`` instead of ``mathworks/matlab``.
   - In-container HPC submission (``config.General.useHPC``) needs the scheduler's ``qsub`` binary, which is
     not included; submit from the host instead.

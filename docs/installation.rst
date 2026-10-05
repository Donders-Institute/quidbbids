Installation
============

QuIDBBIDS is a MATLAB package compatible with Linux, Windows, and macOS systems.

Requirements
------------

- `MATLAB <https://nl.mathworks.com/products/MATLAB.html>`__ (see `project.json <https://github.com/Donders-Institute/quidbbids/blob/main/project.json>`__ for version details)
- `Git <https://git-scm.com>`__ (for cloning and updating; optional if downloading a ZIP archive)

Installation Methods
--------------------

Git (Recommended)
~~~~~~~~~~~~~~~~~

The recommended approach uses Git to install QuIDBBIDS and its dependencies. This allows easy access
to specific releases (``main`` branch) or the latest development code (``dev`` branch; see the 
`contributing guide <https://github.com/Donders-Institute/quidbbids/blob/dev/CONTRIBUTING.rst>`__).

.. code-block:: console

   git clone --recurse-submodules https://github.com/Donders-Institute/QuIDBBIDS.git

This creates a ``QuIDBBIDS`` folder containing both the package and its submodule dependencies.

**MATLAB Path Setup**

Add the ``QuIDBBIDS`` folder (without subfolders) to your MATLAB path.

.. code-block:: matlab

   addpath('/path/to/QuIDBBIDS')

Or use the MATLAB GUI: *Home → Set Path → Add Folder*.

ZIP Archive (Alternative)
~~~~~~~~~~~~~~~~~~~~~~~~~

Download the latest release from the `releases page <https://github.com/Donders-Institute/QuIDBBIDS/releases>`__
and extract the ZIP file. Add the extracted ``QuIDBBIDS`` folder to your MATLAB path as above.

.. note::
   ZIP downloads do not include submodule dependencies, which will need to be installed manually.

Configuration
-------------

On first run, QuIDBBIDS creates a version-specific default configuration file at ``~/.quidbbids/v#.#.#/config_default.json``.

- **Modify settings**: Edit the configuration file directly to adjust the settings to your site specific needs.
- **Reset to defaults**: Run ``qb.resetconfig()`` in MATLAB to restore the factory default settings.

Dependencies
------------

QuIDBBIDS automatically detects and uses system-wide installations of its dependencies. If not found,
it will use versions from the ``dependencies`` folder (populated only when using ``--recurse-submodules``).

See the `.gitmodules <https://github.com/Donders-Institute/QuIDBBIDS/blob/main/.gitmodules>`__ file for
manual installation instructions for each dependency.

Required Manual Installations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Some dependencies cannot be fully installed via Git alone. One notable case is the
`SEPIA <https://github.com/kschan0214/sepia>`__ toolbox, which requires manual configuration and installation
of a few (non-git) dependencies of its own. In short, you need to install:

1. `CompileMRI <https://github.com/korbinian90/CompileMRI.jl>`__
2. `SEGUE <https://xip.uclb.com/product/SEGUE>`__ 
3. `TKD/iterTik/dirTik <https://xip.uclb.com/product/mri_qsm_tkd>`__ 

After installing these, update ``sepia/SpecifyToolboxesDirectory.m`` with the correct paths. Reference information
on installing SEPIA and its external dependencies can be found in the
`SEPIA Documentation <https://sepia-documentation.readthedocs.io/en/latest/getting_started/Installation.html>`__.

Optional Dependencies
~~~~~~~~~~~~~~~~~~~~~

A few tools are required for some of the QuIDBBIDS workers:

* **FreeSurfer (mri_synthstrip)**. FreeSurfer's `mri_synthstrip` is the preferred brain extraction tool used in QuIDBBIDS
  preprocessing. However, it is not strictly needed, as QuIDBBIDS will use the BET implementation distributed by the (already
  installed) MEDI toolbox as a fallback.
* **MRtrix3 (fod2fixel, fixel2voxel, fixel2peaks)**. The diffusion informed myelin-water (DI-MWI) model estimation requires
  pre-processed BIDS derivative DWI data that follows the `qsirecon <https://qsirecon.readthedocs.io>`__ conventions. In such
  workflows QuIDBBIDS will convert the qsirecon data to fixel representations, which requires
  `MRtrix3 <https://www.mrtrix.org/>`__ to be present on your system.

Version Selection
-----------------

If you have installed QuIDBBIDS with Git, you can rapidly switch between versions:

.. code-block:: console

   cd QuIDBBIDS
   git tag                                  # List all release versions (e.g., v1.0.0, v1.1.0)
   git checkout v1.0.1                      # Switch to a specific release
   git checkout HEAD                        # Or switch to the latest version
   git submodule update --init --recursive  # Initialize submodules for this version

To use the very latest (unstable) software, you can switch to the ``dev`` branch:

.. code-block:: console

   git switch -c dev origin/dev             # Create and checkout dev branch
   git switch dev                           # Switch to existing dev branch
   git submodule update --init --recursive  # Initialize submodules for this version

In case of trouble, to forcefully reset your installation to, say, the latest version run:

.. code-block:: console

   git reset --hard HEAD   # NB: This will discard any local changes you may have made to the repository
   git submodule update --init --recursive

Updating QuIDBBIDS
------------------

To update a Git installed QuIDBBIDS and all its dependencies to the latest version, navigate to your local repository and run:

.. code-block:: console

   git pull --tags --recurse-submodules

.. note::

   If you are using the ``dev`` branch, then your default config file in your home directory will not be updated by
   ``git pull``. You should therefore always run ``qb.resetconfig()`` after pulling the dev updates.

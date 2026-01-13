Installation
============

QuIDBBIDS is a MATLAB package that can be installed on Linux, Windows, and macOS systems, provided the following requirements are met.

**Requirements:**

- `MATLAB <https://nl.mathworks.com/products/MATLAB.html>`__ (R2024b or later)
- `Git <https://git-scm.com>`__ (for cloning and updating the repository)

Installing QuIDBBIDS
--------------------

The recommended installation method is via **Git**. This allows you to easily obtain a specific release (``main``
branch) or the latest development version (``dev`` branch; see the contributing guide <https://github.com/Donders-Institute/quidbbids/blob/dev/CONTRIBUTING.rst>`__).

To clone QuIDBBIDS and its dependencies, run:

.. code-block:: console

   git clone --recurse-submodules https://github.com/Donders-Institute/QuIDBBIDS.git

This will create a folder named ``QuIDBBIDS`` in your current directory.

To install a specific **versioned release**, list available tags and check out the desired one, for example:

.. code-block:: console

   cd QuIDBBIDS
   git tag                        # List available release versions (e.g., v1.0.0, v1.0.1, v1.1.0)
   git checkout v1.0.1            # Check out a specific (stable) release version
   git switch -c dev origin/dev   # Check out the latest (unstable) development code

And to update the dev branch:

.. code-block:: console

   git switch dev                 # Check out your dev branch
   git pull                       # Get the latest code
   qb.reset()                     # Reset QuIDBBIDS settings to latest value (may be required after updates)

Then, in MATLAB, add the cloned ``QuIDBBIDS`` folder (without subfolders) to your MATLAB path.

.. note::
   QuIDBBIDS depends on several external MATLAB toolboxes (see *Requirements* above).
   Make sure these dependencies are installed and accessible from your MATLAB path.

Installing dependencies
-----------------------

If you have cloned QuIDBBIDS with ``--recurse-submodules`` you already have `SEPIA <https://github.com/kschan0214/sepia>`__ 
in your QuIDBBIDS ``dependencies`` folder. However, it is required that you install SEPIA's 
`CompileMRI <https://github.com/korbinian90/CompileMRI.jl>`__, `SEGUE <https://xip.uclb.com/product/SEGUE>`__ and the 
`TKD/iterTik/dirTik <https://xip.uclb.com/product/mri_qsm_tkd>`__ dependencies yourself, and edit 
``sepia/SpecifyToolboxesDirectory.m`` accordingly. See 
`here <https://sepia-documentation.readthedocs.io/en/latest/getting_started/Installation.html>`__ for more info.

Updating QuIDBBIDS
------------------

If you installed QuIDBBIDS using Git, navigate to your local repository and run:

.. code-block:: console

   git pull --tags --recurse-submodules

This updates QuIDBBIDS and all dependencies to the latest version on the current branch.
To update to a specific release tag instead, use:

.. code-block:: console

   git tag                        # List available versions (e.g., v1.0.0, v1.0.1, v1.1.0)
   git checkout v1.1.0            # Check out a specific version

Installation
============

QuIDBBIDS is a MATLAB package and can be installed on Linux, MS Windows and on OS-X computers, as long as the following requirements are met: 

**Requirements:**

- `MATLAB <https://nl.mathworks.com/products/MATLAB.html>`__ (R2024b or later)
- `SPM <https://www.fil.ion.ucl.ac.uk/spm/>`__ (SPM12 or later)
- `bids-matlab <https://github.com/bids-standard/bids-matlab>`__

Installing QuIDBBIDS
--------------------

Stable QuIDBBIDS releases can be installed most easily using MATLAB's built-in `Add-on Explorer <https://nl.mathworks.com/help/MATLAB/MATLAB_env/get-add-ons.html>`__:

1. Open MATLAB and navigate to:
   
   - **Home** tab → **Environment** section → Click the **Add-Ons** button
  
2. This opens the Add-On Explorer. In there:
   
   - Type "quidbbids" in the search field
   - Select the QuIDBBIDS package from the results
   - Click **Add** to install and follow the instructions to include the dependencies

Alternatively, you can downloaded the package from the MATLAB central `fileexchange <https://nl.mathworks.com/MATLABcentral/fileexchange>`__ or from `GitHub <https://github.com/orgs/Donders-Institute/packages?repo_name=quidbbids>`__. After downloading, you can add the (unzipped) QuIDBBIDS folder to your MATLAB path yourself (NB: that is without subfolders), or just double click on the ``QuIDBBIDS.mltbx`` file in MATLAB's Current Folder toolbar.

If you like to use the latest (development/unstable) code and have a working Git installation, you can install QuIDBBIDS by running the following commands in a command terminal:

.. code-block:: console

   $ git clone https://github.com/Donders-Institute/QuIDBBIDS.git                         # This installs the QuIDBBIDS-package only
   $ git clone --recurse-submodules https://github.com/Donders-Institute/QuIDBBIDS.git    # This installs the QuIDBBIDS-package + all dependencies

Add the cloned QuIDBBIDS folder to your MATLAB path (without subfolders).

.. note::
   As listed above, QuIDBBIDS has a number of dependencies that are required for the package to work. Not all of these dependencies may not have been automatically installed when you installed QuIDBBIDS. In that case, you should install them manually.

Updating QuIDBBIDS
------------------

You can update QuIDBBIDS using the Add-On Manager:

1. On the **Home** tab→ **Resources** section → **Help** > **Check for Updates**
2. View and install any available update(s)

Alternatively, if you used git to install QuIDBBIDS, in a command terminal navigate to your QuIDBBIDS folder and run:

.. code-block:: console

   $ git pull                       # This updates QuIDBBIDS only
   $ git pull --recurse-submodules  # This updates everything

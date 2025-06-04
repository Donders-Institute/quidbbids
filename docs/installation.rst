Installation
============

QuIDBBIDS is a MATLAB package and can be installed on Linux, Windows, and macOS systems, provided the following requirements are met:

**Requirements:**

- `MATLAB <https://nl.mathworks.com/products/MATLAB.html>`__ (R2024b or later)
- `SPM <https://www.fil.ion.ucl.ac.uk/spm/>`__ (SPM12 or later)
- `bids-matlab <https://github.com/bids-standard/bids-matlab>`__

Installing QuIDBBIDS
--------------------

Stable releases of QuIDBBIDS can most easily be installed using MATLAB's built-in `Add-On Explorer <https://nl.mathworks.com/help/MATLAB/MATLAB_env/get-add-ons.html>`__:

1. Open MATLAB and navigate to:
   
   - **Home** tab → **Environment** section → Click the **Add-Ons** button

2. In the Add-On Explorer:

   - Type "quidbbids" in the search field
   - Select the QuIDBBIDS package from the results
   - Click **Add** to install and follow the instructions to include the dependencies

Alternatively, you can download the package from MATLAB Central's `File Exchange <https://nl.mathworks.com/MATLABcentral/fileexchange>`__ or from `GitHub <https://github.com/orgs/Donders-Institute/packages?repo_name=quidbbids>`__. After downloading, you can either:

- Add the (unzipped) QuIDBBIDS folder to your MATLAB path manually (without subfolders), or
- Double-click the ``QuIDBBIDS.mltbx`` file in MATLAB’s **Current Folder** panel

If you prefer the latest (development/unstable) version and have a working Git installation, run the following in a terminal:

.. code-block:: console

   $ git clone https://github.com/Donders-Institute/QuIDBBIDS.git                       # QuIDBBIDS only
   $ git clone --recurse-submodules https://github.com/Donders-Institute/QuIDBBIDS.git  # QuIDBBIDS + dependencies

Then add the cloned QuIDBBIDS folder to your MATLAB path (without subfolders).

.. note::
   As listed above, QuIDBBIDS has several required dependencies. These may not all be automatically installed when installing QuIDBBIDS. If not, please install them manually.

Updating QuIDBBIDS
------------------

To update QuIDBBIDS using the Add-On Manager:

1. Go to the **Home** tab → **Resources** section → **Help** → **Check for Updates**
2. View and install any available updates

Alternatively, if you installed QuIDBBIDS using Git, navigate to your QuIDBBIDS folder in a terminal and run:

.. code-block:: console

   $ git pull                       # Updates QuIDBBIDS only
   $ git pull --recurse-submodules  # Updates QuIDBBIDS and all dependencies

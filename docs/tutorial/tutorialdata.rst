Tutorial data
=============

Prerequisites
-------------
Install QuIDBBIDS(and its dependencies), in your MATLAB environment,
you can find the installation instruction on the :doc:`/installation` page

.. note::
 
   Make sure that the QuIDBBIDS folder (without subfolders) is on your MATLAB path.
   You can verify this by typing ``qb.QuIDBBIDS`` in the MATLAB command window — it
   should not return an error.

You will also need a BIDS formatted dataset that contains multi-echo GRE (MEGRE) data magnitude and phase images.
If you don't have one, you can download the tutorial dataset using:

.. code-block:: matlab

   >> qb.tutorialdata()

.. tip::
 
   If you want to use your own non-BIDS dataset, you can use `BIDScoin <https://bidscoin.readthedocs.io>`__ to convert it to the BIDS format.

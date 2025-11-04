===============================================
Quantitative Imaging Derived Biomarkers in BIDS
===============================================

|Tests| |RTD| |GPLv3|

.. raw:: html

   <img name="quidbbids-logo" src="https://github.com/Donders-Institute/quidbbids/blob/main/docs/_static/quidbbids_logo.png" height="150px" alt=" ">

QuIDBBIDS is a MATLAB BIDS-app that enables researchers to easily preprocess and compute quantitative MRI biomarkers using standardized BIDS data. By 
simplifying workflow creation and ensuring reproducibility, QuIDBBIDS lowers barriers for large-scale neuroimaging studies and supports broader clinical 
translation of quantitative MRI methods.

We focus on relaxometry metrics derivable from (multi-echo) gradient-echo and RF-spoiled sequences, including:

- Longitudinal Relaxation (R1, both based on variable flip angle GRE and MP2RAGE acquisitions in combination with transmit field B1 maps)
- Effective Transverse Relaxation (R2*)
- Susceptibility (QSM) and Multi-compartment relaxometry Myelin Water Imaging (MCR-MWI - based on VFA acquisition)

QuIDBBIDS uses a novel declarative framework in which users specify desired (biomarker) outputs, and the software dynamically builds and executes the 
necessary workflow from a library of modular "workers".

QuIDBBIDS is a work-in-progress (WIP) that is being developed at the `Donders Institute <https://www.ru.nl/donders/>`__ of the `Radboud University <https://www.ru.nl>`__.

.. note::

   * All **source code** is hosted at `GitHub <https://github.com/Donders-Institute/quidbbids>`__ and **freely available** under the GPL-3.0-or-later `license <https://spdx.org/licenses/GPL-3.0-or-later.html>`__.
   * The full BIDScoin **documentation** is hosted at `Read the Docs <https://quidbbids.readthedocs.io>`__
   * You are encouraged to **post issues or questions at** `GitHub <https://github.com/Donders-Institute/quidbbids/issues>`__

.. |Tests| image:: https://github.com/Donders-Institute/quidbbids/actions/workflows/tests.yml/badge.svg
   :target: https://github.com/Donders-Institute/quidbbids/actions
   :alt: Matlab test results
.. |GPLv3| image:: https://img.shields.io/badge/License-GPLv3+-blue.svg
   :target: https://www.gnu.org/licenses/gpl-3.0
   :alt: GPL-v3.0 license
.. |RTD| image:: https://readthedocs.org/projects/quidbbids/badge/?version=latest
   :target: https://quidbbids.readthedocs.io/en/latest/?badge=latest
   :alt: Documentation status

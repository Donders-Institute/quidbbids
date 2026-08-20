Workers
=======

This section describes all available workers in QuIDBBIDS. Workers are used to process BIDS
data and make workitems (deliverables) in a peer-to-peer network, orchestrated by the
QuIDBBIDS manager.

B1prepWorker
~~~~~~~~~~~~

Performs B1 field mapping preprocessing to generate regularized flip-angle maps for MRI bias correction.

B1prepWorker processes raw B1 mapping data (acquired with acq-famp and acq-anat protocols) to produce
scaled and regularized transmit field (B1+) maps in degrees. The regularization uses a complex smoothing
approach that preserves tissue boundaries while reducing salt-and-pepper noise.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - 
   - - ``makes``
     - rawTB1map_famp, rawTB1map_anat, TB1map_angle, TB1map_anat
   - - ``usesGPU``
     - false

DWIprepWorker
~~~~~~~~~~~~~

Preprocesses QSIRecon derivative data to generate DWI model parameters for DI-MWI analysis.
DWIprepWorker converts QSIRecon outputs (NODDI and MSMT-CSD models) into standardized workitems representing
fiber/neurite theta (polar angle relative to B0), fiber fraction (ff), and intracellular volume fraction (icvf).
The generated maps are coregistered to MEGRE/VFA space for use in downstream DI-MWI modeling.

Supported methods:
------------------

NODDI - Neurite Orientation Dispersion and Density Imaging
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Requires: QSIRecon workflow with ``--recon-spec amico_noddi`` (produces ``icvf`` and ``direction`` maps)
- Outputs:

  - DWItheta (smallest polar angle between the neurite orientation and the B0 field)
  - DWIff (set to 1 for all voxels, since NODDI models a single neurite population per voxel)
  - DWIicvf (non-modulated, i.e. not corrected for GM/CSF partial voluming effects)

MRtrix3 - Constrained Spherical Deconvolution
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Requires: QSIRecon workflow with any of the ``mrtrix`` reconstruction specifications that produces FOD maps,
  plus installation of MRtrix3 (fod2fixel, fixel2voxel, fixel2peaks), plus the ``NODDI`` reconstruction
  (as described above)
- Outputs:

  - DWItheta (smallest polar angles between fixel directions and the B0 field)
  - DWIff (derived from the Apparent Fiber Density, as a proxy for fiber fraction)
  - DWIicvf (from NODDI, as described above)

References:
^^^^^^^^^^^

- Zhang et al., NeuroImage, 2012 (NODDI)
- Jeurissen et al., 2014 (MRtrix3)

.. note::

   DWIprepWorker does NOT run QSIRecon itself; QSIRecon derivatives must be precomputed.
   QSIPrep/QSIRecon output directories must be configured in the config file or else the downstream DI-MWI model estimations
   will be performed without the diffusion information (which may lead to suboptimal results).

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - syntheticT1
   - - ``makes``
     - derivICVF, derivFDir, derivFOD, DWItheta, DWIicvf, DWIff
   - - ``usesGPU``
     - false

MCRWorker
~~~~~~~~~

Multi-Compartment Relaxometry (MCR) worker for myelin water imaging (MWI) and Diffusion-Informed MWI (DI-MWI) analysis.

MCRWorker implements the MCR framework, combining complex multi-echo GRE data (VFA or MPM acquisitions)
with coregistered B1 transmit field maps to estimate myelin water fraction (MWF) and other quantitative microstructural
parameters. The model simultaneously fits T1, T2*, and proton density across multiple compartments (myelin water,
intra/extra-axonal water, and free water) while accounting for B1 inhomogeneities and field map inhomogeneities.

Theoretical Framework:
----------------------

The MCR model is based on the quantitative framework described in:
Chan et al., NeuroImage, 2020, https://doi.org/10.1016/j.neuroimage.2020.117159

Implementation uses the MWI toolbox: https://github.com/kschan0214/mwi

.. note::

   MCRWorker supports both standard MCR-MWI and DI-MWI variants. When diffusion priors (DWItheta,
   DWIicvf, DWIff) are available from DWIprepWorker, the DI-MWI model incorporates fiber orientation
   and compartment fraction information to improve parameter estimation specificity.

.. tip::

   The ``ortho`` deliverables are just 3 orthogonal slices (to speed up computation) and can be used
   for a fast and shallow quality control.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - ME4Dmag, unwrapped, TB1map_GRE, fieldmap, localfmask, DWItheta, DWIicvf, DWIff
   - - ``makes``
     - MWFmap, FMW_exrate, FitMask, MW_M0map, MW_R2starmap, FW_M0map, FW_T1map, FW_R1map, IAW_R2starmap, MWFmap_ortho, FMW_exrate_ortho, FitMask_ortho, MW_M0map_ortho, MW_R2starmap_ortho, FW_M0map_ortho, FW_T1map_ortho, FW_R1map_ortho, IAW_R2starmap_ortho
   - - ``usesGPU``
     - false

MCR_GPUWorker
~~~~~~~~~~~~~

GPU-accelerated Multi-Compartment Relaxometry (MCR) worker for efficient myelin water imaging (MWI) analysis.

MCR_GPUWorker implements the MCR framework on GPU hardware, combining complex multi-echo GRE data (VFA or MPM)
with coregistered B1 transmit field maps to estimate myelin water fraction (MWF) and other quantitative
microstructural parameters.

Theoretical Framework:
----------------------

The MCR model is based on the quantitative framework described in:
Chan et al., NeuroImage, 2020, https://doi.org/10.1016/j.neuroimage.2020.117159

GPU implementation is provided by the Gacelle toolbox:
https://gacelle.readthedocs.io/en/latest/supported_models/MCRMWI.html

Reference:
----------
Gacelle et al., Imaging Neuroscience 2026 (under review), https://arxiv.org/abs/2511.22094

.. note::

   MCR_GPUWorker provides significant speed improvements over MCRWorker,
   particularly for high-resolution datasets or when processing multiple subjects.
   Requires GPU hardware with CUDA support.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - ME4Dmag, unwrapped, TB1map_GRE, fieldmap, localfmask
   - - ``makes``
     - MWFmap, FMW_exrate, FitMask, MW_M0map, MW_R2starmap, FW_M0map, FW_T1map, FW_R1map, IAW_R2starmap
   - - ``usesGPU``
     - true

MEGREprepWorker
~~~~~~~~~~~~~~~

Performs preprocessing on raw Multi-Echo Gradient Recalled Echo (MEGRE) data for QSM and relaxometry workflows.

MEGREprepWorker prepares MEGRE acquisitions by performing essential preprocessing steps required for
subsequent Quantitative Susceptibility Mapping (QSM) and relaxometry analysis. MEGRE is a GRE sequence
with multiple echo times that allows for both magnitude and phase contrast optimization.

Processing Steps:
-----------------

1. Brain Mask Generation:
   Creates a brain mask for each MEGRE acquisition using the echo-1 magnitude image as input to
   mri_synthstrip (FreeSurfer). Individual masks are combined to produce a minimal output mask
   suitable for QSM processing.

2. Multi-Echo Merging:
   Merges all echo images (magnitude and phase) for each acquisition into 4D NIfTI files.
   This format is required by downstream QSM workflows (e.g., SEPIA) that process multi-echo data.

3. Denoising (Optional):
   Applies (Tensor) MPPCA denoising to the merged 4D files to improve signal-to-noise ratio.
   Configurable via denoising.method ('MPPCA' or 'tMPPCA') and denoising.kernel parameters.

.. note::

   The brain mask generation uses mri_synthstrip which requires FreeSurfer to be installed and configured.
   Denoising is applied in-place to the merged 4D files when enabled.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - 
   - - ``makes``
     - rawMEGRE, brainmask, ME4Dmag, ME4Dphase
   - - ``usesGPU``
     - false

MP2RAGEWorker
~~~~~~~~~~~~~

Magnetization Prepared 2 Rapid Gradient Echo (MP2RAGE) worker for T1 and M0 mapping.

MP2RAGEWorker processes MP2RAGE acquisitions to generate quantitative R1 (1/T1) and magnetization (M0) maps.
MP2RAGE is a 3D T1-weighted imaging sequence that acquires two contrast-weighted images (INV1 and INV2)
at different inversion times, along with a UNIT1 image, enabling robust T1 quantification.

Methods:
--------

This implementation uses a dictionary matching approach that offers significantly improved performance
for long T1 values compared to the original implementation. The method is described in:

Chan et al., Imaging Neuroscience, 2025, https://doi.org/10.1162/imag_a_00456 (supplemental material)

Original MP2RAGE T1 mapping method:
Marques et al., PLoS ONE, 2013, https://doi.org/10.1371/journal.pone.0069294

The dictionary matching code is based on: https://github.com/JosePMarques/MP2RAGE-related-scripts/

.. note::

   Accurate T1 estimation requires careful configuration of ``NumberShots`` (number of slices in
   the inversion segment) and ``EchoSpacing`` (TR of the GRE readout). Incorrect values may lead
   to systematic biases in T1 estimates, particularly at high field strengths.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - TB1map_anat, TB1map_angle
   - - ``makes``
     - rawUNIT1, rawINV1, rawINV2, R1map, M0map, MP2RAGE_T1w
   - - ``usesGPU``
     - false

QSMWorker
~~~~~~~~~

Quantitative Susceptibility Mapping (QSM) and R2* relaxometry worker using the SEPIA toolbox.

QSMWorker performs QSM reconstruction and R2* mapping from multi-echo GRE magnitude and phase data.
QSM is a post-processing technique that converts MRI phase data into quantitative susceptibility maps,
enabling the study of tissue magnetic properties such as iron content, calcium, and myelin.

The SEPIA toolbox (Susceptibility and Phase Imaging Application) provides a comprehensive pipeline
for QSM reconstruction, including phase unwrapping, background field removal, and susceptibility inversion.

Processing Steps:
-----------------

1. Phase Unwrapping: Resolves phase wraps in the multi-echo phase data
2. Background Field Removal: Separates local tissue phase from background field contributions
3. Susceptibility Inversion: Converts local field maps to susceptibility maps
4. R2* Mapping: Computes R2* relaxation rate maps from multi-echo magnitude decay

.. note::

   SEPIA has its own working directory structure. QSMWorker temporarily switches to the
   SEPIA directory for processing and renames output files to ensure BIDS compatibility.
   The SEPIA toolbox must be installed and configured.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - ME4Dmag, ME4Dphase, brainmask
   - - ``makes``
     - R2starmap, T2starmap, S0map, Chimap, fieldmap, unwrapped, localfmask
   - - ``usesGPU``
     - false

R1R2sWorker
~~~~~~~~~~~

Joint R1 and R2* mapping worker using GPU-accelerated estimation for multi-echo GRE data.

R1R2sWorker generates quantitative R1 (1/T1) and R2* (1/T2*) maps from Variable Flip Angle (VFA) and
Multi-Parameter Mapping (MPM) multi-echo GRE data using a joint estimation model. The simultaneous fitting
of R1 and R2* parameters improves accuracy by accounting for the interdependence of these relaxation
parameters, particularly important at high field strengths where both T1 and T2* effects are significant.

Theoretical Framework:
----------------------

The joint R1-R2* estimation is implemented using the Gacelle toolbox:
Gacelle, K. S. Chan et al., Imaging Neuroscience 2026

Documentation: https://gacelle.readthedocs.io/en/latest/supported_models/JointR1R2star.html

Methods:
--------

- Loads coregistered multi-echo GRE magnitude data, B1 transmit field maps, and brain masks
- Performs joint estimation of R1 and R2* using gpuJointR1R2starMapping
- Accounts for B1 inhomogeneities in the fitting process

.. note::

   The joint estimation approach is particularly advantageous when T1 and T2* are correlated,
   such as in white matter where myelin water has distinct relaxation properties.
   Requires GPU hardware with CUDA support.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - ME4Dmag, TB1map_GRE, brainmask
   - - ``makes``
     - R2starmap, M0map, R1map
   - - ``usesGPU``
     - true

SCRWorker
~~~~~~~~~

Single Compartment Relaxometry (SCR) worker for combined relaxometry and susceptibility analysis.

SCRWorker combines separately computed Quantitative Susceptibility Mapping (QSM) outputs with
relaxometry data to generate consolidated parameter maps. SCR provides a simplified model that
assumes a single tissue compartment, suitable for applications where multi-compartment modeling
is not required or when computational efficiency is prioritized.

Methods:
--------

1. R2* and Chi Map Averaging:
   Computes weighted means of R2* and susceptibility (Chi) maps across different flip angles.
   The weighting uses S0^2 to emphasize voxels with higher signal intensity.

2. R1 and M0 Mapping:
   Estimates R1 (1/T1) and M0 (proton density) maps using the DESPOT1 (Driven Equilibrium Single
   Pulse Observation of T1) method with S0 estimates from QSM processing.
   The current implementation assumes a constant TR across all flip angles.

.. note::

   The SCR model is appropriate for tissues with relatively homogeneous microstructure or when
   the primary goal is to obtain average parameter values rather than compartment-specific estimates.
   For myelin water imaging, consider using MCRWorker or MCR_GPUWorker instead.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - S0map, R2starmap, Chimap, localfmask, TB1map_GRE
   - - ``makes``
     - R1map_S0, M0map_S0, meanR2starmap, meanChimap
   - - ``usesGPU``
     - false

VFAprepWorker
~~~~~~~~~~~~~

Variable Flip Angle (VFA) and Multi-Parameter Mapping (MPM) preprocessing worker for multi-echo GRE data.

VFAprepWorker performs comprehensive preprocessing of VFA and MPM acquisitions to prepare data for
downstream QSM, SCR, and MCR workflows. VFA/MPM are multi-echo GRE sequences acquired at different
flip angles that enable quantitative parameter mapping and improve SNR through signal averaging.

Processing Steps:
-----------------

0. Denoising (Optional):
   Applies MPPCA or tMPPCA denoising to raw input data before further processing.
   Configurable via denoising.method and denoising.kernel parameters.

1. Synthetic T1 and M0 Generation:
   Passes coregistered echo-1 magnitude images to DESPOT1 to compute T1-weighted synthetic
   reference images and S0 (proton density) maps for each flip angle. These synthetic images
   serve as targets for coregistration in the common GRE space.

2. Coregistration:
   Coregisters all VFA/MPM images to their corresponding synthetic T1 targets using echo-1 magnitude
   images as reference. B1 transmit field maps are also coregistered to the M0 maps, which share
   the same common GRE space.

3. Brain Mask Generation:
   Creates a brain mask for each flip angle using the echo-1 magnitude image. Individual masks
   are combined (via logical AND) to produce a minimal output mask suitable for SEPIA QSM processing.

4. Multi-Echo Merging:
   Merges all echo images for each flip angle into 4D NIfTI files (separately for magnitude and phase).
   This format is required by downstream QSM, SCR, and MCR workflows.

.. note::

   If only VFA data is available (without MPM), steps 1 and 2 (synthetic T1 generation and coregistration)
   are skipped. VFAprepWorker automatically detects available data types from the BIDS configuration.
   Processing is performed independently for each acquisition, run, and flip angle combination.

Properties
----------

.. list-table::
   :widths: 25 75

   - - ``needs``
     - TB1map_anat, TB1map_angle
   - - ``makes``
     - rawMEVFA, syntheticT1, M0map_echo1, TB1map_GRE, TB1anat_GRE, brainmask, ME4Dmag, ME4Dphase
   - - ``usesGPU``
     - false


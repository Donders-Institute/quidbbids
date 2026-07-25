Workers
=======

This section describes all available workers in QuIDBBIDS.

B1prepWorker
~~~~~~~~~~~~

I am a modest worker that fabricates regularized flip-angle maps in degrees (ready for the big B1-correction party!)

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - 
   - - ``makes``
     - rawTB1map_famp, rawTB1map_anat, TB1map_angle, TB1map_anat
   - - ``usesGPU``
     - false

DWIprepWorker
~~~~~~~~~~~~~

Preprocessing of QSIRecon derivative data to generate DWI model parameters for DI-MWI analysis.
This worker converts QSIRecon outputs (NODDI and MSMT-CSD models) into standardized workitems representing
fiber/neurite theta (polar angle relative to B0), fiber fraction (ff), and intracellular volume fraction (icvf).
The generated maps are coregistered to MEGRE/VFA space for use in downstream DI-MWI modeling.

Supported methods:
------------------

NODDI - Neurite Orientation Dispersion and Density Imaging (Zhang et al., 2012)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Requires: QSIRecon workflow with ``--recon-spec amico_noddi`` (produces ``icvf`` and ``direction`` maps)
- Outputs:

  - DWI_theta (smallest polar angle between the neurite orientation and the B0 field)
  - DWI_ff (set to 1 for all voxels, since NODDI models a single neurite population per voxel)
  - DWI_icvf (non-modulated, i.e. not corrected for GM/CSF partial voluming effects)

MRtrix3 - Constrained Spherical Deconvolution (Jeurissen et al., 2014)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Requires: QSIRecon workflow with any of the ``mrtrix`` reconstruction specifications that produces FOD maps,
  plus installation of MRtrix3 (fod2fixel, fixel2voxel, fixel2peaks), plus the ``NODDI`` reconstruction
  (as described above)
- Outputs:

  - DWI_theta (smallest polar angles between fixel directions and the B0 field)
  - DWI_ff (derived from the Apparent Fiber Density, as a proxy for fiber fraction)
  - DWI_icvf (from NODDI, as described above)

.. note::

   This worker does NOT run QSIRecon itself; QSIRecon derivatives must be precomputed.
   QSIPrep/QSIRecon output directories must be configured in the config file or else the downstream MW model estimations
   will be performed without the diffusion information (which may lead to suboptimal results).

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - syntheticT1
   - - ``makes``
     - DWI_theta, DWI_icvf, DWI_ff
   - - ``usesGPU``
     - false

MCRWorker
~~~~~~~~~

Multi-compartment relaxometry worker, it combines complex multi-echo data (labeled either _MPM or _VFA) with coregistered
B1 relative maps to compute myelin water fraction maps

Additionally it requires:
-------------------------

- a field map has already been computed per acquisition in order to reduce the search space of the minimisation problem
- a common brain mask exists for the various acquisitions

The theoretical framework is described in Chan et al., NeuroImage, 2020, https://doi.org/10.1016/j.neuroimage.2020.117159
Using as backend the code present on the repository https://github.com/kschan0214/mwi

Methods:
--------

- reads data
- computes initial phase of each acquisition
- (optional) extracts 3 orthogonal slices to speed up computation
- runs fitting process using mwi_3cx_2R1R2s_dimwi - there are various configuration options MCRWorker.algoPara
- saves relevant output

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - ME4Dmag, unwrapped, TB1map_GRE, fieldmap, localfmask, DWI_theta, DWI_icvf, DWI_ff
   - - ``makes``
     - MWFmap, FMW_exrate, FitMask, MW_M0map, MW_R2starmap, FW_M0map, FW_T1map, FW_R1map, IAW_R2starmap, MWFmap_ortho, FMW_exrate_ortho, FitMask_ortho, MW_M0map_ortho, MW_R2starmap_ortho, FW_M0map_ortho, FW_T1map_ortho, FW_R1map_ortho, IAW_R2starmap_ortho
   - - ``usesGPU``
     - false

MCR_GPUWorker
~~~~~~~~~~~~~

Multi-compartment relaxometry worker, it combines complex multi-echo data (labeled either _MPM or _VFA) with coregistered B1 relative maps to compute myelin water fraction maps

Additionally it requires:
-------------------------

- a field map has already been computed per acquisition in order to reduce the search space of the minimisation problem
- a common brain mask exists for the various acquisitions

The theoretical framework is described in Chan et al., NeuroImage, 2020, https://doi.org/10.1016/j.neuroimage.2020.117159
Using as backend the code present on the repository https://gacelle.readthedocs.io/en/latest/supported_models/MCRMWI.html

Methods:
--------

- reads data
- computes initial phase of each acquisition
- runs fitting process using gpuMCRMWI - there are various configuration options MCR_GPUWorker.fitting
- saves relevant output

Gacelle, et al., Imaging Neuroscience 2026 under review https://arxiv.org/abs/2511.22094

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - ME4Dmag, unwrapped, TB1map_GRE, fieldmap, localfmask
   - - ``makes``
     - MWFmap, FMW_exrate, FitMask, MW_M0map, MW_R2starmap, FW_M0map, FW_T1map, FW_R1map, IAW_R2starmap
   - - ``usesGPU``
     - true

MEGREprepWorker
~~~~~~~~~~~~~~~

I do the following pre-processing work for you:

- Create a brain mask for each MEGRE acquisition using the echo-1_mag image.
- Merge all echoes into a 4D file (for running the QSM workflows)
- Denoise using (Tensor) MPPCA the merged 4D file (optional) - this is configurable
  with denoising.method & denoising.kernel

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - 
   - - ``makes``
     - rawMEGRE, brainmask, ME4Dmag, ME4Dphase
   - - ``usesGPU``
     - false

MP2RAGEWorker
~~~~~~~~~~~~~

I'm an MP2RAGE worker and create M0 and R1 maps, but only if you have MP2RAGE and B1 map data!
Computations are based on a dictionary matching approach described in the supplemental material
of the paper Chan et al, Imaging Neuroscience, 2025 https://doi.org/10.1162/imag_a_00456.

This method, when compared to the original implementation described by Marques et al, PLOSone, 2013
https://doi.org/10.1371/journal.pone.0069294 has significantly better performance for long T1 values

.. note::

   Be careful at defining the configuration parameters ``NumberShots`` and (to a smaller extent) ``EchoSpacing``

The code is based on: https://github.com/JosePMarques/MP2RAGE-related-scripts/

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - TB1map_anat, TB1map_angle
   - - ``makes``
     - rawUNIT1, rawINV1, rawINV2, R1map, M0map, MP2RAGE_T1w
   - - ``usesGPU``
     - false

QSMWorker
~~~~~~~~~

I am your SEPIA expert that can make shiny QSM and R2-star images for you

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - ME4Dmag, ME4Dphase, brainmask
   - - ``makes``
     - R2starmap, T2starmap, S0map, Chimap, fieldmap, unwrapped, localfmask
   - - ``usesGPU``
     - false

R1R2sWorker
~~~~~~~~~~~

This worker generates precise R1- and R2-starmaps from MPM and VFA multiecho data using one single model

Methods:
--------

- loads coregistered Multiecho GRE magnitude, relative B1 maps as well as a brain mask (for memory purposes)
- uses Gacelle, K-s Chan et al., Imaging Neuroscience 2026 for simultaneous R1 and R2-star mapping from
  variable flip angle multi-echo GRE data (VFA or MPM)

There are various configuration options that are referred to in https://gacelle.readthedocs.io/en/latest/supported_models/JointR1R2star.html

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - ME4Dmag, TB1map_GRE, brainmask
   - - ``makes``
     - R2starmap, M0map, R1map
   - - ``usesGPU``
     - true

SCRWorker
~~~~~~~~~

Single Compartment Relaxometry worker, this worker combines the separately computed S0, Chi and R2* maps into a single S0, R1 and R2* map 

Methods:
--------
- Compute weighted means of the R2-star & Chi-maps over the different flip-angles
- Compute R1- & M0-maps based on despot1 with S0 estimates (current implementation assumes constant TR for the various flip angles)

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - S0map, R2starmap, Chimap, localfmask, TB1map_GRE
   - - ``makes``
     - R1map_S0, M0map_S0, meanR2starmap, meanChimap
   - - ``usesGPU``
     - false

VFAprepWorker
~~~~~~~~~~~~~

I am a working class hero that will happily do the following pre-processing work for you:

- Pass coregistered echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
- Coregister all VFA/MPM images to each T1w-like target image (using echo-1_mag),
  coregister the B1 images as well to the M0 (which is also in the common GRE space)
- Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
  to produce a minimal output mask (for SEPIA)
- Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows)

If only VFA data is available, then steps 1 and 2 are skipped

Properties
----------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   - - Property
     - Value
   - - ``needs``
     - TB1map_anat, TB1map_angle
   - - ``makes``
     - rawMEVFA, syntheticT1, M0map_echo1, TB1map_GRE, TB1anat_GRE, brainmask, ME4Dmag, ME4Dphase
   - - ``usesGPU``
     - false


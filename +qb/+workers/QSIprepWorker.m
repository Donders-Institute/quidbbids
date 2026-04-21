classdef QSIprepWorker < qb.workers.Worker
%QSIPREPWORKER Converts QSIRecon outputs (NODDI and MSMT-CSD) into QSI workitems for DI-MWI analysis
% See also: qb.workers.MCRWorker, qb.workers.Worker, qb.QuIDBBIDS


properties (Constant)
    description = ["Preprocessing of QSIRecon derivative data to generate QSI model parameters for DI-MWI analysis";
                   "This worker converts QSIRecon outputs (NODDI and MSMT-CSD models) into standardized QSI workitems representing";
                   "fiber/neurite theta (polar angle relative to B0), fiber fraction (ff), and intracellular volume fraction (icvf).";
                   "The generated maps are coregistered to MEGRE/VFA space for use in downstream DI-MWI modeling.";
                   "";
                   "Supported methods:";
                   "";
                   "NODDI - Neurite Orientation Dispersion and Density Imaging (Zhang et al., 2012)";
                   "  Requires: QSIRecon workflow with `--recon-spec amico_noddi` (produces 'icvf' and 'direction' maps)";
                   "  Outputs:  QSI_theta (smallest polar angle between the neurite orientation and the B0 field)";
                   "            QSI_ff (set to 1 for all voxels, since NODDI models a single neurite population per voxel)";
                   "            QSI_icvf (modulated, i.e. the product of NODDI icvf and tissue fraction for compatibility with MCR model)";
                   "";
                   "MRtrix - Constrained Spherical Deconvolution (Jeurissen et al., 2014)";
                   "  Requires: QSIRecon workflow with any of the `mrtrix` reconstruction specifications that produces FOD maps,";
                   "            plus installation of MRtrix3 (fod2fixel and fixel2voxel), plus the `NODDI` reconstruction (as described above)";
                   "  Outputs:  QSI_theta (smallest polar angles between fixel directions and B0 field)";
                   "            QSI_ff (Apparent Fiber Density as a proxy for fiber fraction)";
                   "            QSI_icvf (modulated, i.e. the product of NODDI icvf and tissue fraction for compatibility with MCR model)";
                   "";
                   "Important notes:";
                   "  - This worker does NOT run QSIRecon itself; QSIRecon derivatives must be precomputed";
                   "  - QSIPrep/QSIRecon output directories must be configured in the config file or else the downstream MW model estimations";
                   "    will be performed without the diffusion information (which may lead to suboptimal results)."]  % Description of the work that is done
    needs       = "syntheticT1"                % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.derivNODDI_icvf = struct(modality='dwi', model='noddi', param='icvf', desc='modulated', suffix='dwimap');
        obj.bidsfilter.derivNODDI_fdir = setfields(obj.bidsfilter.derivNODDI_icvf, param='direction');
        obj.bidsfilter.QSI_theta       = setfields(obj.bidsfilter.derivNODDI_icvf, param='theta', space='withinGRE');
        obj.bidsfilter.QSI_ff          = setfields(obj.bidsfilter.QSI_theta, param='fiberfraction');
        obj.bidsfilter.QSI_icvf        = setfields(obj.bidsfilter.derivNODDI_icvf, space=obj.bidsfilter.QSI_theta.space);
    end
    
end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        function qsidir = get_qsidir(qsidir)
            if isempty(qsidir)
                return
            elseif isempty(fileparts(qsidir))
                qsidir = fullfile(obj.BIDS.pth, 'derivatives', qsidir);
            end
            if ~isfolder(qsidir)
                obj.logger.warning('"%s" does not exist or is not a folder', qsidir)
                qsidir = '';
            end
        end

        import qb.utils.spm_vol

        % Get the QSIPrep and QSIRecon directories
        qsiprepdir  = get_qsidir(obj.config.QSIprepWorker.QsiprepDir);
        qsirecondir = get_qsidir(obj.config.QSIprepWorker.QsireconDir);
        if isempty(qsiprepdir) || isempty(qsirecondir)
            return
        end

        % Get the QSIrecon derivative images
        BIDSD = obj.BIDS_ses(fullfile(qsirecondir,'derivatives',['QSIRecon-' obj.config.QSIprepWorker.Model]));
        icvf  = obj.query_ses(BIDSD, 'data', obj.bidsfilter.derivNODDI_icvf);
        fdir  = obj.query_ses(BIDSD, 'data', obj.bidsfilter.derivNODDI_fdir);
        if length(icvf) ~= length(fdir)
            obj.logger.warning('Unexpected number of QSIRecon-files found: icvf=%d vs fdir=%d', length(icvf), length(fdir))
        end
        if isempty(icvf)
            obj.logger.verbose('No QSIRecon files found in: %s..', fullfile(qsirecondir, obj.sub_ses()))
            return
        end

        % Coregister the icvf and fdir maps to the "withinGRE" space (i.e. the space of the GRE images that are used in the DI-MWI model)
        BIDSD = obj.BIDS_ses(qsiprepdir, index_derivatives=true);
        T1src = bids.query(BIDSD, 'data', struct(sub=obj.sub, modality='anat', space='ACPC', desc='preproc', suffix='T1w'));
        if isempty(T1src)
            obj.logger.error('No QSIRecon T1w reference image found for: %s. Cannot coregister the "ACPC" files to the "withinGRE" space.', fullfile(qsiprepdir, obj.sub_ses()))
            return
        elseif length(T1src) > 1
            obj.logger.info('More than one T1w "ACPC" reference image found, using the first image: %s', T1src{1})
        end
        T1tgt = obj.ask_team('syntheticT1');
        if isempty(T1tgt)
            T1tgt = obj.query_ses(obj.BIDS, 'data', struct(modality='anat', suffix='T1w'));
        end
        if length(T1tgt) > 1
            T1tgt = T1tgt(round(length(T1tgt)/2));      % If there are multiple T1w "withinGRE" images (flips), use the middle one
            obj.logger.info('More than one T1w "withinGRE" reference image found, using: %s', T1tgt{1})
        end
        Vtgt = spm_vol(T1tgt{1});
        Vsrc = spm_vol(T1src{1});
        x    = spm_coreg(Vtgt, Vsrc, struct(cost_fun='nmi'));

        % Loop over the found icvf maps (and corresponding fdir maps) to compute the QSI_theta, QSI_ff and QSI_icvf workitems
        for n = 1:length(icvf)

            % Load the icvf and fdir data
            Vicvf = spm_vol(icvf{n});
            FDIR  = spm_read_vols(spm_vol(fdir{n}));                % The fiber directions in world coordinates (size: [X Y Z 3])

            % Compute the (smallest) polar angle (theta) between the fiber direction and the B0 field using: θ = acos( |f⋅b| / (|f| |b|) )
            % b0dir = repmat(shiftdim([0; 0; 1], -3), Vicvf.dim);   % B0-field in world coordinates (assuming the B0 field is always along the z-axis in the subject's native space)
            % theta = acos(abs(dot(FDIR, b0dir, 4)) ./ (vecnorm(FDIR,2,4) .* vecnorm(b0dir,2,4))); % The absolute value is taken to make it agnostic to the sign of the fiber direction, i.e. within [0, pi/2].
            b0dir = [0; 0; 1];                                      % Compute the above two lines more efficiently, i.e. without broadcasting b0dir
            theta = acos(abs(tensorprod(FDIR, b0dir, 4, 1)) ./ (vecnorm(FDIR,2,4) * norm(b0dir)));

            % Rotate the data to the "withinGRE" space (using trilinear interpolation)
            T = Vicvf.mat \ spm_matrix(x) * Vtgt.mat;               % Transformation from voxel coordinates in Vtgt to voxel coordinates in Vicvf
            for z = Vtgt.dim(3):-1:1
                ICVF(:,:,z) = spm_slice_vol(Vicvf, T * spm_matrix([0 0 z]), Vtgt.dim(1:2), 1);
            end
            Vicvf.private     = struct();       % Clear private nifti object to allow overriding the memory map, i.e. re/misuse Vicvf to save the rotated theta map
            Vicvf.private.dat = theta;          % Override the memory map
            Vicvf.dat         = theta;          % Make sure that for gz-files ".dat" is also overridden
            theta             = NaN(Vtgt.dim);  % Source theta is now stored in the memory map of Vicvf
            for z = 1:Vtgt.dim(3)
                theta(:,:,z) = spm_slice_vol(Vicvf, T * spm_matrix([0 0 z]), Vtgt.dim(1:2), 1);
            end

            % Save the QSI_theta, QSI_icvf and QSI_ff images & json files
            write_vol_qsi(fdir{n}, obj.bidsfilter.QSI_theta, theta, 'polar angle (theta)')
            write_vol_qsi(icvf{n}, obj.bidsfilter.QSI_icvf, ICVF, 'volume fraction (icvf)')
            write_vol_qsi(icvf{n}, obj.bidsfilter.QSI_ff, true(Vtgt.dim), 'fiber fraction (ff)')

        end

        function write_vol_qsi(fname, bfilter, data, type)
            bfile = obj.bfile_set(fname, bfilter);
            obj.logger.info('-> Saving %s data to: %s', type, bfile.filename)
            qb.utils.write_vol(Vtgt, data, bfile);
        end
    end

end

end

classdef DWIprepWorker < qb.workers.Worker
%DWIPREPWORKER Converts QSIRecon outputs (NODDI and MSMT-CSD) into workitems needed for DI-MWI analysis
% See also: qb.workers.MCRWorker, qb.workers.Worker, qb.QuIDBBIDS


properties (Constant)
    description = ["Preprocessing of QSIRecon derivative data to generate DWI model parameters for DI-MWI analysis";
                   "This worker converts QSIRecon outputs (NODDI and MSMT-CSD models) into standardized workitems representing";
                   "fiber/neurite theta (polar angle relative to B0), fiber fraction (ff), and intracellular volume fraction (icvf).";
                   "The generated maps are coregistered to MEGRE/VFA space for use in downstream DI-MWI modeling.";
                   "";
                   "Supported methods:";
                   "";
                   "NODDI - Neurite Orientation Dispersion and Density Imaging (Zhang et al., 2012)";
                   "  Requires: QSIRecon workflow with `--recon-spec amico_noddi` (produces 'icvf' and 'direction' maps)";
                   "  Outputs:  DWI_theta (smallest polar angle between the neurite orientation and the B0 field)";
                   "            DWI_ff (set to 1 for all voxels, since NODDI models a single neurite population per voxel)";
                   "            DWI_icvf (non-modulated, i.e. not corrected for GM/CSF partial voluming effects)";
                   "";
                   "MRtrix3 - Constrained Spherical Deconvolution (Jeurissen et al., 2014)";
                   "  Requires: QSIRecon workflow with any of the `mrtrix` reconstruction specifications that produces FOD maps,";
                   "            plus installation of MRtrix3 (fod2fixel), plus the `NODDI` reconstruction (as described above)";
                   "  Outputs:  DWI_theta (smallest polar angles between fixel directions and the B0 field)";
                   "            DWI_ff (derived from the Apparent Fiber Density, as a proxy for fiber fraction)";
                   "            DWI_icvf (from NODDI, as described above)";
                   "";
                   "Important notes:";
                   "  - This worker does NOT run QSIRecon itself; QSIRecon derivatives must be precomputed";
                   "  - QSIPrep/QSIRecon output directories must be configured in the config file or else the downstream MW model estimations";
                   "    will be performed without the diffusion information (which may lead to suboptimal results)."]  % Description of the work that is done
    needs       = "syntheticT1"                % List of workitems (excluding derivative data) the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.DWI_theta = struct(modality='dwi', space='withinGRE', param='theta', suffix='dwimap');
        obj.bidsfilter.DWI_icvf  = setfields(obj.bidsfilter.DWI_theta, param='icvf');
        obj.bidsfilter.DWI_ff    = setfields(obj.bidsfilter.DWI_theta, param='fiberfraction');
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
            % Return the full path to the QSIprep/QSIRecon derivatives directory, or an empty string if it does not exist
            if isempty(qsidir)
                qsidir = '';
                return
            elseif isempty(fileparts(qsidir))
                if strcmp(qsidir, 'qsiprep')
                    qsidir = fullfile(obj.BIDS.pth, 'derivatives', 'qsiprep');
                else
                    qsidir = fullfile(obj.BIDS.pth, 'derivatives', 'qsirecon', 'derivatives', qsidir);
                end
            end
            if ~isfolder(qsidir)
                obj.logger.verbose('QSIprep/QSIRecon derivatives directory not found: %s', qsidir)
                qsidir = '';
            end
        end

        import qb.utils.spm_vol

        % Get the QSIPrep and QSIRecon directories and get the QSI BIDS layouts
        qsiprepdir = get_qsidir(obj.config.DWIprepWorker.QSIprepDir);
        NODDIdir   = get_qsidir(obj.config.DWIprepWorker.NODDIDir);
        MRtrixdir  = get_qsidir(obj.config.DWIprepWorker.MRtrix3Dir);
        if isempty(qsiprepdir) || isempty(NODDIdir)
            obj.logger.warning('One or more of the QSIPrep/QSIRecon directories are missing. Cannot generate DWI workitems for DI-MWI analysis.')
            return
        end
        QSIprep = obj.BIDS_ses(qsiprepdir);
        NODDI   = obj.BIDS_ses(NODDIdir);
        if strcmp(obj.config.DWIprepWorker.Model, 'MRtrix3')
            MRtrix = obj.BIDS_ses(MRtrixdir);
        end

        % Compute the DWI_theta, DWI_ff and DWI_icvf workitems
        for acq = obj.query_ses(NODDI, 'acquisitions')
            for run = str2double(obj.query_ses(NODDI, 'runs'))
                
                % Query the NODDI icvf and fdir files for the current acquisition and run
                icvf = obj.query_ses(NODDI, 'data', obj.config.DWIprepWorker.BFilterICVF, acq=char(acq), run=char(run));
                fdir = obj.query_ses(NODDI, 'data', obj.config.DWIprepWorker.BFilterFDir, acq=char(acq), run=char(run));
                if isempty(icvf)
                    obj.logger.verbose('No QSIRecon acq-%s_run-%s icvf-files found in: %s..', char(acq), char(run), fullfile(NODDIdir, obj.sub_ses()))
                    continue
                end
                if length(icvf) ~= 1 || length(fdir) > 1
                    obj.logger.warning('Unexpected number of QSIRecon-files found: icvf=%d vs fdir=%d', length(icvf), length(fdir))
                end
                Vicvf = spm_vol(icvf{1});

                % Estimate the coregistration from the qsiprep space to the "withinGRE" space (i.e. the space of the GRE images that are used in the DI-MWI model)
                if ~exist('T', 'var')
                    T1src = obj.query_ses(QSIprep, 'data', struct(sub=obj.sub, modality='anat', space='ACPC', desc='preproc', suffix='T1w'));
                    if isempty(T1src)
                        obj.logger.error('No QSIRecon T1w reference image found for: %s. Cannot coregister the "ACPC" files to the "withinGRE" space.', fullfile(qsiprepdir, obj.sub_ses()))
                        return
                    elseif length(T1src) > 1
                        obj.logger.warning('More than one T1w "ACPC" reference image found, using the first image: %s', T1src{1})
                    end
                    T1tgt = obj.ask_team('syntheticT1');
                    if isempty(T1tgt)
                        T1tgt = obj.query_ses(obj.BIDS, 'data', struct(modality='anat', suffix='T1w'));
                    end
                    if length(T1tgt) > 1
                        T1tgt = T1tgt(round(length(T1tgt)/2));      % If there are multiple T1w "withinGRE" images (flips), use the middle one
                        obj.logger.warning('More than one T1w "withinGRE" reference image found, using: %s', T1tgt{1})
                    end
                    Vtgt = spm_vol(T1tgt{1});
                    Vsrc = spm_vol(T1src{1});
                    x    = spm_coreg(Vtgt, Vsrc, struct(cost_fun='nmi'));
                    T    = Vicvf.mat \ spm_matrix(x) * Vtgt.mat;    % Transformation from voxel coordinates in Vtgt to voxel coordinates in Vicvf (the dwi space)
                end

                % Load the qsirecon data
                switch obj.config.DWIprepWorker.Model
                    case 'NODDI'
                        AFDs  = ones(Vtgt.dim);                     % NODDI models a single neurite population per voxel, so the fiber fraction is set to 1 for all voxels
                        FDIRs = spm_read_vols(spm_vol(fdir{1}));    % The fiber directions in world coordinates (size: [X Y Z 3])
                        FDIRs = permute(FDIRs, [1 2 3 5 4]);        % Reshape to [X Y Z 1 3], i.e. to the same format as the MRtrix3 fixel directions (FDIRs)

                    case 'MRtrix3'
                        % Query MRtrix FOD from QSIRecon derivatives
                        fod = obj.query_ses(MRtrix, 'data', obj.config.DWIprepWorker.BFilterFOD, acq=char(acq), run=char(run));
                        if length(fod) ~= 1
                            obj.logger.error('Expected one MRtrix3 FOD file for acq-%s_run-%s but found %d', char(acq), char(run), length(fod));
                            continue
                        end
                        
                        % Execute MRtrix to compute fixels from the FOD
                        fixels = fullfile(fileparts(fod{1}), 'fixels');
                        if isfolder(fixels)
                            rmdir(fixels, 's')
                        end
                        nrfixels = obj.config.DWIprepWorker.NrFixels;
                        obj.run_command(sprintf('%s; fod2fixel %s %s -maxnum %d -nii -afd afd.nii', obj.config.DWIprepWorker.MRtrixEnv, fod{1}, fixels, nrfixels));
                        
                        % Load peak directions and AFDs, and reorganize the fixel data into 4D volumes where the 4th dimension corresponds to the fixel number (1 to nrfixels)
                        index = spm_read_vols(spm_vol(fullfile(fixels, 'index.nii')));          % Dimensions: [x y z 2] where the 4th dimension contains [numfixelsvox fixelindex]
                        AFDs  = zeros([size(index(:,:,:,1)) nrfixels]);                         % Dimensions: [x y z nrfixels]
                        FDIRs = zeros([size(index(:,:,:,1)) nrfixels 3]);                       % Dimensions: [x y z nrfixels 3]
                        AFD_  = spm_read_vols(spm_vol(fullfile(fixels, 'afd.nii')));            % Dimensions: [n 1]
                        FDIR_ = spm_read_vols(spm_vol(fullfile(fixels, 'directions.nii')));     % Dimensions: [n 3]
                        [x, y, z] = ind2sub(size(index(:,:,:,1)), find(index(:,:,:,1)));        % Get the voxel coordinates of all non-empty fixels
                        for i = 1:length(x)
                            fnum = index(x(i), y(i), z(i), 1);                                  % Get the number of fixels in the current voxel
                            fidx = index(x(i), y(i), z(i), 2);                                  % Get the fixel index for the current voxel
                            for n = 1:fnum
                                AFDs(x(i), y(i), z(i), n)     = AFD_(fidx + n - 1);             % Store the AFD for the current fixel
                                FDIRs(x(i), y(i), z(i), n, :) = FDIR_(fidx + n - 1, :);         % Store the fiber direction for the current fixel
                            end
                        end
                        
                    otherwise
                        obj.logger.error('Unsupported QSIRecon method specified in config: %s. Supported methods are: "NODDI" and "MRtrix3".', obj.config.DWIprepWorker.Model)
                        return
                end

                % Compute the DWI_icvf, DWI_theta and DWI_ff maps in the "withinGRE" space
                for z = Vtgt.dim(3):-1:1
                    ICVF(:,:,z) = spm_slice_vol(Vicvf, T * spm_matrix([0 0 z]), Vtgt.dim(1:2), 1);  % Rotate and reslice the data using trilinear interpolation
                end
                for f = size(AFDs,4): -1: 1
                    FDIR = FDIRs(:,:,:,f,:);            % The fiber direction in world coordinates (size: [X Y Z 1 3])
                    AFD  = AFDs(:,:,:,f);               % The fiber fraction (size: [X Y Z])

                    % Compute the (smallest) polar angle (theta) between the fiber direction and the B0 field using: θ = acos( |f⋅b| / (|f| |b|) )
                    % b0dir = repmat(shiftdim([0; 0; 1], -4), Vicvf.dim);   % B0-field in world coordinates (assuming the B0 field is always along the z-axis in the subject's native space)
                    % theta = acos(abs(dot(FDIR, b0dir, 5)) ./ (vecnorm(FDIR,2,5) .* vecnorm(b0dir,2,5))); % The absolute value is taken to make it agnostic to the sign of the fiber direction, i.e. within [0, pi/2].
                    b0dir = [0; 0; 1];                                      % Compute the above two lines more efficiently, i.e. without broadcasting b0dir
                    theta = acos(abs(tensorprod(FDIR, b0dir, 5, 1)) ./ (vecnorm(FDIR,2,5) * norm(b0dir)));

                    Vicvf.private      = struct();      % Clear private nifti object to allow overriding the memory map, i.e. re/misuse Vicvf to save the rotated theta map
                    Vicvf.private.dat  = theta;         % Override the memory map
                    Vicvf.dat          = theta;         % Make sure that for gz-files ".dat" is also overridden -- the source theta is now stored in the memory map of Vicvf
                    for z = Vtgt.dim(3):-1:1
                        THETA(:,:,z,f) = spm_slice_vol(Vicvf, T * spm_matrix([0 0 z]), Vtgt.dim(1:2), 1);
                    end
                    Vicvf.private.dat  = AFD;           % Override the memory map again for saving the rotated fiber fraction map
                    Vicvf.dat          = AFD;           % Make sure that for gz-files ".dat" is also overridden -- the source AFDs is now stored in the memory map of Vicvf
                    for z = Vtgt.dim(3):-1:1
                        FFRAC(:,:,z,f) = spm_slice_vol(Vicvf, T * spm_matrix([0 0 z]), Vtgt.dim(1:2), 1);
                    end
                end

                % Save the DWI_icvf, DWI_theta and DWI_ff images & json files
                write_vol_qsi(icvf{1}, obj.bidsfilter.DWI_icvf, ICVF, 'volume fraction (icvf)')
                write_vol_qsi(fdir{1}, obj.bidsfilter.DWI_theta, THETA, 'polar angle (theta)')
                write_vol_qsi(icvf{1}, obj.bidsfilter.DWI_ff, FFRAC, 'fiber fraction (ff)')

            end
        end

        function write_vol_qsi(fname, bfilter, data, type)
            bfile = obj.bfile_set(fname, bfilter);
            obj.logger.info('-> Saving %s data to: %s', type, bfile.filename)
            qb.utils.write_vol(Vtgt, data, bfile);
        end
    end

end

end

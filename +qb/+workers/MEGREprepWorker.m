classdef MEGREprepWorker < qb.workers.Worker
%MEGREPREPWORKER Performs preprocessing on raw MEGRE/VFA/MPM data to produce workitems that can be used by other workers
%
% Processing steps:
%
% 1. Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
%    The results are blurry but within the common GRE space, hence, iterate the computation
%    with the input images that have been realigned to the target in the common space
% 2. Coregister all FA-MEGRE images to each T1w-like target image (using echo-1_mag),
%    coregister the B1 images as well to the M0 (which is also in the common GRE space)
% 3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
%    to produce a minimal output mask (for SEPIA)
% 4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows)
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["I am a working class hero that will happily do the following pre-processing work for you:";
                   "";
                   "1. Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.";
                   "   The results are blurry but within the common GRE space, hence, iterate the computation";
                   "   with the input images that have been realigned to the target in the common space";
                   "2. Coregister all MEGRE/VFA/MPM images to each T1w-like target image (using echo-1_mag),";
                   "   coregister the B1 images as well to the M0 (which is also in the common GRE space)";
                   "3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask";
                   "   to produce a minimal output mask (for SEPIA)";
                   "4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows"
                   "";
                   "If only MEGRE data is available, then steps 1 and 2 are skipped"]
    needs       = ["TB1map_anat", "TB1map_angle"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        include = obj.config.General.BIDS.include;
        obj.bidsfilter.rawMEGRE     = setfields(include, ...
                                             modality = 'anat', ...
                                             echo     = 1:999, ...
                                             suffix   = 'MEGRE');
        obj.bidsfilter.rawMEVFA     = setfields(obj.bidsfilter.rawMEGRE, ...
                                             flip     = 1:999, ...
                                             suffix   = 'VFA');
        obj.bidsfilter.rawMEMPM     = setfields(obj.bidsfilter.rawMEVFA, ...
                                             mt       = 'off', ...      `% NB: For now, only process mt-off images, in the future we could also include mt-on images
                                             suffix   = 'MPM');
        obj.bidsfilter.syntheticT1  = struct(modality = 'anat', ...
                                             part     = '', ...
                                             space    = 'withinGRE', ...
                                             desc     = 'synthetic', ...
                                             suffix   = 'T1w');
        obj.bidsfilter.M0map_echo1  = struct(modality = 'anat', ...
                                             part     = '', ...
                                             flip     = [], ...
                                             echo     = 1, ...
                                             space    = obj.bidsfilter.syntheticT1.space, ...
                                             desc     = 'despot1', ...
                                             suffix   = 'M0map');
        obj.bidsfilter.brainmask    = struct(modality = 'anat', ...
                                             echo     = [], ...
                                             part     = '', ...
                                             flip     = [], ...
                                             desc     = 'minimal', ...
                                             label    = 'brain', ...
                                             suffix   = 'mask');
        obj.bidsfilter.echos4Dmag   = struct(modality = 'anat', ...
                                             echo     = [], ...
                                             part     = 'mag', ...
                                             desc     = 'ME4D');
        obj.bidsfilter.echos4Dphase = setfield(obj.bidsfilter.echos4Dmag, part = 'phase');
        obj.bidsfilter.TB1map_GRE   = struct(modality = 'fmap', ...
                                             space    = obj.bidsfilter.syntheticT1.space, ...
                                             acq      = 'famp', ...
                                             suffix   = 'TB1map');

        % Constrain the raw input filters based on the BIDS include config (e.g. to disable the use of VFA/MPM data if only MEGRE data is included)
        if all(cellfun('isempty', regexp(include.suffix, 'MEGRE')))
            obj.bidsfilter.rawMEGRE = setfields(include, suffix = '');      % MEGRE data is not to be included
        end
        if all(cellfun('isempty', regexp(include.suffix, 'VFA')))
            obj.bidsfilter.rawMEVFA = setfields(include, suffix = '');      % VFA data is not to be included
        end
        if all(~cellfun('isempty', regexp(include.suffix, 'MPM')))
            obj.bidsfilter.rawMEMPM = setfields(include, suffix = '');      % MPM data is not to be included
        end

    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get the work done
        if ~isempty(obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawMEGRE))
            obj.create_brainmask(obj.BIDS, obj.bidsfilter.rawMEGRE)         % Processing step 3
            obj.merge_MEfiles()                                             % Processing step 4
        end
        for bfilter = {obj.bidsfilter.rawMEVFA, obj.bidsfilter.rawMEMPM}
            if ~isempty(obj.query_ses(obj.BIDS, 'data', bfilter{1}))
                obj.create_syntheticT1_M0(bfilter{1})                       % Processing step 1
                obj.coreg_VFA_B1_2synthetic(bfilter{1})                     % Processing step 2
                obj.create_brainmask(obj.BIDSW_ses(), bfilter{1})           % Processing step 3
                obj.merge_MEVFAfiles()                                      % Processing step 4
            end
        end
    end

    function create_syntheticT1_M0(obj, bfilter)
        %CREATE_SYNTHETICT1_M0 Implements processing step 1
        %
        % Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
        % The results are blurry but within the common GRE space, hence, iterate the computation
        % with the input images that have been realigned to the target in the common space. The
        % T1 contrast is somewhat off if MPM MT-on_flip-# images are included.

        import qb.utils.spm_write_vol_gz
        import qb.utils.spm_vol

        GRESignal = @(FlipAngle, TR, T1) sind(FlipAngle) .* (1-exp(-TR./T1)) ./ (1-(exp(-TR./T1)) .* cosd(FlipAngle));

        % Process all runs independently
        for run = obj.query_ses(obj.BIDS, 'runs', bfilter)

            % Get the echo-1 magnitude files and metadata for all flip angles of this run
            VFA_e1_filter = qb.utils.setfields(bfilter, echo=1, run=char(run), part='mag');
            VFA_e1 = obj.query_ses(obj.BIDS, 'data', VFA_e1_filter);
            if length(VFA_e1) <= 1
                obj.logger.error("Need at least two different flip angles to compute T1 and S0 maps, found:" + VFA_e1)
            end

            % Get metadata from the first FA file (assume TR and nii-header identical for all MPM/VFAs of the same run)
            Ve1 = spm_vol(VFA_e1{1});

            % Compute T1 and M0 maps
            obj.logger.info("--> Running despot1 to compute T1 and M0 maps from: " + VFA_e1{1})
            e1img = NaN([Ve1.dim length(VFA_e1)]);
            for n = 1:length(VFA_e1)
                e1img(:,:,:,n) = spm_read_vols(spm_vol(VFA_e1{n}));
                metadata       = bids.File(VFA_e1{n}).metadata;
                flipangles(n)  = metadata.FlipAngle;
            end
            [T1, M0] = despot1_mapping(e1img, flipangles, metadata.RepetitionTime);

            % TODO: Iterate the computation with the input images realigned to the synthetic T1w images

            % Save T1w-like images in the work directory
            for n = 1:length(VFA_e1)
                T1w                    = M0 .* GRESignal(flipangles(n), metadata.RepetitionTime, T1);
                T1w(~isfinite(T1w))    = 0;
                bfile                  = obj.bfile_set(VFA_e1{n}, obj.bidsfilter.syntheticT1);
                bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                obj.logger.verbose("-> Saving T1-like synthetic reference " + fullfile(bfile.bids_path, bfile.filename))
                spm_write_vol_gz(Ve1, T1w, bfile);
            end

            % Save the M0 volume as well
            bfile                    = obj.bfile_set(Ve1.fname, obj.bidsfilter.M0map_echo1);
            bfile.metadata.Sources   = strrep(VFA_e1, extractBefore(VFA_e1{1}, bfile.bids_path), 'bids::');
            bfile.metadata.FlipAngle = flipangles;
            obj.logger.verbose("-> Saving M0 map " + fullfile(bfile.bids_path, bfile.filename))
            spm_write_vol_gz(Ve1, M0, bfile);
        end
    end

    function coreg_VFA_B1_2synthetic(obj, bfilter)
        %COREG_VFA_B1_2SYNTHETIC Implements processing step 2
        %
        % Coregister all MEGRE FA-images to each T1w-like target image (using echo-1_mag),
        % coregister the B1 images as well to the M0 (which is also in the common GRE space)

        import qb.utils.spm_write_vol_gz
        import qb.utils.spm_vol
        import qb.utils.setfields

        % Index the workdir layout (only for obj.subject)
        BIDSW = obj.BIDSW_ses();

        % Get the B1 images from the team
        B1famp = obj.ask_team('TB1map_angle');
        B1anat = obj.ask_team('TB1map_anat');

        % Process all runs independently
        for run = obj.query_ses(obj.BIDS, 'runs', bfilter)

            VFA_e1_filter = setfields(bfilter, echo=1, run=char(run), part='mag');

            % Realign all FA images to their synthetic targets
            for flip = obj.query_ses(obj.BIDS, 'flips', VFA_e1_filter)

                % Get the raw echo-1 magnitude file for this flip angle of this run
                VFA_e1 = obj.query_ses(obj.BIDS, 'data', VFA_e1_filter, 'flip',char(flip));

                % Get the common synthetic FA target image
                VFAref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.syntheticT1, 'run',char(run), 'flip',char(flip));
                if length(VFAref) ~= 1
                    obj.logger.exception("I expected one synthetic reference images, but found:" + sprintf("\n%s",VFAref{:}))
                end

                % Coregister the VFA_e1 image to the synthetic target image using Normalized Cross-Correlation (NCC)
                obj.logger.info("--> Coregistering VFA images using: " + VFA_e1)
                Vref = spm_vol(char(VFAref));
                Vin  = spm_vol(char(VFA_e1));
                x    = spm_coreg(Vref, Vin, struct(cost_fun = 'ncc'));

                % Save all resliced echo images for this flip angle (they will be merged to a 4D-file later)
                VFA_flip_filter = setfields(bfilter, flip=char(flip), run=char(run));
                for echo = obj.query_ses(obj.BIDS, 'echos', VFA_flip_filter)

                    % Load the magnitude and phase data -> convert to complex data (to correctly resample phase-wraps)
                    VFA_fe_m     = obj.query_ses(obj.BIDS, 'data', VFA_flip_filter, 'echo',char(echo), 'part','mag');
                    VFA_fe_p     = obj.query_ses(obj.BIDS, 'data', VFA_flip_filter, 'echo',char(echo), 'part','phase');
                    Vfe_m        = spm_vol(char(VFA_fe_m));         % Magnitude volume
                    Vfe_p        = spm_vol(char(VFA_fe_p));         % Phase volume
                    img_m        = spm_read_vols(Vfe_m);
                    img_p        = qb.utils.read_vols_phase(Vfe_p); % Read phase data in radians
                    img          = cat(4, img_m .* cos(img_p), ...  % Real image part
                                          img_m .* sin(img_p));     % Imag image part
                    
                    % Reslice the real and imag data to the synthetic target space (spm_slice_vol doesn't support complex data directly)
                    T     = Vfe_m.mat \ spm_matrix(x) * Vref.mat;   % T = Transformation from voxels in Vref to voxels in Vfe
                    img_r = NaN([Vref.dim 2]);                      % Preallocate resliced images
                    for n = 1:size(img,4)

                        % Avoid disk IO by temporarily replacing the memory mapped mag data with real/imag data
                        Vfe_m.private     = struct();               % Clear private nifti object to allow overriding the memory map
                        Vfe_m.private.dat = img(:,:,:,n);           % Override the memory map with real/imag data
                        Vfe_m.dat         = img(:,:,:,n);           % Make sure that for gz-files ".dat" is also overridden

                        for z = 1:Vref.dim(3)
                            img_r(:,:,z,n) = spm_slice_vol(Vfe_m, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);    % Using trilinear interpolation (NB: the memory map of Vfe_m is used here)
                        end
                    end

                    % Save the magnitude image
                    bfile = obj.bfile_set(Vfe_m.fname, struct(space=obj.bidsfilter.syntheticT1.space, desc='temp3D'));  % Will be merged to desc=ME4D
                    bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                    spm_write_vol_gz(Vref, hypot(img_r(:,:,:,1), img_r(:,:,:,2)), bfile);   % Numerically stable sqrt(Re.^2 + Im.^2)

                    % Save the phase image
                    bfile = obj.bfile_set(Vfe_p.fname, struct(space=obj.bidsfilter.syntheticT1.space, desc='temp3D'));  % Will be merged to desc=ME4D
                    bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                    spm_write_vol_gz(Vref, atan2(img_r(:,:,:,2), img_r(:,:,:,1)), bfile);   % Quadrant-correct phase in radians, range [-pi, pi]

                end

            end

            % Get the B1 images and the common M0 target image
            M0ref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.M0map_echo1, 'run',char(run));
            if length(M0ref) ~= 1
                obj.logger.error("Unexpected M0map images found: %s", sprintf("\n%s", M0ref{:}))
            end

            % Coregister the FA-map to the M0/synthetic T1 space
            if ~isempty(B1famp)
                if length(B1famp) ~= 1 || length(B1anat) ~= 1
                    obj.logger.error("Unexpected B1 images found: %s", sprintf("\n%s", B1famp{:}, B1anat{:}))
                end

                % Coregister the B1-anat image to the M0 target image using Normalized Mutual Information (NMI)
                Vref = spm_vol(char(M0ref));                    % Same space as synthetic T1
                Vin  = spm_vol(char(B1anat));
                x    = spm_coreg(Vref, Vin, struct(cost_fun = 'nmi'));

                % Reslice the FA-map to the M0/synthetic T1 space
                VB1 = spm_vol(char(B1famp));
                T   = VB1.mat \ spm_matrix(x) * Vref.mat;       % Transformation from voxels in Vref to voxels in VB1
                B1  = NaN(Vref.dim);
                for z = 1:Vref.dim(3)
                    B1(:,:,z) = spm_slice_vol(VB1, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                end

                % Save the resliced FA-map
                bfile = obj.bfile_set(B1famp, obj.bidsfilter.TB1map_GRE);
                obj.logger.verbose("-> Saving coregistered " + fullfile(bfile.bids_path, bfile.filename))
                spm_write_vol_gz(Vref, B1, bfile);
            end

        end
    end

    function create_brainmask(obj, BIDS, bfilter)
        %CREATE_BRAINMASK Implements processing step 3
        %
        % Create brain masks for the BFILTER images in BIDS. Combine flip-masks
        % to produce a combined minimal output mask (for QSM and MCR processing)

        import qb.utils.spm_vol

        % Process all runs independently
        for run = obj.query_ses(BIDS, 'runs', bfilter)

            % Combine all (echo-1) masks to create a minimal brain mask (using mri_synthstrip)
            mask = true;
            for echo1 = obj.query_ses(BIDS, 'data', bfilter, 'echo',1, 'run',char(run), 'part','mag')   % This will loop over flips (NB: and possibly more)
                bfile = bids.File(char(echo1));
                specs = setfield(obj.bidsfilter.brainmask, desc = sprintf('VFA%02d', bfile.metadata.FlipAngle));   % Add desc -> (flip)mask is a temporary file
                bfile = obj.bfile_set(bfile, specs);
                [~,~] = mkdir(fileparts(bfile.path));   % Ensure the output directory exists
                obj.run_command(sprintf("mri_synthstrip -i %s -m %s", char(echo1), bfile.path));        % [status,out] = system('echo $CUDA_VISIBLE_DEVICES') does not detect if pytorch was compiled with CUDA support
                mask  = spm_read_vols(spm_vol(bfile.path)) & mask;
                delete(bfile.path)                      % Delete the temporary mask file
            end

            % Save the combined mask
            bfile = obj.bfile_set(echo1, obj.bidsfilter.brainmask);
            obj.logger.info("--> Creating brain mask: %s", bfile.filename)
            qb.utils.spm_write_vol_gz(spm_vol(char(echo1)), mask, bfile);

        end
    end

    function merge_MEVFAfiles(obj)
        %MERGE_MEVFAFILES Implements processing step 4
        %
        % Merge the 3D echos files for each flip angle into 4D files

        import qb.utils.spm_file_merge_gz

        % Index the workdir layout (only for obj.subject)
        BIDSW = obj.BIDSW_ses();

        % Process all runs independently
        bfilter.desc = 'temp3D';
        for run = obj.query_ses(BIDSW, 'runs', bfilter)
            bfilter.run = char(run);

            % Merge the temp3D echos files for each flip angle into 4D files
            for flip = obj.query_ses(BIDSW, 'flips', bfilter)
                bfilter.flip = char(flip);

                % Get the mag/phase echo images for this flip angle & run
                [magfiles,   magbfiles]   = obj.query_ses(BIDSW, 'data',  bfilter, 'part','mag');
                [phasefiles, phasebfiles] = obj.query_ses(BIDSW, 'data',  bfilter, 'part','phase');

                % Sort the mag/phase files by their echo index
                [~, magidx]   = sort(cellfun(@(s) s.metadata.EchoNumber, magbfiles));
                [~, phaseidx] = sort(cellfun(@(s) s.metadata.EchoNumber, phasebfiles));
                
                % Create the 4D mag and phase QSM/MCR input data
                bfile = obj.bfile_set(magfiles{1}, obj.bidsfilter.echos4Dmag);
                obj.logger.verbose("-> Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename)
                spm_file_merge_gz(magfiles(magidx), bfile.path, {'EchoNumber', 'EchoTime'});

                bfile = obj.bfile_set(phasefiles{1}, obj.bidsfilter.echos4Dphase);
                obj.logger.verbose("-> Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename)
                spm_file_merge_gz(phasefiles(phaseidx), bfile.path, {'EchoNumber', 'EchoTime'});

            end
        end
    end

    function merge_MEfiles(obj)
        %MERGE_MEFILES Implements processing step 4 (single flip angle)
        %
        % Merge the raw 3D echos files for each acquisition protocol into 4D files

        import qb.utils.spm_file_merge_gz

        % Merge the 3D echos files into 4D files for all MEGRE acq/runs independently
        bfilter = obj.bidsfilter.rawMEGRE;
        for acq = obj.query_ses(obj.BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = obj.query_ses(obj.BIDS, 'runs', bfilter)
                bfilter.run = char(run);

                % Get the mag/phase echo images for this flip angle & run
                [magfiles,   magbfiles]   = obj.query_ses(obj.BIDS, 'data', bfilter, 'part','mag');
                [phasefiles, phasebfiles] = obj.query_ses(obj.BIDS, 'data', bfilter, 'part','phase');

                % Sort the mag/phase files by their echo index
                [~, magidx]   = sort(cellfun(@(s) s.metadata.EchoNumber, magbfiles));
                [~, phaseidx] = sort(cellfun(@(s) s.metadata.EchoNumber, phasebfiles));

                % Create the 4D mag and phase QSM/MCR input data
                bfile = obj.bfile_set(magfiles{1}, obj.bidsfilter.echos4Dmag);
                obj.logger.verbose("-> Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename)
                spm_file_merge_gz(magfiles(magidx), bfile.path, {'EchoNumber', 'EchoTime'}, false);

                bfile = obj.bfile_set(phasefiles{1}, obj.bidsfilter.echos4Dphase);
                obj.logger.verbose("-> Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename)
                spm_file_merge_gz(phasefiles(phaseidx), bfile.path, {'EchoNumber', 'EchoTime'}, false);

            end
        end
    end
end

end

classdef VFAprepWorker < qb.workers.Worker
%VFAPREPWORKER Performs preprocessing on raw VFA/MPM data to produce workitems that can be used by other workers
%
% Processing steps:
%
% 0. Denoise the raw input data (optional)
% 1. Pass coregistered echo-1_mag VFA/MPM images to despot1 to compute T1w-like target + S0 maps for each FA.
% 2. Coregister all VFA/MPM images to each T1w-like target image (using echo-1_mag),
%    coregister the B1 images as well to the M0 (which is also in the common GRE space)
% 3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
%    to produce a minimal output mask (for SEPIA)
% 4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows)
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["I am a working class hero that will happily do the following pre-processing work for you:";
                   "";
                   "1. Pass coregistered echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.";
                   "2. Coregister all VFA/MPM images to each T1w-like target image (using echo-1_mag),";
                   "   coregister the B1 images as well to the M0 (which is also in the common GRE space)";
                   "3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask";
                   "   to produce a minimal output mask (for SEPIA)";
                   "4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows"
                   "";
                   "If only VFA data is available, then steps 1 and 2 are skipped"]
    needs       = ["TB1map_anat", "TB1map_angle"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        include                    = obj.config.General.BIDS.include;
        obj.bidsfilter.rawMEVFA    = setfields(include, ...
                                            modality = 'anat', ...
                                            echo     = 1:999, ...
                                            flip     = 1:999, ...
                                            suffix   = '(VFA|MPM)');
        obj.bidsfilter.syntheticT1 = struct(modality = 'anat', ...
                                            part     = '', ...
                                            space    = 'withinGRE', ...
                                            desc     = 'synthetic', ...
                                            suffix   = 'T1w');
        obj.bidsfilter.M0map_echo1 = struct(modality = 'anat', ...
                                            part     = '', ...
                                            flip     = [], ...
                                            echo     = 1, ...
                                            space    = obj.bidsfilter.syntheticT1.space, ...
                                            desc     = 'despot1', ...
                                            suffix   = 'M0map');
        obj.bidsfilter.TB1map_GRE  = struct(modality = 'fmap', ...
                                            space    = obj.bidsfilter.syntheticT1.space, ...
                                            acq      = 'famp', ...
                                            suffix   = 'TB1map');
        obj.bidsfilter.TB1anat_GRE = setfield(obj.bidsfilter.TB1map_GRE, acq='anat');

        parent                     = qb.workers.MEGREprepWorker(obj.BIDS, obj.subject, obj.config);
        obj.bidsfilter.brainmask   = parent.bidsfilter.brainmask;
        obj.bidsfilter.ME4Dmag     = parent.bidsfilter.ME4Dmag;
        obj.bidsfilter.ME4Dphase   = parent.bidsfilter.ME4Dphase;

        % Constrain the raw input filters based on the BIDS include config (e.g. to disable the use of VFA data if only MPM data is included)
        if all(cellfun('isempty', regexp(include.suffix, '(VFA|MPM)')))
            obj.bidsfilter.rawMEVFA = setfields(include, suffix='');        % VFA data is not to be included
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

        import qb.utils.setfields
        import qb.workers.MEGREprepWorker.*

        if isempty(obj.bidsfilter.rawMEVFA.suffix)
            return
        end

        % Get the work done. For now, only process mt-off images, in the future we could also include mt-on images
        include = obj.config.General.BIDS.include;
        for bfilter = {setfields(obj.bidsfilter.rawMEVFA, suffix='VFA'), setfields(obj.bidsfilter.rawMEVFA, mt='off', suffix='MPM')}
            if all(cellfun('isempty', regexp(include.suffix, bfilter{1}.suffix)))              % A bit of an ugly hack, for now
                continue
            end
            if ~isempty(obj.query_ses(obj.BIDS, 'data', bfilter{1}))
                obj.denoise_raw(bfilter{1})                                                 % Processing step 5a
                obj.make_syntheticT1_M0(bfilter{1})                                         % Processing step 1
                obj.coreg_VFA_B1_2synthetic(bfilter{1})                                     % Processing step 2+5b
                create_brainmask(obj, obj.BIDSW_ses(), bfilter{1})                          % Processing step 3
                merge_MEVFAfiles(obj, setfield(bfilter{1}, desc='temp3D'), obj.BIDSW_ses()) % Processing step 4
            else
                obj.logger.verbose("No raw %s data found for: ", bfilter{1}.suffix, obj.subject.name)
            end
        end
    end

    function denoise_raw(obj, bfilter)
        %DENOISE_RAW creates a temporary brainmask and denoises raw 5D data

        import qb.workers.MEGREprepWorker.*

        if ~strlength(obj.config.(obj.name).denoising.method)
            return
        end

        obj.bidsfilter.brainmask.id = 'temp';
        obj.bidsfilter.ME4Dmag.id   = 'temp';
        obj.bidsfilter.ME4Dphase.id = 'temp';

        cleanup = onCleanup(@() delete(fullfile(strrep(obj.subject.path, obj.BIDS.pth, obj.workdir), bfilter.modality, '*_id-temp_*mask.*')));
        create_brainmask(obj, obj.BIDS, bfilter)
        merge_MEVFAfiles(obj, bfilter, obj.BIDS, false)
        denoise_MPPCA(obj)

        obj.bidsfilter.brainmask = rmfield(obj.bidsfilter.brainmask, 'id');
        obj.bidsfilter.ME4Dmag   = rmfield(obj.bidsfilter.ME4Dmag,   'id');
        obj.bidsfilter.ME4Dphase = rmfield(obj.bidsfilter.ME4Dphase, 'id');
    end

    function make_syntheticT1_M0(obj, bfilter)
        %CREATE_SYNTHETICT1_M0 Implements processing step 1
        %
        % Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
        % The results are blurry but within the common GRE space, hence, iterate the computation
        % with the input images that have been realigned to the target in the common space. The
        % T1 contrast is somewhat off if MPM MT-on_flip-# images are included.

        import qb.utils.write_vol
        import qb.utils.spm_vol

        GRESignal = @(FlipAngle, TR, T1) sind(FlipAngle) .* (1-exp(-TR./T1)) ./ (1-(exp(-TR./T1)) .* cosd(FlipAngle));

        % Process all acq/runs independently
        for acq = obj.query_ses(obj.BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(obj.BIDS, 'runs', bfilter))

                % Get the echo-1 magnitude files and metadata for all flip angles of this acq/run
                bfilter_e1 = qb.utils.setfields(bfilter, echo=1, run=run, part='mag');
                VFA_e1     = obj.query_ses(obj.BIDS, 'data',  bfilter_e1);
                flips      = obj.query_ses(obj.BIDS, 'flips', bfilter_e1);
                if length(VFA_e1) <= 1
                    obj.logger.error("Need at least two different flip angles to compute T1 and S0 maps, found:" + VFA_e1)
                end
                if length(VFA_e1) ~= length(flips)
                    obj.logger.error("Number of VFA images found (%d) differs from the number of flipangles (%d)", length(VFA_e1), length(flips))
                end

                % Define a reference volume, i.e. the middle FA file (assume TR and nii-header identical for all MPM/VFAs of the same run)
                flip = round(mean(str2double(flips)));
                Vref = spm_vol(char(obj.query_ses(obj.BIDS, 'data', bfilter_e1, flip=flip)));

                % Compute T1 and M0 maps
                obj.logger.info("--> Running despot1 to compute T1 and M0 maps from: " + VFA_e1{1})
                VFAimg = NaN([Vref.dim length(VFA_e1)]);
                for n = 1:length(VFA_e1)
                    VFAn = spm_vol(VFA_e1{n});
                    if strcmp(Vref.fname, VFAn.fname)
                        VFAimg(:,:,:,n) = spm_read_vols(VFAn);
                    else    % Coregister each VFA_e1 volume to the reference volume
                        x = spm_coreg(Vref, VFAn, struct(cost_fun='nmi'));
                        T = VFAn.mat \ spm_matrix(x) * Vref.mat;       % Transformation from voxel coordinates in Vref to voxel coordinates in VFAn
                        for z = 1:Vref.dim(3)
                            VFAimg(:,:,z,n) = spm_slice_vol(VFAn, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                        end
                    end
                    metadata      = bids.File(VFA_e1{n}).metadata;
                    flipangles(n) = metadata.FlipAngle;
                end
                [T1, M0] = despot1_mapping(VFAimg, flipangles, metadata.RepetitionTime);

                % Save T1w-like images in the work directory
                for n = 1:length(VFA_e1)
                    T1w                    = M0 .* GRESignal(flipangles(n), metadata.RepetitionTime, T1);
                    T1w(~isfinite(T1w))    = 0;
                    bfile                  = obj.bfile_set(VFA_e1{n}, obj.bidsfilter.syntheticT1);
                    bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                    obj.logger.verbose("-> Saving T1-like synthetic reference " + fullfile(bfile.bids_path, bfile.filename))
                    write_vol(Vref, T1w, bfile);
                end

                % Save the M0 volume as well
                bfile                    = obj.bfile_set(Vref.fname, obj.bidsfilter.M0map_echo1);
                bfile.metadata.Sources   = strrep(VFA_e1, extractBefore(VFA_e1{1}, bfile.bids_path), 'bids::');
                bfile.metadata.FlipAngle = flipangles;
                obj.logger.verbose("-> Saving M0 map " + fullfile(bfile.bids_path, bfile.filename))
                write_vol(Vref, M0, bfile);
            end
        end
    end

    function coreg_VFA_B1_2synthetic(obj, bfilter)
        %COREG_VFA_B1_2SYNTHETIC Implements processing step 2
        %
        % Coregister all MEVFA-images to each T1w-like target image (using echo-1_mag),
        % coregister the B1 images as well to the M0 (which is also in the common GRE space)

        import qb.utils.write_vol
        import qb.utils.spm_vol
        import qb.utils.read_vols_phase
        import qb.utils.setfields

        % Index the workdir layout (only for obj.subject)
        BIDSW = obj.BIDSW_ses();

        % Get the B1 images from the team
        B1famp = obj.ask_team('TB1map_angle');
        B1anat = obj.ask_team('TB1map_anat');

        % Process all acq/runs independently
        for acq = obj.query_ses(obj.BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(obj.BIDS, 'runs', bfilter))

                bfilter_e1 = setfields(bfilter, echo=1, run=run, part='mag');

                % Get the denoised data (if applicable)
                if strlength(obj.config.(obj.name).denoising.method)
                    denoised_magf   = obj.query_ses(BIDSW, 'data', struct(acq=char(acq), run=run, part='mag', id='temp'));
                    denoised_phasef = obj.query_ses(BIDSW, 'data', struct(acq=char(acq), run=run, part='phase', id='temp'));
                    for m = length(denoised_magf):-1:1
                        denoised_mag(:,:,:,:,m)   = single(spm_read_vols(spm_vol(denoised_magf{m})));
                        denoised_phase(:,:,:,:,m) = single(read_vols_phase(spm_vol(denoised_phasef{m})));
                    end
                    cellfun(@delete, strrep(erase([denoised_magf, denoised_phasef],'.gz'), '.nii','.*'))
                end

                % Realign all FA images to their synthetic targets
                for flip = str2double(obj.query_ses(obj.BIDS, 'flips', bfilter_e1))

                    % Get the common synthetic FA target image and the raw echo-1 magnitude file for this flip angle of this run
                    VFA_e1 = obj.query_ses(obj.BIDS, 'data', bfilter_e1, flip=flip);
                    VFAref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.syntheticT1, acq=char(acq), run=run, flip=flip);
                    if length(VFAref) ~= 1
                        obj.logger.exception("I expected one synthetic reference images, but found:" + sprintf("\n%s",VFAref{:}))
                    end

                    % Coregister the VFA_e1 image to the synthetic target image using Normalized Cross-Correlation (NCC)
                    obj.logger.info("--> Coregistering VFA images using: " + VFA_e1)
                    Vref = spm_vol(char(VFAref));
                    Ve1  = spm_vol(char(VFA_e1));
                    x    = spm_coreg(Vref, Ve1, struct(cost_fun='nmi'));
                    T    = Ve1.mat \ spm_matrix(x) * Vref.mat;          % T = Transformation from voxel coordinates in Vref to voxel coordinates in Ve1/Vfe

                    % Save all (denoised) resliced echo images for this flip angle (they will be merged to a 4D-file later)
                    bfilter_flip = setfields(bfilter, flip=flip, run=run);
                    for echo = str2double(obj.query_ses(obj.BIDS, 'echos', bfilter_flip))

                        % Load the magnitude and phase data -> convert to complex data (to correctly resample phase-wraps)
                        VFA_fe_m = obj.query_ses(obj.BIDS, 'data', bfilter_flip, echo=echo, part='mag');
                        VFA_fe_p = obj.query_ses(obj.BIDS, 'data', bfilter_flip, echo=echo, part='phase');
                        Vfe_m    = spm_vol(char(VFA_fe_m));             % Magnitude volume
                        Vfe_p    = spm_vol(char(VFA_fe_p));             % Phase volume
                        if strlength(obj.config.(obj.name).denoising.method)
                            img_m = denoised_mag(:,:,:,echo,flip);
                            img_p = denoised_phase(:,:,:,echo,flip);
                        else
                            img_m = spm_read_vols(Vfe_m);
                            img_p = read_vols_phase(Vfe_p);             % Read phase data in radians
                        end
                        img = cat(4, img_m .* cos(img_p), ...           % Real image part
                                     img_m .* sin(img_p));              % Imag image part
                        
                        % Reslice the real and imag data to the synthetic target space (spm_slice_vol doesn't support complex data directly)
                        img_r = NaN([Vref.dim 2]);                      % Preallocate resliced images
                        for n = 1:size(img,4)

                            % Avoid disk IO by temporarily replacing the memory mapped mag data with real/imag data
                            Vfe_m.private     = struct();               % Clear private nifti object to allow overriding the memory map
                            Vfe_m.private.dat = double(img(:,:,:,n));   % Override the memory map with real/imag data
                            Vfe_m.dat         = double(img(:,:,:,n));   % Make sure that for gz-files ".dat" is also overridden
                            for z = 1:Vref.dim(3)
                                img_r(:,:,z,n) = spm_slice_vol(Vfe_m, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);    % Using trilinear interpolation (NB: the memory map of Vfe_m is used here)
                            end
                        end

                        % Save the magnitude image
                        bfile = obj.bfile_set(Vfe_m.fname, struct(space=obj.bidsfilter.syntheticT1.space, desc='temp3D'));  % Will be merged to desc=ME4D
                        bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                        if strlength(obj.config.(obj.name).denoising.method)
                            bfile.metadata.Denoised = obj.config.(obj.name).denoising.method;
                        end
                        write_vol(Vref, hypot(img_r(:,:,:,1), img_r(:,:,:,2)), bfile);   % Numerically stable sqrt(Re.^2 + Im.^2)

                        % Save the phase image
                        bfile = obj.bfile_set(Vfe_p.fname, struct(space=obj.bidsfilter.syntheticT1.space, desc='temp3D'));  % Will be merged to desc=ME4D
                        bfile.metadata.Sources = {['bids::' bfile.bids_path '/' bfile.filename]};
                        if strlength(obj.config.(obj.name).denoising.method)
                            bfile.metadata.Denoised = obj.config.(obj.name).denoising.method;
                        end
                        write_vol(Vref, atan2(img_r(:,:,:,2), img_r(:,:,:,1)), bfile);   % Quadrant-correct phase in radians, range [-pi, pi]

                    end

                end

                % Get the B1 images and the common M0 target image
                M0ref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.M0map_echo1, acq=char(acq), run=run);
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
                    VB1a = spm_vol(char(B1anat));
                    x    = spm_coreg(Vref, VB1a, struct(cost_fun='nmi'));
                    T    = VB1a.mat \ spm_matrix(x) * Vref.mat;     % Transformation from voxel coordinates in Vref to voxel coordinates in VB1a/B1anat

                    % Reslice the anat/FA-maps to the M0/synthetic T1 space
                    VB1f = spm_vol(char(B1famp));
                    for z = Vref.dim(3):-1:1
                        B1_famp(:,:,z) = spm_slice_vol(VB1f, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                        B1_anat(:,:,z) = spm_slice_vol(VB1a, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                    end

                    % Save the resliced FA-map
                    bfile = obj.bfile_set(B1famp, obj.bidsfilter.TB1map_GRE);
                    obj.logger.verbose("-> Saving coregistered " + fullfile(bfile.bids_path, bfile.filename))
                    write_vol(Vref, B1_famp, bfile);

                    % Save the resliced FA-anat
                    bfile = obj.bfile_set(B1anat, obj.bidsfilter.TB1anat_GRE);
                    obj.logger.verbose("-> Saving coregistered " + fullfile(bfile.bids_path, bfile.filename))
                    write_vol(Vref, B1_anat, bfile);

                end

            end
        end
    end

end

end

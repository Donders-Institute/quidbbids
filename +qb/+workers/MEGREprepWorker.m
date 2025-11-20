classdef MEGREprepWorker < qb.workers.Worker
%MEGREPREPWORKER Performs preprocessing to produce workitems that can be used by other workers
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


properties (GetAccess = public, SetAccess = protected)
    name        % Name of the worker
    description % Description of the work that is done
    version     % The version of MEGREprepWorker
    needs       % List of workitems the worker needs. Workitems can contain regexp patterns
end


properties
    bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', bidsfilter.(workitem), 'run',1)`
end


methods

    function obj = MEGREprepWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
        % Constructor for this concrete Worker class

        arguments
            BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
            subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
            config    (1,1) struct = struct()   % Configuration struct loaded from the config file
            workdir   {mustBeTextScalar} = ''
            outputdir {mustBeTextScalar} = ''
            team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
            workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
        end

        % Call the abstract parent constructor
        obj@qb.workers.Worker(BIDS, subject, config, workdir, outputdir, team, workitems);

        % Make the abstract properties concrete
        obj.name        = "Marcel";
        obj.description = ["I am a working class hero that will happily do the following pre-processing work for you:";
                            "";
                            "1. Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.";
                            "   The results are blurry but within the common GRE space, hence, iterate the computation";
                            "   with the input images that have been realigned to the target in the common space";
                            "2. Coregister all ME-VFA images to each T1w-like target image (using echo-1_mag),";
                            "   coregister the B1 images as well to the M0 (which is also in the common GRE space)";
                            "3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask";
                            "   to produce a minimal output mask (for SEPIA)";
                            "4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows";
                            "";
                            "If only MEGRE data is available, then steps 1 and 2 are skipped"];
        obj.version     = "0.1.0";
        obj.needs       = ["TB1map_anat", "TB1map_angle"];
        obj.bidsfilter.rawMEVFA     = struct('modality', 'anat', ...
                                                'echo', 1:999, ...
                                                'flip', 1:999, ...
                                                'suffix', 'VFA');
        obj.bidsfilter.rawMEGRE     = struct('modality', 'anat', ...
                                                'echo', 1:999, ...
                                                'suffix', 'MEGRE');
        obj.bidsfilter.syntheticT1  = struct('modality', 'anat', ...
                                                'rec', 'synthetic', ...
                                                'part', '', ...
                                                'space', 'withinGRE', ...
                                                'desc', 'VFAflip\d*', ...
                                                'suffix', 'T1w');
        obj.bidsfilter.M0map_echo1  = struct('modality', 'anat', ...
                                                'part', '', ...
                                                'echo', 1, ...
                                                'space', obj.bidsfilter.syntheticT1.space, ...
                                                'desc', 'despot1', ...
                                                'suffix', 'M0map');
        obj.bidsfilter.brainmask    = struct('modality', 'anat', ...
                                                'echo', [], ...
                                                'part', '', ...
                                                'desc', 'minimal', ...
                                                'label', 'brain', ...
                                                'suffix', 'mask');
        obj.bidsfilter.echos4Dmag   = struct('modality', 'anat', ...
                                                'echo', [], ...
                                                'part', 'mag', ...
                                                'desc', 'ME4D');
        obj.bidsfilter.echos4Dphase = setfield(obj.bidsfilter.echos4Dmag, 'part', 'phase');
        obj.bidsfilter.TB1map_GRE   = struct('modality', 'fmap', ...
                                                'space', obj.bidsfilter.syntheticT1.space, ...
                                                'acq', 'famp', ...
                                                'suffix', 'TB1map');

        % Make the workitems (if requested)
        if strlength(workitems)                             % isempty(string('')) -> false
            for workitem = string(workitems)
                obj.fetch(workitem);
            end
        end
    end

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get the work done
        if obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawMEVFA)
            obj.create_syntheticT1_M0()                                     % Processing step 1
            obj.coreg_VFA_B1_2synthetic()                                   % Processing step 2
            obj.create_brainmask(obj.BIDSW_ses(), obj.bidsfilter.rawMEVFA)  % Processing step 3
            obj.merge_MEVFAfiles()                                          % Processing step 4
        end
        if obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawMEGRE)
            obj.create_brainmask(obj.BIDS, obj.bidsfilter.rawMEGRE)         % Processing step 3
            obj.merge_MEfiles()                                             % Processing step 4
        end
    end

    function create_syntheticT1_M0(obj)
        %CREATE_SYNTHETICT1_M0 Implements processing step 1
        %
        % Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
        % The results are blurry but within the common GRE space, hence, iterate the computation
        % with the input images that have been realigned to the target in the common space

        import qb.utils.spm_write_vol_gz
        import qb.utils.spm_vol
        import qb.utils.setfields

        GRESignal = @(FlipAngle, TR, T1) sind(FlipAngle) .* (1-exp(-TR./T1)) ./ (1-(exp(-TR./T1)) .* cosd(FlipAngle));

        % Process all runs independently
        for run = obj.query_ses(obj.BIDS, 'runs', obj.bidsfilter.rawMEVFA)

            % Get the echo-1 magnitude files and metadata for all flip angles of this run
            VFA_e1_filter = setfields(obj.bidsfilter.rawMEVFA, 'echo',1, 'run',char(run), 'part','(mag)?');
            VFA_e1 = obj.query_ses(obj.BIDS,  'data', VFA_e1_filter);
            flips  = obj.query_ses(obj.BIDS, 'flips', VFA_e1_filter);
            if length(flips) <= 1
                obj.logger.error("Need at least two different flip angles to compute T1 and S0 maps, found:" + flips)
            end

            % Get metadata from the first FA file (assume TR and nii-header identical for all VFAs of the same run)
            Ve1 = spm_vol(VFA_e1{1});

            % Compute T1 and M0 maps
            obj.logger.info("--> Running despot1 to compute T1 and M0 maps from: " + VFA_e1{1})
            e1img = NaN([Ve1.dim length(flips)]);
            for n = 1:length(flips)
                e1img(:,:,:,n) = spm_read_vols(spm_vol(VFA_e1{n}));
                metadata       = bids.File(VFA_e1{n}).metadata;
                flipangles(n)  = metadata.FlipAngle;
            end
            [T1, M0] = despot1_mapping(e1img, flipangles, metadata.RepetitionTime);

            % TODO: Iterate the computation with the input images realigned to the synthetic T1w images

            % Save T1w-like images in the work directory
            for n = 1:length(flips)
                T1w                    = M0 .* GRESignal(flipangles(n), metadata.RepetitionTime, T1);
                T1w(~isfinite(T1w))    = 0;
                specs                  = setfield(obj.bidsfilter.syntheticT1, 'desc', sprintf('VFAflip%s', flips{n}));  % Keep in sync with obj.bidsfilter.syntheticT1.desc
                bfile                  = obj.bfile_set(VFA_e1{n}, specs);
                bfile.metadata.Sources = {['bids:raw:' bfile.bids_path]};                               % TODO: FIXME
                obj.logger.info("Saving T1like synthetic reference " + fullfile(bfile.bids_path, bfile.filename))
                spm_write_vol_gz(Ve1, T1w, bfile.path);
                bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
            end

            % Save the M0 volume as well
            bfile                  = obj.bfile_set(Ve1.fname, obj.bidsfilter.M0map_echo1);
            bfile.metadata.Sources = strrep(VFA_e1, extractBefore(VFA_e1{1}, bfile.bids_path), 'bids:raw:');
            obj.logger.info("Saving M0 map " + fullfile(bfile.bids_path, bfile.filename))
            spm_write_vol_gz(Ve1, M0, bfile.path);
            bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
        end
    end

    function coreg_VFA_B1_2synthetic(obj)
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
        for run = obj.query_ses(obj.BIDS, 'runs', obj.bidsfilter.rawMEVFA)

            VFA_e1_filter = setfields(obj.bidsfilter.rawMEVFA, 'echo',1, 'run',char(run), 'part','(mag)?');

            % Realign all FA images to their synthetic targets
            for flip = obj.query_ses(obj.BIDS, 'flips', VFA_e1_filter)

                % Get the raw echo-1 magnitude file for this flip angle of this run
                VFA_e1 = obj.query_ses(obj.BIDS, 'data', VFA_e1_filter, 'flip',char(flip));

                % Get the common synthetic FA target image
                VFAref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.syntheticT1, 'run',char(run), 'desc',sprintf('VFAflip%s', char(flip)));    % Keep in sync with obj.bidsfilter.syntheticT1
                if length(VFAref) ~= 1
                    obj.logger.exception("I expected one synthetic reference images, but found:" + sprintf("\n%s",VFAref{:}))
                end

                % Coregister the VFA_e1 image to the synthetic target image using Normalized Cross-Correlation (NCC)
                obj.logger.info("--> Coregistering echo images for FA: " + flip)
                Vref = spm_vol(char(VFAref));
                Vin  = spm_vol(char(VFA_e1));
                x    = spm_coreg(Vref, Vin, struct('cost_fun', 'ncc'));

                % Save all resliced echo images for this flip angle (they will be merged to a 4D-file later)
                VFA_flip_filter = setfields(obj.bidsfilter.rawMEVFA, 'flip',char(flip), 'run',char(run), 'part','(mag)?');
                for echo = obj.query_ses(obj.BIDS, 'echos', VFA_flip_filter)
                    VFA_fe = obj.query_ses(obj.BIDS, 'data', VFA_flip_filter, 'echo',char(echo));
                    Vfe    = spm_vol(char(VFA_fe));
                    img    = NaN(Vref.dim);
                    T      = Vfe.mat \ spm_matrix(x) * Vref.mat;     % Transformation from voxels in Vref to voxels in Vfe
                    for z = 1:Vref.dim(3)
                        img(:,:,z) = spm_slice_vol(Vfe, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);    % Using trilinear interpolation
                    end
                    bfile = obj.bfile_set(Vfe.fname, 'space',obj.bidsfilter.syntheticT1.space, 'desc','temp3D');  % Will be merged to desc=ME4D
                    bfile.metadata.Sources = {['bids:raw:' bfile.bids_path]};       % TODO: FIXME
                    spm_write_vol_gz(Vref, img, bfile.path);
                    bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
                end

            end

            % Get the B1 images and the common M0 target image
            M0ref = obj.query_ses(BIDSW, 'data', obj.bidsfilter.M0map_echo1, 'run',char(run));
            if length(M0ref) ~= 1
                obj.logger.error("Unexpected M0map images found: %s", sprintf("\n%s", M0ref{:}))
            end

            % Coregister the B1-anat fmap to the M0 target image using Normalized Mutual Information (NMI)
            if ~isempty(B1famp)
                if length(B1famp) ~= 1 || length(B1anat) ~= 1
                    obj.logger.error("Unexpected B1 images found: %s", sprintf("\n%s", B1famp{:}, B1anat{:}))
                end

                Vref = spm_vol(char(M0ref));                    % Same space as synthetic T1
                Vin  = spm_vol(char(B1anat));
                x    = spm_coreg(Vref, Vin, struct('cost_fun', 'nmi'));

                % Save the resliced FA-map
                VB1 = spm_vol(char(B1famp));
                B1  = NaN(Vref.dim);
                T   = VB1.mat \ spm_matrix(x) * Vref.mat;       % Transformation from voxels in Vref to voxels in VB1
                for z = 1:Vref.dim(3)
                    B1(:,:,z) = spm_slice_vol(VB1, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                end
                bfile = obj.bfile_set(B1famp, obj.bidsfilter.TB1map_GRE);
                obj.logger.info("Saving coregistered " + fullfile(bfile.bids_path, bfile.filename))
                spm_write_vol_gz(Vref, B1, bfile.path);
                bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
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
            for echo1 = obj.query_ses(BIDS, 'data', bfilter, 'echo',1, 'run',char(run))     % This will loop over flips (NB: and possibly more)
                bfile = bids.File(char(echo1));
                specs = setfield(obj.bidsfilter.brainmask, 'desc', sprintf('VFA%02d', bfile.metadata.FlipAngle));   % Add desc -> (flip)mask is a temporary file
                bfile = obj.bfile_set(bfile, specs);
                [~,~] = mkdir(fileparts(bfile.path));   % Ensure the output directory exists
                obj.run_command(sprintf("mri_synthstrip -i %s -m %s", char(echo1), bfile.path));
                mask  = spm_read_vols(spm_vol(bfile.path)) & mask;
                delete(bfile.path)                      % Delete the temporary mask file
            end

            % Save the combined mask
            bfile = obj.bfile_set(echo1, obj.bidsfilter.brainmask);
            obj.logger.info("--> Creating brain mask: %s", bfile.filename)
            qb.utils.spm_write_vol_gz(spm_vol(char(echo1)), mask, bfile.path);
            bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)

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
                magfiles   = obj.query_ses(BIDSW, 'data',  bfilter, 'part','(mag)?');
                phasefiles = obj.query_ses(BIDSW, 'data',  bfilter, 'part','phase');

                % Sort the mag/phase files by their echo index
                phaseechos    = obj.query_ses(BIDSW, 'echos', bfilter, 'part','phase');
                magechos      = obj.query_ses(BIDSW, 'echos', bfilter, 'part','(mag)?');
                [~, magidx]   = sort(double(string(magechos)));
                [~, phaseidx] = sort(double(string(phaseechos)));
                
                % Create the 4D mag and phase QSM/MCR input data
                bfile = obj.bfile_set(magfiles{1}, obj.bidsfilter.echos4Dmag);
                obj.logger.info("Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename)
                spm_file_merge_gz(magfiles(magidx), bfile.path, {'EchoNumber', 'EchoTime'});

                bfile = obj.bfile_set(phasefiles{1}, obj.bidsfilter.echos4Dphase);
                obj.logger.info("Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename)
                spm_file_merge_gz(phasefiles(phaseidx), bfile.path, {'EchoNumber', 'EchoTime'});

            end
        end
    end

    function merge_MEfiles(obj)
        %MERGE_MEFILES Implements processing step 4 (without fmap data / single flip angle)
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
                magfiles   = obj.query_ses(obj.BIDS, 'data', bfilter, 'part','(mag)?');
                phasefiles = obj.query_ses(obj.BIDS, 'data', bfilter, 'part','phase');

                % Sort the mag/phase files by their echo index
                phaseechos    = obj.query_ses(BIDSW, 'echos', bfilter, 'part','phase');
                magechos      = obj.query_ses(BIDSW, 'echos', bfilter, 'part','(mag)?');
                [~, magidx]   = sort(double(string(magechos)));
                [~, phaseidx] = sort(double(string(phaseechos)));

                % Create the 4D mag and phase QSM/MCR input data
                bfile = obj.bfile_set(magfiles{1}, obj.bidsfilter.echos4Dmag);
                obj.logger.info("Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename)
                spm_file_merge_gz(magfiles(magidx), bfile.path, {'EchoNumber', 'EchoTime'}, false);

                bfile = obj.bfile_set(phasefiles{1}, obj.bidsfilter.echos4Dphase);
                obj.logger.info("Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename)
                spm_file_merge_gz(phasefiles(phaseidx), bfile.path, {'EchoNumber', 'EchoTime'}, false);

            end
        end
    end
end

end

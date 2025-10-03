classdef PreprocWorker < qb.workers.Worker
    %PREPROCWORKER Performs preprocessing to produce workitems that can be used by other workers
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
        description % Description of the work that is done (e.g. for GUIs)
        needs       % List of workitems the worker needs
    end

    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `bids.query('data', setfield(bidsfilter.(workitem), 'run',1))`
    end
    
    
    methods

        function obj = PreprocWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            %PREPROCWORKER Constructor for this concrete Worker class

            arguments
                BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
                subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
                config    (1,1) struct = struct()   % Configuration struct loaded from the config TOML file
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
                               "2. Coregister all FA-MEGRE images to each T1w-like target image (using echo-1_mag),";
                               "   coregister the B1 images as well to the M0 (which is also in the common GRE space)";
                               "3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask";
                               "   to produce a minimal output mask (for SEPIA)";
                               "4. Merge all echoes for each flip angle into 4D files (for running the QSM and SCR/MCR workflows"];
            obj.needs       = [];         % TODO: Think about using a worker or filter to fetch the raw BIDS (anat and fmap) input data
            obj.bidsfilter.syntheticT1  = struct('modality', 'anat', ...
                                                 'part', '', ...
                                                 'space', 'withinGRE', ...
                                                 'desc', 'FA\d*synthetic', ...
                                                 'suffix', 'T1w');
            obj.bidsfilter.M0map_echo1  = struct('modality', 'anat', ...
                                                 'space', 'withinGRE', ...
                                                 'desc', 'despot1echo1', ...
                                                 'suffix', 'M0map');
            obj.bidsfilter.brainmask    = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', '', ...
                                                 'space', 'withinGRE', ...
                                                 'desc', 'minimal', ...
                                                 'label', 'brain', ...
                                                 'suffix', 'mask');
            obj.bidsfilter.echos4Dmag   = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', 'mag', ...
                                                 'desc', 'FA\d*', ...
                                                 'space', 'withinGRE');
            obj.bidsfilter.echos4Dphase = setfield(obj.bidsfilter.echos4Dmag, 'part', 'phase');
            obj.bidsfilter.FAmap_angle  = struct('modality', 'fmap', ...
                                                 'space', 'withinGRE', ...
                                                 'acq', 'famp');
            obj.bidsfilter.FAmap_anat   = setfield(obj.bidsfilter.FAmap_angle, 'acq', 'anat');
            
            % Fetch the workitems (if requested)
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

            % Check the input
            if isempty(obj.subject.anat) || isempty(obj.subject.fmap)
                return
            end

            % Get the work done
            obj.create_common_syntheticT1_M0()  % Processing step 1
            obj.coreg_FAs_B1_2common()          % Processing step 2
            obj.create_brainmask()              % Processing step 3
            obj.merge_echofiles()               % Processing step 4
        end

        function create_common_syntheticT1_M0(obj)
            %CREATE_COMMON_SYNTHETICT1_M0 Implements processing step 1
            %
            % Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
            % The results are blurry but within the common GRE space, hence, iterate the computation
            % with the input images that have been realigned to the target in the common space

            import qb.utils.spm_write_vol_gz

            GRESignal = @(FlipAngle, TR, T1) sind(FlipAngle) .* (1-exp(-TR./T1)) ./ (1-(exp(-TR./T1)) .* cosd(FlipAngle));

            % TODO: Index the workdir if force=false
            % BIDSW = bids.layout(char(obj.workdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

            % Process all runs independently
            anat_mag = {'sub',obj.sub(), 'ses',obj.ses(), 'modality','anat', 'part','mag'};
            for run = bids.query(obj.BIDS, 'runs', anat_mag{:}, 'echo',1:999)    % Note that the suffix (e.g. 'MEGRE') is already selected in the BIDS layout

                % Get the echo-1 magnitude files and metadata for all flip angles of this run
                FAs_e1m = bids.query(obj.BIDS,     'data', anat_mag{:}, 'echo',1, 'run',char(run));
                meta    = bids.query(obj.BIDS, 'metadata', anat_mag{:}, 'echo',1, 'run',char(run));
                flips   = cellfun(@getfield, meta, repmat({'FlipAngle'}, size(meta)), "UniformOutput", true);
                if length(flips) <= 1
                    obj.logger.error("Need at least two different flip angles to compute T1 and S0 maps, found:" + sprintf(" %s", flips{:}));
                end

                % Get metadata from the first FA file (assume TR and nii-header identical for all FAs of the same run)
                Ve1m = spm_vol(FAs_e1m{1});
                TR   = meta{1}.RepetitionTime;

                % Compute T1 and M0 maps
                obj.logger.info("--> Running despot1 to compute T1 and M0 maps from: " + FAs_e1m{1});
                e1mag = zeros([Ve1m.dim length(flips)]);
                for n = 1:length(flips)
                    e1mag(:,:,:,n) = spm_vol(FAs_e1m{n}).dat();
                end
                [T1, M0] = despot1_mapping(e1mag, flips, TR);

                % TODO: Iterate the computation with the input images realigned to the synthetic T1w images

                % Save T1w-like images in the work directory
                for n = 1:length(flips)
                    T1w                    = M0 .* GRESignal(flips(n), TR, T1);
                    T1w(~isfinite(T1w))    = 0;
                    specs                  = setfield(obj.bidsfilter.syntheticT1, 'desc', sprintf('FA%02dsynthetic', flips(n)));  % Keep in sync with obj.bidsfilter.syntheticT1.desc
                    bfile                  = obj.update_bfile(bids.File(FAs_e1m{n}), specs);
                    bfile.metadata.Sources = {['bids:raw:' bfile.bids_path]};                               % TODO: FIXME
                    obj.logger.info("Saving T1like synthetic reference " + fullfile(bfile.bids_path, bfile.filename))
                    spm_write_vol_gz(Ve1m, T1w, bfile.path);
                    bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
                end

                % Save the M0 volume as well
                bfile                  = obj.update_bfile(bids.File(FAs_e1m{n}), obj.bidsfilter.M0map_echo1);
                bfile.metadata.Sources = strrep(FAs_e1m, extractBefore(FAs_e1m{1}, bfile.bids_path), 'bids:raw:');
                obj.logger.info("Saving M0 map " + fullfile(bfile.bids_path, bfile.filename))
                spm_write_vol_gz(Ve1m, M0, bfile.path);
                bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
            end
        end

        function coreg_FAs_B1_2common(obj)
            %COREG_FAS_B1_2COMMON Implements processing step 2
            %
            % Coregister all MEGRE FA-images to each T1w-like target image (using echo-1_mag),
            % coregister the B1 images as well to the M0 (which is also in the common GRE space)

            import qb.utils.spm_write_vol_gz

            % Index the workdir layout (only for obj.subject)
            BIDSW = obj.layout_workdir();

            % Process all runs independently
            anat = {'sub',obj.sub(), 'ses',obj.ses(), 'modality','anat'};
            fmap = {'sub',obj.sub(), 'ses',obj.ses(), 'modality','fmap'};
            for run = bids.query(obj.BIDS, 'runs', anat{:}, 'part','mag', 'echo',1:999)

                % Get the echo-1 magnitude files and metadata for all flip angles of this run
                FAs_e1m = bids.query(obj.BIDS,     'data', anat{:}, 'echo',1, 'part','mag', 'run',char(run));
                meta    = bids.query(obj.BIDS, 'metadata', anat{:}, 'echo',1, 'part','mag', 'run',char(run));
                flips   = cellfun(@getfield, meta, repmat({'FlipAngle'}, size(meta)), "UniformOutput", true);

                % Realign all FA images to their synthetic targets
                for n = 1:length(flips)

                    % Get the common synthetic FA target image
                    FAref = bids.query(BIDSW, 'data', setfield(setfield(obj.bidsfilter.syntheticT1, 'run',char(run)), 'desc',sprintf('FA%02dsynthetic', flips(n))));    % Keep in sync with obj.bidsfilter.syntheticT1
                    if length(FAref) ~= 1
                        obj.logger.exception("I expected one synthetic reference images, but found: " + sprintf("\n%s",FAref{:}));
                    end

                    % Coregister the FAs_e1m image to the synthetic target image using Normalized Cross-Correlation (NCC)
                    obj.logger.info("--> Coregistering echo images for FA: " + flips(n))
                    Vref = spm_vol(char(FAref));
                    Vin  = spm_vol(FAs_e1m{n});
                    x    = spm_coreg(Vref, Vin, struct('cost_fun', 'ncc'));

                    % Save all resliced echo images for this flip angle (they will be merged to a 4D-file later)
                    for echo = bids.query(obj.BIDS, 'data', anat{:}, 'run',char(run))'
                        bfile = bids.File(char(echo));
                        if bfile.metadata.FlipAngle ~= flips(n)
                            continue
                        end
                        Vin    = spm_vol(char(echo));
                        volume = zeros(Vref.dim);
                        T      = Vin.mat \ spm_matrix(x) * Vref.mat;    % Transformation from voxels in Vref to voxels in Vin
                        for z = 1:Vref.dim(3)
                            volume(:,:,z) = spm_slice_vol(Vin, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                        end
                        bfile.entities.space   = obj.bidsfilter.echos4Dmag.space;
                        bfile.entities.desc    = sprintf('FA%02d', flips(n));
                        bfile.metadata.Sources = {['bids:raw:' bfile.bids_path]};       % TODO: FIXME
                        spm_write_vol_gz(Vref, volume, fullfile(obj.workdir, bfile.bids_path, bfile.filename));
                        bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
                    end

                end

                % Get the B1 images and the common M0 target image
                B1famp = bids.query(obj.BIDS,  'data', fmap{:}, 'run',char(run), 'acq','famp', 'echo',[]);  % TODO: Use a GetdataWorker
                B1anat = bids.query(obj.BIDS,  'data', fmap{:}, 'run',char(run), 'acq','anat', 'echo',[]);
                M0ref  = bids.query(BIDSW,     'data', setfield(obj.bidsfilter.M0map_echo1, 'run',char(run)));
                if length(B1famp) ~= 1 || length(B1anat) ~= 1
                    error("Unexpected B1 images found: %s", sprintf("\n%s", B1famp{:}, B1anat{:}));
                end
                if length(M0ref) ~= 1
                    error("Unexpected M0map images found: %s", sprintf("\n%s", M0ref{:}));
                end

                % Coregister the B1-anat fmap to the M0 target image using Normalized Mutual Information (NMI)
                Vref = spm_vol(char(M0ref));
                Vin  = spm_vol(char(B1anat));
                x    = spm_coreg(Vref, Vin, struct('cost_fun', 'nmi'));

                % Save the resliced B1 images
                for B1vol = [B1anat, B1famp]
                    Vin    = spm_vol(char(B1vol));
                    volume = zeros(Vref.dim);
                    T      = Vin.mat \ spm_matrix(x) * Vref.mat;    % Transformation from voxels in Vref to voxels in Vin
                    for z = 1:Vref.dim(3)
                        volume(:,:,z) = spm_slice_vol(Vin, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
                    end
                    bfile                = bids.File(char(B1vol));
                    bfile.entities.space = obj.bidsfilter.FAmap_angle.space;
                    obj.logger.info("Saving coregistered " + fullfile(bfile.bids_path, bfile.filename))
                    spm_write_vol_gz(Vref, volume, fullfile(obj.workdir, bfile.bids_path, bfile.filename));
                    bids.util.jsonencode(fullfile(char(obj.workdir), bfile.bids_path, bfile.json_filename), bfile.metadata)
                end
            end
        end

        function create_brainmask(obj)
            %CREATE_BRAINMASK Implements processing step 3
            %
            % Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
            % to produce a minimal output mask (for QSM and MCR processing)

            % Index the workdir layout (only for obj.subject)
            BIDSW = obj.layout_workdir();

            % Process all runs independently
            anat_mag = {'modality','anat', 'space',obj.bidsfilter.brainmask.space, 'part','mag'};  % Keep in sync
            for run = bids.query(BIDSW, 'runs', anat_mag{:}, 'echo',1:999)

                % Get the echo-1 magnitude file for all flip angles of this run
                FAs_e1m = bids.query(BIDSW, 'data', anat_mag{:}, 'echo',1, 'run',char(run));

                % Create individual brain masks using mri_synthstrip
                Ve1m  = spm_vol(FAs_e1m{1});
                masks = zeros([Ve1m.dim length(FAs_e1m)]);
                for n = 1:length(FAs_e1m)
                    bfile          = bids.File(FAs_e1m{n});
                    specs          = setfield(obj.bidsfilter.brainmask, 'desc', sprintf('FA%02d', bfile.metadata.FlipAngle));
                    bfile          = obj.update_bfile(bfile, specs);
                    obj.logger.info(sprintf("--> Creating brain mask for FA: %d -> %s", bfile.metadata.FlipAngle, bfile.filename))
                    obj.run_command(sprintf("mri_synthstrip -i %s -m %s", FAs_e1m{n}, bfile.path));
                    masks(:,:,:,n) = spm_vol(bfile.path).dat();
                    delete(bfile.path)      % Delete the individual mask files to save space
                end

                % Combine the individual masks to create a minimal brain mask
                bfile      = obj.update_bfile(bfile, obj.bidsfilter.brainmask);
                Ve1m.dt(1) = spm_type('uint8');
                Ve1m.pinfo = [1; 0];
                qb.utils.spm_write_vol_gz(Ve1m, all(masks,4), bfile.path);
                bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)

            end
        end

        function merge_echofiles(obj)
            %MERGE_ECHOFILES Implements processing step 4
            %
            % Merge the 3D echos files for each flip angle into 4D files

            import qb.utils.spm_file_merge_gz

            % Index the workdir layout (only for obj.subject)
            BIDSW = obj.layout_workdir();

            % Process all runs independently
            anat = {'modality','anat', 'space',obj.bidsfilter.echos4Dmag.space};
            for run = bids.query(BIDSW, 'runs', anat{:}, 'part','mag', 'echo',1:999, 'desc','FA\d*')

                % Get the flip angles for this run
                FAs = bids.query(BIDSW, 'descriptions', anat{:}, 'desc','FA\d*', 'part','mag', 'echo',1, 'run',char(run));
                if length(FAs) < 2
                    obj.logger.error("No flip angle images found in: " + obj.subject.path);
                end

                % Merge the 3D echos files for each flip angle into 4D files
                for FA = FAs

                    % Get the mag/phase echo images for this flip angle & run
                    magfiles   = bids.query(BIDSW, 'data', anat{:}, 'echo',1:999, 'run',char(run), 'desc',char(FA), 'part','mag');
                    phasefiles = bids.query(BIDSW, 'data', anat{:}, 'echo',1:999, 'run',char(run), 'desc',char(FA), 'part','phase');

                    % Reorder the data because SEPIA (possibly?) expects the TE to be in increasing order
                    meta       = bids.query(BIDSW, 'metadata', anat{:}, 'echo',1:999, 'run',char(run), 'desc',char(FA), 'part','mag');
                    [TEs, idx] = sort(cellfun(@getfield, meta, repmat({'EchoTime'}, size(meta)), "UniformOutput", true));
                    magfiles   = magfiles(idx);
                    phasefiles = phasefiles(idx);
                    if length(TEs) ~= length(unique(TEs))           % Check if the TEs are unique
                        obj.logger.exception(sprintf("Non-unique TEs (%s) found in: %s", strtrim(sprintf('%g ', TEs)), subject.path))
                    end

                    % Create the 4D mag and phase QSM/MCR input data
                    bfile = obj.update_bfile(bids.File(phasefiles{1}), rmfield(obj.bidsfilter.echos4Dphase, 'desc'));
                    obj.logger.info(sprintf("Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename))
                    spm_file_merge_gz(phasefiles, bfile.path, {'EchoNumber', 'EchoTime'});

                    bfile = obj.update_bfile(bids.File(magfiles{1}), rmfield(obj.bidsfilter.echos4Dmag, 'desc'));
                    obj.logger.info(sprintf("Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename))
                    spm_file_merge_gz(magfiles, bfile.path, {'EchoNumber', 'EchoTime'});

                end
            end
        end

    end

end

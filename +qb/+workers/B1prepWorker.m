classdef B1prepWorker < qb.workers.Worker
    %B1PREPWORKER Performs preprocessing to produce workitems that can be used by other workers
    %
    % See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of B1prepWorker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end

    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', setfield(bidsfilter.(workitem), 'run',1))`
    end


    methods

        function obj = B1prepWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            % Constructor for this concrete Worker class

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
            obj.name        = "Yoda";
            obj.description = ["I am a modest worker that fabricates regularized flip-angle maps in degrees (ready for the big B1-correction party!)"];
            obj.version     = "0.1.0";
            obj.needs       = [];         % TODO: Think about using a worker or filter to fetch the raw BIDS (anat and fmap) input data
            obj.bidsfilter.B1map_angle = struct('modality', 'fmap', 'acq', 'famp', 'desc', 'degrees', 'space', '');
            obj.bidsfilter.B1map_anat  = setfield(obj.bidsfilter.B1map_angle, 'acq', 'anat');

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

            % Get the B1 anat and fa-map images
            B1anat = obj.query_ses(obj.BIDS,  'data', 'modality','fmap', 'acq','anat', 'echo',[]);
            B1famp = obj.query_ses(obj.BIDS,  'data', 'modality','fmap', 'acq','famp', 'echo',[]);
            if length(B1anat) ~= length(B1famp)
                error("Unexpected number of B1-files found: acq-anat=%d vs acq-famp=%d", length(B1anat), length(B1famp))
            end

            for n = 1:length(B1anat)

                % Load the FA-map
                bfile = bids.File(B1famp{n});
                FAVol = spm_vol(B1famp{n});
                FA    = spm_read_vols(FAVol);
                if isfield(obj.config.B1prepWorker.FAscaling, bfile.metadata.Manufacturer)
                    FA = FA / obj.config.B1prepWorker.FAscaling.(bfile.metadata.Manufacturer); % Scale to degrees
                end

                % Regularize the FA-map in order to avoid influence of salt & pepper border noise
                if obj.config.B1prepWorker.FWHM ~= 0
                    dim = spm_imatrix(FAVol.mat);
                    FA  = spm_read_vols(spm_vol(B1anat{n})) .* exp(1i*FA);                            % Make complex and multiply with anat to avoid smoothing skull-noise across tissue borders
                    FA  = angle(smooth3D(FA, obj.config.B1prepWorker.FWHM, abs(dim(7:9))));  % Smooth and take angle again
                end

                % Save the FA-map image & json file
                bfile = obj.bfile_set(bfile, obj.bidsfilter.B1map_angle);
                obj.logger.info(sprintf("--> Saving regularized B1-map: %s", bfile.filename))
                qb.utils.spm_write_vol_gz(FAVol, FA, bfile.path);
                bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)

                % Copy the anat image & json file
                bfile = obj.bfile_set(B1anat{n}, obj.bidsfilter.B1map_anat);
                copyfile(B1anat{n}, bfile.path);
                bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)

            end
        end

    end

end

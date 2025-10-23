classdef R1R2sWorker < qb.workers.Worker
%R1R2SWORKER Runs MCR workflow

    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of R1R2SWORKER
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end

    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `bids.query('data', setfield(bidsfilter.(workitem), 'run',1))`
    end
    
    
    methods

        function obj = R1R2sWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            %R1R2SWORKER Constructor for this concrete Worker class

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
            obj.name        = "R2D2";
            obj.description = ["I'm R2-D2, an astromech droid that can fix starships and, yes, generate precise R1- and R2-starmaps for all your neuro-navigation needs!";
                               "";
                               "Methods:"
                               "- Gacelle et al., MRM 2020 for R2-star mapping from multi-echo GRE data"];
            obj.version     = "0.1.0";
            obj.needs       = ["echos4Dmag", "FAmap_angle", "brainmask"];  % TODO: Ask Jose which mask to use
            obj.bidsfilter.R2starmap = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'part', '', ...
                                              'desc', 'gacelleR1R2s', ...
                                              'suffix', 'R2starmap');
            obj.bidsfilter.M0map     = setfield(obj.bidsfilter.R2starmap, 'suffix','M0Map');
            obj.bidsfilter.R1map     = setfield(obj.bidsfilter.R2starmap, 'suffix','R1map');
            
            % Make the workitems (if requested)
            if strlength(workitems)                 % isempty(string('')) -> false
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
            
            import qb.utils.spm_write_vol_gz

            % Check the input
            if isempty(obj.subject.anat) || isempty(obj.subject.fmap)
                return
            end

            % Get the workitems we need from a colleague
            echos4Dmag  = obj.ask_team('echos4Dmag');       % Multiple FA-images per run
            FAmap_angle = obj.ask_team('FAmap_angle');      % Single image per run
            brainmask   = obj.ask_team('brainmask');        % Multiple FA-images per run

            % Check the number of items we got: TODO: FIXME: multi-run acquisitions
            if length(echos4Dmag) < 2
                obj.logger.exception(sprintf('%s received data for only %d flip angles', obj.name, length(echos4Dmag)))
            end
            if length(FAmap_angle) ~= 1         % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
                obj.logger.exception(sprintf('%s expected only one FAmap file but got: %s', obj.name, sprintf('%s ', FAmap_angle{:})))
            end
            if length(brainmask) ~= 1           % TODO: FIXME
                obj.logger.exception('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', brainmask{:}))
            end
            
            % Load the data + metadata
            V    = spm_vol(echos4Dmag{1});                          % For reading the 3D image dimensions
            dims = [V(1).dim length(V) length(echos4Dmag)];
            img  = NaN(dims);
            for n = 1:dims(5)
                img(:,:,:,:,n) = spm_read_vols(spm_vol(echos4Dmag{n}));
                bfile          = bids.File(echos4Dmag{1});          % For reading metadata, parsing entities, etc
                FA(n)          = bfile.metadata.FlipAngle;
            end
            mask = spm_vol(char(brainmask)).dat() & all(~isnan(img), [4 5]);
            B1   = spm_vol(char(FAmap_angle)).dat() / obj.config.RelB1mapWorker.B1ScaleFactor;     % TODO: Replace with a worker that computes a relative B1-map
            TR   = bfile.metadata.RepetitionTime;
            TE   = bfile.metadata.EchoTime;

            % Estimate the MCR model
            extraData     = [];
            extraData.b1  = single(B1);
            objGPU        = gpuJointR1R2starMapping(TE, TR, FA);
            askadam_R1R2s = objGPU.estimate(img, mask, extraData, obj.config.R1R2sWorker.fitting.GPU);  % TODO: Is single() needed/desired?

            % Save the output data
            V.dim = dims(1:3);
            spm_write_vol_gz(V, askadam_R1R2s.final.R1,     obj.update_bfile(bfile, obj.bidsfilter.R1map,     obj.workdir).path);
            spm_write_vol_gz(V, askadam_R1R2s.final.M0,     obj.update_bfile(bfile, obj.bidsfilter.M0map,     obj.workdir).path);
            spm_write_vol_gz(V, askadam_R1R2s.final.R2star, obj.update_bfile(bfile, obj.bidsfilter.R2starmap, obj.workdir).path);
        end

    end

end

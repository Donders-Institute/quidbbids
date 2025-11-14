classdef SCRWorker < qb.workers.Worker
    %SCRWORKER Runs SCR workflow
    %
    % See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of SCRWorker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end


    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', setfield(bidsfilter.(workitem), 'run',1))`
    end


    methods

        function obj = SCRWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
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
            obj.name        = "Samuel";
            obj.description = ["Your relaxed number cruncher that fits SCR models for breakfast";
                               "";
                               "Methods:"
                               "- Compute weighted means of the R2-star & Chi-maps over the different flip-angles";
                               "- Compute R1- & M0-maps based on despot1 with S0 estimates"];
            obj.version     = "0.0.1";
            obj.needs       = ["S0map", "R2starmap", "Chimap", "localfmask", "B1map_VFA"];
            obj.bidsfilter.R1map_S0      = struct('modality', 'anat', ...
                                                  'echo', [], ...
                                                  'part', '', ...
                                                  'desc', 'despot1S0', ...
                                                  'suffix', 'R1map');
            obj.bidsfilter.M0map_S0      = setfield(obj.bidsfilter.R1map_S0, 'suffix', 'M0map');
            obj.bidsfilter.meanR2starmap = struct('modality', 'anat', ...
                                                  'echo', [], ...
                                                  'part', '', ...
                                                  'desc', 'mean', ...
                                                  'suffix', 'R2starmap');
            obj.bidsfilter.meanChimap    = setfield(obj.bidsfilter.meanR2starmap, 'suffix', 'Chimap');

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

            import qb.utils.spm_write_vol_gz
            import qb.utils.spm_vol
            import qb.utils.spm_read_vols

            % Check the input
            if ~ismember("fmap", fieldnames(obj.subject))
                return
            end

            % Get the QSM workitems we need from a colleague (instead of just getting the files, use the filters to get the right runs ourselves)
            [~, S0filter]     = obj.ask_team('S0map');
            [~, maskfilter]   = obj.ask_team('localfmask');
            [~, R2starfilter] = obj.ask_team('R2starmap');  % TODO: Make optional (-> ME-VFA data)
            [~, Chifilter]    = obj.ask_team('Chimap');     % TODO: Make optional (-> ME-VFA data)

            % Get B1map from a colleague
            B1map             = obj.ask_team('B1map_VFA');
            if length(B1map) ~= 1       % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
                obj.logger.exception(sprintf('%s expected only one B1map file but got: %s', obj.name, sprintf('%s ', B1map{:})))
            end
            B1 = spm_read_vols(spm_vol(char(B1map)));

            % Index the (special) SEPIA workdir layout (only for obj.subject)
            BIDSWS = obj.layout_workdir(replace(obj.workdir, "QuIDBBIDS", "SEPIA"));

            % Process all runs independently
            for run = obj.query_ses(BIDSWS, 'runs', S0filter)     % NB: Assumes all workitems have the same number of runs

                S0data     = obj.query_ses(BIDSWS, 'data',     setfield(S0filter,     'run', char(run)));
                R2stardata = obj.query_ses(BIDSWS, 'data',     setfield(R2starfilter, 'run', char(run)));
                Chidata    = obj.query_ses(BIDSWS, 'data',     setfield(Chifilter,    'run', char(run)));
                maskdata   = obj.query_ses(BIDSWS, 'data',     setfield(maskfilter,   'run', char(run)));
                meta       = obj.query_ses(BIDSWS, 'metadata', setfield(S0filter,     'run', char(run)));
                flips      = cellfun(@getfield, meta, repmat({'FlipAngle'}, size(meta)), "UniformOutput", true);

                % Check the queries workitems
                if numel(unique([length(S0data), length(R2stardata), length(Chidata), length(maskdata)])) > 1
                    obj.logger.exception(sprintf('%s received an ambiguous number of S0maps, R2starmaps, Chimaps or localfmasks:%s', obj.name, ...
                                         sprintf('\n%s', S0data{:}, R2stardata{:}, Chidata{:}, maskdata{:})))
                end
                if length(S0data) < 2
                    obj.logger.exception(sprintf('%s received data for only %d flip angles', obj.name, length(S0data)))
                end
                if length(flips) <= 1
                    obj.logger.exception("Need at least two different flip angles to compute T1 and S0 maps, found:" + sprintf(" %s", flips{:}));
                end

                % Read the QSM images (4th dimension = flip angle)
                V    = spm_vol(S0data{1});                  % Get generic metadata (from any QSM output image)
                S0   = NaN([V.dim(1:3) length(S0data)]);
                R2s  = S0;
                Chi  = S0;
                mask = true;
                for n = 1:length(S0data)
                    S0(:,:,:,n)  = spm_read_vols(spm_vol(S0data{n}));
                    R2s(:,:,:,n) = spm_read_vols(spm_vol(R2stardata{n}));
                    Chi(:,:,:,n) = spm_read_vols(spm_vol(Chidata{n}));
                    mask         = spm_read_vols(spm_vol(maskdata{n})) & mask;
                end

                % Compute and save weighted means of the R2-star & Chi maps. TODO: Change the `desc` value from `VFA\d*` -> `mean`. Also, only compute for ME-VFA data
                R2smean  = sum(S0.^2 .* R2s, 4) ./ sum(S0.^2, 4);
                Chimean  = sum(S0.^2 .* Chi, 4) ./ sum(S0.^2, 4);
                bfileR2s = obj.bfile_set(S0data{1}, obj.bidsfilter.meanR2starmap);
                bfileChi = obj.bfile_set(S0data{1}, obj.bidsfilter.meanChimap);
                spm_write_vol_gz(V, R2smean.*mask, bfileR2s.path);          % TODO: Add JSON sidecar files
                spm_write_vol_gz(V, Chimean.*mask, bfileChi.path);          % TODO: Add JSON sidecar files

                % Compute the R1 and M0 maps using DESPOT1 (based on S0).     TODO: Adapt for using echo data as an alternative to S0
                bfile    = bids.File(S0data{1});                            % TODO: FIXME: Random
                [T1, M0] = despot1_mapping(S0, flips, bfile.metadata.RepetitionTime, mask, B1);     % TODO: Check if we should only use the first two FA (as in MWI_tmp)
                R1       = (mask ./ T1);
                R1(~isfinite(R1)) = 0;          % set NaN and Inf to 0

                % Save the SCR output maps
                bfileR1 = obj.bfile_set(S0data{1}, obj.bidsfilter.R1map_S0);
                bfileM0 = obj.bfile_set(S0data{1}, obj.bidsfilter.M0map_S0);
                spm_write_vol_gz(V, R1,       bfileR1.path);                % TODO: Add JSON sidecar files
                spm_write_vol_gz(V, M0.*mask, bfileM0.path);                % TODO: Add JSON sidecar files

            end
        end

    end

end

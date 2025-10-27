classdef QSMWorker < qb.workers.Worker
%QSMWORKER Runs QSM and R2-star workflows

    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of QSMWorker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end

    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', setfield(bidsfilter.(workitem), 'run',1))`
    end
    
    
    methods

        function obj = QSMWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            %QSMWORKER Constructor for this concrete Worker class

            arguments
                BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
                subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
                config    (1,1) struct = struct()   % Configuration struct loaded from the config TOML file
                workdir   {mustBeTextScalar} = ''
                outputdir {mustBeTextScalar} = ''
                team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
                workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
            end

            % SEPIA should have a directory of its own (we cannot control it's output very well)
            workdir = replace(workdir, "QuIDBBIDS", "SEPIA");
            if ~isempty(workdir) && ~isfolder(workdir)
                bids.init(char(workdir), 'is_derivative', true)
            end

            % Call the abstract parent constructor
            obj@qb.workers.Worker(BIDS, subject, config, workdir, outputdir, team, workitems);

            % Make the abstract properties concrete
            obj.name        = "Kwok";
            obj.description = ["I am your SEPIA expert that can make shiny QSM and R2-star images for you"];
            obj.version     = "0.1.0";
            obj.needs       = ["echos4Dmag", "echos4Dphase", "brainmask"];
            obj.bidsfilter.R2starmap  = struct('modality', 'anat', ...
                                               'echo', [], ...
                                               'part', '', ...
                                               'suffix', 'R2starmap');
            obj.bidsfilter.T2starmap  = setfield(obj.bidsfilter.R2starmap, 'suffix','T2starmap');
            obj.bidsfilter.S0map      = setfield(obj.bidsfilter.R2starmap, 'suffix','S0map');
            obj.bidsfilter.Chimap     = setfield(obj.bidsfilter.R2starmap, 'suffix','Chimap');
            obj.bidsfilter.fieldmap   = setfield(obj.bidsfilter.R2starmap, 'suffix','fieldmap');
            obj.bidsfilter.unwrapped  = setfield(setfield(obj.bidsfilter.R2starmap, 'part','phase'), 'suffix','unwrapped');
            obj.bidsfilter.localfmask = setfield(setfield(obj.bidsfilter.R2starmap, 'label','localfield'), 'suffix','mask');

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

            % Get preprocessed workitems from a colleague
            obj.workdir = replace(obj.workdir, "SEPIA", "QuIDBBIDS");       % SEPIA has it's own directory, temporarily put it back to what it was
            magfiles    = obj.ask_team('echos4Dmag');
            phasefiles  = obj.ask_team('echos4Dphase');
            mask        = obj.ask_team('brainmask');
            obj.workdir = replace(obj.workdir, "QuIDBBIDS", "SEPIA");

            % Check the received workitems
            if length(magfiles) ~= length(phasefiles)
                obj.logger.exception(sprintf('%s got %d magnitude vs %d phase files', obj.name, length(magfiles), length(phasefiles)))
            end
            if length(mask) ~= 1
                obj.logger.warning(sprintf('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', mask{:})))
                entmag = bids.File(magfiles{1}).entities;
                for mask_ = mask
                    entmask = bids.File(char(mask_)).entities;
                    if ( isfield(entmag, 'space') &&  isfield(entmask, 'space') && entmag.space == entmask.space) || ...
                       (~isfield(entmag, 'space') && ~isfield(entmask, 'space'))
                        obj.logger.info("Selecting mask: " + mask_)
                        mask = mask_;
                        break
                    end
                end
            end

            % Process all acquisition protocols, runs and flip angles independently
            for n = 1:length(magfiles)

                % Make sure the magnitude and phase images belong together
                if ~strcmp(magfiles{n}, replace(phasefiles{n}, '_part-phase_','_part-mag_'))
                    obj.logger.exception(sprintf("Magnitude and phase images do not match:\n%s\n%s", magfiles{n}, phasefiles{n}))
                end

                % Create a SEPIA header file
                clear input
                input.nifti         = magfiles{n};                                          % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
                input.TEFileList    = {spm_file(spm_file(magfiles{n}, 'ext',''), 'ext','.json')};                   % Could just be left empty??
                bfile               = obj.bfile_set(magfiles{n}. setfield(obj.bidsfilter.R2starmap), 'suffix','');  % Output basename; SEPIA adds suffixes of its own
                output              = extractBefore(bfile.path,'.');                        % Output path. N.B: SEPIA will interpret the last part of the path as a file-prefix
                save_sepia_header(input, struct('TE', bfile.metadata.EchoTime), output)     % Override SEPIA's TE values with what the bfile says (-> added by spm_file_merge_gz)

                % Get the SEPIA parameters
                switch workitem
                    case fieldnames(obj.config.QSMWorker)
                        param = obj.config.QSMWorker.(workitem);
                    case {"T2starmap", "S0map"}
                        param = obj.config.QSMWorker.("R2starmap");
                    case {"Chimap", "unwrapped", "localfmask"}
                        param = obj.config.QSMWorker.("QSM");
                    otherwise
                        obj.logger.exception(sprintf("%s cannot find the SEPIA parameters for: %s ", obj.name, workitem))
                end

                % Run the SEPIA workflow
                clear input
                input(1).name = phasefiles{n};  % For input().name see SEPIA GUI
                input(2).name = magfiles{n};
                input(3).name = '';
                input(4).name = [output '_header.mat'];
                obj.logger.info(sprintf("--> Running SEPIA %s workflow for %s/%s", workitem, obj.subject.name, obj.subject.session))
                sepiaIO(input, output, char(mask), param)

                % Bluntly rename mask files to make them BIDS valid (bids-matlab fails on the original files)
                for srcmask = dir([output '*_mask_*'])'
                    bname  = extractBefore(srcmask.name,'.');
                    ext    = extractAfter(srcmask.name, '.');
                    source = fullfile(srcmask.folder, srcmask.name);
                    target = fullfile(srcmask.folder, [replace(bname, '_mask_', '_label-') '_mask.' ext]);
                    obj.logger.verbose(sprintf('Renaming %s -> %s', source, target))
                    movefile(source, target)
                end

                % Add a JSON sidecar file for the S0map
                bids.util.jsonencode([output '_S0map.json'], bfile.metadata)

            end
        end

    end

end

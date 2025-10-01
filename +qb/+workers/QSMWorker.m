classdef QSMWorker < qb.workers.Worker
%QSMWORKER Runs QSM and R2-star workflows

    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done (e.g. for GUIs)
        needs       % List of workitems the worker needs
    end


    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `bids.query('data', setfield(bidsfilter.(workitem), 'run',1))`
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
            obj.needs       = ["echos4Dmag", "echos4Dphase", "brainmask"];
            obj.bidsfilter.R2star = struct('sub', obj.sub(), ...
                                           'ses', obj.ses(), ...
                                            'modality', 'anat', ...
                                            'echo', [], ...
                                            'part', '', ...
                                            'desc','FA\d*', ...
                                            'space','withinGRE', ...
                                            'suffix', 'R2starmap');
            obj.bidsfilter.T2star = setfield(obj.bidsfilter.R2star, 'suffix', 'T2starmap');
            obj.bidsfilter.S0     = setfield(obj.bidsfilter.R2star, 'suffix', 'S0map');
            obj.bidsfilter.Chi    = setfield(obj.bidsfilter.R2star, 'suffix', 'Chimap');

            % Fetch the workitems (if requested)
            if strlength(workitems)                             % isempty(string('')) -> false
                for workitem = string(workitems)
                    obj.fetch(workitem);
                end
            end

        end

        function work = get_work_done(obj, workitem)
            %GET_WORK_DONE Does the work to produce the workitem and recruits other workers as needed
            %
            % Inputs:
            %   WORKITEM - Name of the work item that needs to be fetched
            %
            % Output:
            %   WORK     - A cell array of paths to the produced data files. The produced work
            %              can be queried using BIDSFILTERS

            arguments (Input)
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
            end

            arguments (Output)
                work
            end
            
            import qb.utils.spm_file_merge_gz

            % Check the input
            if isempty(obj.subject.anat) || isempty(obj.subject.fmap)
                work = {};
                return
            end

            % Get preprocessed workitems from a colleague
            obj.workdir = replace(obj.workdir, "SEPIA", "QuIDBBIDS");       % SEPIA has it's own directory, temporarily put it back to what it was
            magfiles    = obj.ask_team('echos4Dmag');
            phasefiles  = obj.ask_team('echos4Dphase');
            mask        = obj.ask_team('brainmask');
            obj.workdir = replace(obj.workdir, "QuIDBBIDS", "SEPIA");
            if length(mask) ~= 1    % TODO: FIXME
                obj.logger.exception('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', mask{:}))
            end

            % Process all runs and flip angles independently
            for n = 1:length(magfiles)

                % Get the bids.File info
                bfile  = bids.File(magfiles{n});                            % Also used for constructing the mag-output
                bfile_ = bids.File(phasefiles{n});                          % Just for checking if we have a matching phase image
                if ~strcmp(bfile.filename, replace(bfile_.filename, '_part-phase_','_part-mag_'))
                    obj.logger.exception(sprintf("Magnitude and phase images do not match:\n%s\n%s", bfile.filename, bfile_.filename))
                end

                % Create a SEPIA header file
                clear input
                input.nifti         = magfiles{n};                          % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
                input.TEFileList    = {spm_file(spm_file(bfile.path, 'ext',''), 'ext','.json')};  % Could just be left empty??
                bfile.entities.part = '';                                   % Start constructing the output basename
                bfile.suffix        = '';                                   % SEPIA adds suffixes of its own
                output              = char(fullfile(obj.workdir, bfile.bids_path, extractBefore(bfile.filename,'.')));  % Output path. N.B: SEPIA will interpret the last part of the path as a file-prefix
                save_sepia_header(input, struct('TE', bfile.metadata.EchoTime), output)     % Override SEPIA's TE values with what the bfile says (-> added by spm_file_merge_gz)

                % Get the SEPIA parameters
                switch workitem
                    case {"R2star", "T2star", "S0"}
                        param = "R2star";
                    case {"Chi"}
                        param = "QSM";
                    otherwise
                        obj.logger.exception(sprintf("%s cannot find the parameters for: %s ", obj.name, workitem))
                end

                % Run the SEPIA QSM workflow
                clear input
                input(1).name = phasefiles{n};  % For input().name see SEPIA GUI
                input(2).name = magfiles{n};
                input(3).name = '';
                input(4).name = [output '_header.mat'];
                obj.logger.info(sprintf("--> Running SEPIA %s workflow for %s/%s", workitem, obj.subject.name, obj.subject.session))
                sepiaIO(input, output, char(mask), obj.config.QSMWorker.(param))

                % TODO: Rename/copy all files of interest to become BIDS valid, create sidecar files for them and move them over to obj.outputdir
            end

            % Collect the requested workitem
            BIDSW = bids.layout(char(obj.workdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);
            work  = bids.query(BIDSW, 'data', obj.bidsfilter.(workitem));
        end

    end

end

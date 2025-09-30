classdef (Abstract) Worker < handle
    %WORKER Abstract base class for BIDS data processing workers
    %
    % This class defines the common interface and base functionality for worker
    % classes that operate on data stored in a BIDS repository. Subclasses
    % only need to set some properties and implement the abstract method for
    % producing the work items -- the general workflow is handled by the Manager class.
    %
    % See also: qb.workers.Manager

    properties (Abstract, GetAccess = public, SetAccess = protected)
        name        % Personal name of the worker
        description % Description of the work that is done (e.g. for GUIs)
        needs       % List of workitems the worker needs
        makes       % List of workitems the worker makes, i.e. returned by fetch(workitem)
    end

    properties (Abstract)
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `bids.query('data', setfield(bidsfilter.(workitem), 'run',1))`
    end

    properties (GetAccess = public, SetAccess = protected)
        usesGPU     % Logical flag indicating if the worker can use GPU resources. Default = false
    end

    properties
        BIDS        % BIDS layout from bids-matlab (raw input data only)
        subject     % The subject that will be worked on 
        config      % Configuration settings that are used to produce the work
        workdir
        outputdir
        team        % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker resume
        logger      % A logger object for keeping logs
    end


    methods (Abstract)

        work = get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work done for the workitem and recruits other workers as needed
        %
        % arguments (Input)
        %     obj
        %     workitem {mustBeTextScalar}   % Name of the work item that needs to be fetched
        % end
        %
        % arguments (Output)
        %     work                          % A cell array of paths to the produced data files
        % end

    end


    methods

        function obj = Worker(BIDS, subject, config, workdir, outputdir, team, workitems)
            %WORKER Constructor for abstract Worker class

            arguments
                BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
                subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
                config    (1,1) struct = struct()   % Configuration struct loaded from the config TOML file
                workdir   {mustBeTextScalar} = ''
                outputdir {mustBeTextScalar} = ''
                team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
                workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
            end

            obj.BIDS      = BIDS;
            obj.subject   = subject;
            obj.config    = config;
            obj.workdir   = workdir;
            obj.outputdir = outputdir;
            obj.team      = team;
            obj.usesGPU   = false;
            obj.logger    = qb.workers.Logging(obj);

        end

        function work = fetch(obj, workitem, force)
            %FETCH Gets the workitem.
            %
            % FETCH first tries to collect the workitem but if it doesn't exist then locks the work
            % folder, gets the work done (-> obj.get_work_done()), unlocks it and write a done-file.
            %
            % For your convenience, an explicit fetch_[workitem]() interface may also be exposed.
            %
            % Inputs:
            %   WORKITEM - Name of the work item that needs to be fetched
            %
            % Output:
            %   WORK     - A cell array of paths to the produced data files. The produced work
            %              can be queried using BIDSFILTERS

            arguments
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
                force    logical = false
            end

            % (Re)index the workdir layout
            BIDS = bids.layout(char(obj.workdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);     %#ok<PROPLC>
            work = bids.query(BIDS, 'data', [{'sub',obj.subject.name, 'ses',obj.subject.session}, obj.bidsfilter.(workitem)]);                                      %#ok<PROPLC>
            if isempty(work)
                obj.logger.info(sprintf("==> %s has started working on: %s", obj.name, obj.subject.path))
                if obj.is_locked(true)
                    if force
                        obj.logger.warning(sprintf("%s will do work on %s but it was locked", obj.name, obj.subject.path))
                    else
                        obj.logger.error(sprintf("%s wants to do work on %s but it was locked", obj.name, obj.subject.path))
                        return
                    end
                end
                % TODO: update the dashboard (non-HPC usage)
                obj.lock()
                work = obj.get_work_done(workitem);     % Get the worker to work
                obj.unlock()
                % TODO: update the dashboard (non-HPC usage)
                if ~isempty(work)
                    obj.done()
                    obj.logger.info(obj.name + " has finished working on: " + obj.subject.path)
                else
                    obj.logger.error(sprintf("%s could not produce the requested %s item", obj.name, workitem))
                end
            end

        end

        function work = ask_colleague(obj, workitem)
            %ASK_COLLEAGUE Asks a team member to fetch a WORKITEM needed to get work done

            arguments
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
            end

            colleague = obj.team(workitem).handle(obj.subject, obj.BIDS, obj.team);
            work      = colleague.fetch(workitem);

        end

        function locker = is_locked(obj, verbose)
            % Returns the content of the lockfile (if it exists)

            arguments
                obj     qb.workers.Worker
                verbose (1,1) logical = false
            end

            lock_file = [obj.workerpath() '_worker.lock'];
            if isfile(lock_file)
                locker = fileread(lock_file);
                if verbose
                    disp(locker)
                end
            else
                locker = '';
            end
        end

        function lock(obj)
            % Write a lock file to indicate the work has started
            %
            % In this way we avoid concurrency issues and we can use qsubfeval instead
            % of qsubcellfun (which has job-status issues)

            lock_file = [obj.workerpath() '_worker.lock'];
            obj.logger.verbose("Locking: " + lock_file)
            [~,~]     = mkdir(fileparts(lock_file));
            fid = fopen(lock_file, 'w');
            if fid ~= -1
                fprintf(fid, "Locked for %s by %s on %s\n", class(obj), getenv('USERNAME'), datetime('now'));
                fclose(fid);
            else
                obj.logger.exception(sprintf("%s could not lock %s", obj.name, lock_file))
            end
        end

        function unlock(obj)
            % Remove the lock file to indicate the work has stopped
            lock_file = [obj.workerpath() '_worker.lock'];
            obj.logger.verbose("Unlocking: " + lock_file)
            if isfile(lock_file)
                delete(lock_file);
            end
        end

        function done = is_done(obj, verbose)
            % Returns the content of the done-file (if it exists)

            arguments
                obj     qb.workers.Worker
                verbose (1,1) logical = false
            end

            done_file = [obj.workerpath() '_worker.done'];
            if isfile(done_file)
                done = fileread(done_file);
                if verbose
                    disp(done)
                end
            else
                done = '';
            end
        end

        function done(obj)
            % Write a done-file to indicate the work has finished successfully
            done_file = [obj.workerpath() '_worker.done'];
            fid = fopen(done_file, 'a');
            if fid ~= -1
                fprintf(fid, "%s work was done by %s on %s\n", class(obj), getenv('USERNAME'), datetime('now'));
                fclose(fid);
            else
                obj.logger.error(sprintf("%s could not write a done-file in %s", obj.name, done_file))
            end
        end

        function [status, output] = run_command(obj, command, silent)
            %RUN_COMMAND Executes a shell command and display its output.
            %
            %   [STATUS, OUTPUT] = RUN_COMMAND(COMMAND) prints the specified shell
            %   COMMAND to the console, executes it using SYSTEM(), and returns the
            %   STATUS and OUTPUT.
            %
            %   If the command fails (i.e., STATUS ~= 0), an error is raised with
            %   a message containing the exit status and the command's output.
            %
            %   Inputs:
            %       COMMAND - A string containing the shell command to execute.
            %       SILENT  - If true, suppress output unless there is an error.
            %                 Default = false.
            %
            %   Outputs:
            %       STATUS  - Exit code returned by the SYSTEM command.
            %       OUTPUT  - Command-line output returned by the SYSTEM command.

            arguments
                obj
                command {mustBeTextScalar, mustBeNonempty}
                silent  (1,1) logical = false
            end

            % Run the command
            if ~silent
                obj.logger.info("$ " + command)
            end
            [status, output] = system(command);

            % Check for errors
            if status ~= 0
                obj.logger.error(sprintf('Command failed with status %d\nOutput:\n%s', status, output));
            elseif ~silent && ~isempty(output)
                obj.logger.info(output)
            end
        end

    end


    methods (Static)

        function bfile = update_bfile(bfile, specs)
            %UPDATE_BFILE Updates the BFILE (-> bids.File()) paths, entities and suffix with the values from SPECS

            arguments
                bfile (1,1) bids.File
                specs (1,1) struct = struct()
            end

            % Go over the specs fields and update the bfile
            oldfname = bfile.filename;          % Store for later use
            oldjname = bfile.json_filename;     % Store for later use
            for field = fieldnames(specs)'
                if strcmp(field{1}, 'suffix')
                    bfile.suffix = specs.suffix;
                else
                    bfile.entities.(field{1}) = specs.(field{1});
                end
            end
            
            % Paths are not updated automatically, so do that manually
            bfile.path           = replace(bfile.path,           oldfname, bfile.filename);
            bfile.metadata_files = replace(bfile.metadata_files, oldjname, bfile.json_filename);
        end

    end

    methods (Access = private)

        function pth = workerpath(obj)
            %WORKERPATH Replaces the subject.path with the workdir path and appends a subdirectory named after the worker
            pth = fullfile(replace(obj.subject.path, obj.BIDS.pth, obj.workdir), regexp(class(obj), '[^.]+$', 'match', 'once'));  % Only take the class basename, i.e. the last part after the dot
        end

    end

end

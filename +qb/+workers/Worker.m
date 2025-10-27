classdef (Abstract) Worker < handle
    %WORKER Abstract base class for BIDS data processing workers
    %
    % This class defines the common interface and base functionality for worker
    % classes that operate on data stored in a BIDS repository. Subclasses
    % only need to set some properties and implement the abstract method for
    % producing the work items -- the general workflow is handled by the Manager class.
    %
    % Note that all Workers are handle classes that copy by reference, not by value
    %
    % See also: qb.workers.Manager

    properties (Abstract, GetAccess = public, SetAccess = protected)
        name        % Personal name of the worker
        description % Description of the work that is done
        version     % The semantic version of the worker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end

    properties (Abstract)
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout_workdir, 'data', setfield(bidsfilter.(workitem), 'run',1))`
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

        get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work done for the WORKITEM and recruits other workers as needed

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

        function workitems = makes(obj)
            workitems = fieldnames(obj.bidsfilter)';
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
            %   FORCE    - Force to start working, even if the subject is locked or existing results exist
            %
            % Output:
            %   WORK     - A cell array of paths to the produced data files. The produced work
            %              can be queried using BIDSFILTERS

            arguments
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
                force    logical = false
            end

            % Check the input
            if ~ismember(workitem, obj.makes())
                obj.logger.error(sprintf("Tell the manager that %s does not know what a %s workitem is", obj.name, workitem))
                work = {};
                return
            end

            % See if we can collect the requested workitem
            work = obj.query_ses(obj.layout_workdir(), 'data', obj.bidsfilter.(workitem));
            if isempty(work) || force

                obj.logger.info(sprintf("==> %s has started %s work on: %s", obj.name, workitem, obj.subject.path))
                locked = obj.is_locked();
                if locked
                    if force
                        obj.logger.warning(sprintf("Work will be done on %s but it was: %s", fileparts(obj.statusfile('.lock')), locked))
                    else
                        obj.logger.error(sprintf("%s was: %s", fileparts(obj.statusfile('.lock')), locked))
                        return
                    end
                end
                
                % TODO: update the dashboard (non-HPC usage)
                
                % Get the work done
                cleanup = onCleanup(@() obj.unlock());
                obj.lock()
                obj.get_work_done(workitem);     % This is where all the concrete methods are implemented

                % TODO: update the dashboard (non-HPC usage)
                
                % Collect the requested workitem
                work = obj.query_ses(obj.layout_workdir(), 'data', obj.bidsfilter.(workitem));
                if ~isempty(work)
                    obj.done()
                    obj.logger.info(obj.name + " has finished working on: " + obj.subject.path)
                else
                    obj.logger.error(sprintf("%s could not produce the requested %s item (%s/%s)", obj.name, workitem, obj.subject.name, obj.subject.session))
                end
                
            else
                obj.logger.info(sprintf("%s fetched %d requested %s items (%s/%s)", obj.name, length(work), workitem, obj.subject.name, obj.subject.session))
            end

            % Make sure that the work exists
            for item = work
                if ~isfile(item)
                    obj.logger.exception(sprintf('%s said he made %s but it does not exist', obj.name, item))
                end
            end
        end

        function [work, bidsfilter] = ask_team(obj, workitem)
            %ASK_TEAM Asks a team member to fetch a (regexp) WORKITEM needed to get the work done

            arguments
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
            end

            % See if someone in the team can make a matching workitem
            workitems = fieldnames(obj.team)';
            match     = ~cellfun(@isempty, regexp(workitems, "^" + workitem + "$"));
            if ~any(match)
                obj.logger.exception(sprintf("%s asked for a %s workitem but nobody in the team knows what that is", obj.name, workitem))
            elseif sum(match) ~= 1
                obj.logger.exception('%s asked for a %s workitem but got multiple answers:%s', sprintf(' %s', workitems{match}))
            end

            % resolve the regexp workitem
            workitem   = workitems{match};

            % Put the coworker to work
            obj.logger.info(sprintf("%s asks for %s workitem(s)", obj.name, workitem))
            coworker   = obj.team.(workitem).handle(obj.BIDS, obj.subject, obj.config, obj.workdir, obj.outputdir, obj.team);
            work       = coworker.fetch(workitem);
            bidsfilter = coworker.bidsfilter.(workitem);

        end

        function locker = is_locked(obj, verbose)
            % Returns the content of the lockfile (if it exists)

            arguments
                obj     qb.workers.Worker
                verbose (1,1) logical = false
            end

            lock_file = obj.statusfile('.lock');
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

            lock_file = obj.statusfile('.lock');
            obj.logger.verbose("Locking: " + lock_file)
            [~,~]     = mkdir(fileparts(lock_file));
            fid = fopen(lock_file, 'w');
            if fid ~= -1
                fprintf(fid, "Locked for %s by %s on %s", class(obj), getenv('USERNAME'), datetime('now'));
                fclose(fid);
            else
                obj.logger.exception(sprintf("%s could not lock %s", obj.name, lock_file))
            end
        end

        function unlock(obj)
            % Remove the lock file to indicate the work has stopped
            lock_file = obj.statusfile('.lock');
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

            done_file = obj.statusfile('.done');
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
            done_file = obj.statusfile('.done');
            fid = fopen(done_file, 'a');
            if fid ~= -1
                fprintf(fid, "%s work was done by %s on %s\n", class(obj), getenv('USERNAME'), datetime('now'));
                fclose(fid);
            else
                obj.logger.error(sprintf("%s could not write a done-file in %s", obj.name, done_file))
            end
        end

        function label = sub(obj)
            %SUB Gets the sub-label from the subject data-structure
            label = strsplit(obj.subject.name, '-');
            label = label{end};
            if isempty(label)
                obj.logger.warning(sprintf('Subject label could not be determined from subject.name: %s', obj.subject.name))
            end
        end

        function label = ses(obj)
            %SES Gets the ses-label from the subject data-structure
            label = strsplit(obj.subject.session, '-');
            label = label{end};
        end

        function BIDSW = layout_workdir(obj, workdir)
            %LAYOUT_WORKDIR Gets a tolerant bids.layout() for the sub/ses WORKDIR (default: obj.workdir)

            if nargin < 2 || isempty(workdir)
                workdir = obj.workdir;
            end
            BIDSW = bids.layout(char(workdir), 'filter', struct('sub',obj.sub(), 'ses',obj.ses()), ...
                                'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);
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

        function result = query_ses(obj, layout, query, varargin)
            %QUERY_SES A thin wrapper around bids.query that adds an additional filter for the current subject and session
            %
            % Inputs:
            %   LAYOUT - BIDS directory name or BIDS structure (from bids.layout) to query
            %   QUERY  - The type of query to perform (e.g., 'data', 'metadata', 'runs', etc.)
            %   FILTER - (optional) A struct or name-value pairs specifying additional filters for the query
            %
            % Output:
            %   RESULT - The result of the bids.query with the subject/session filter applied. NB: always a row cell array
            %
            % Usage:
            %   RESULT = QUERY_SES(LAYOUT, QUERY, [FILTER])
            %   RESULT = QUERY_SES(LAYOUT, QUERY, struct('name1', value1, 'name2', value2, ...))
            %   RESULT = QUERY_SES(LAYOUT, QUERY, 'name1', value1, 'name2', value2, ...)
            %
            % See also: bids.query

            % Parse the filter input
            if isempty(varargin) || ~isscalar(varargin)
                bfilter = struct(varargin{:});
            elseif isstruct(varargin{1})
                bfilter = varargin{1};
            else
                obj.logger.exception('QUERY_SES expects the FILTER to be a struct or name-value pairs');
            end

            % Do the query with the subject/session filter added
            result = bids.query(layout, query, setfield(setfield(bfilter, 'sub',obj.sub()), 'ses',obj.ses()));

            % Always return a row cell array
            if size(result,2)==0 || size(result,1)>1
                result = result';
            end
        end

        function bfile = bfile_set(obj, bfile, specs, rootdir)
            %BFILE_SET Update a BIDS file's path, entities, and suffix.
            %
            %   BFILE = OBJ.BFILE_SET(BFILE, SPECS, ROOTDIR) updates the entities,
            %   suffix, and file paths of a BIDS file according to the fields provided
            %   in the SPECS structure.
            %
            %   Inputs:
            %       BFILE   - Either a bids.File object or a character/string path to a
            %                 BIDS-formatted file. If a path is provided, it is converted
            %                 internally to a bids.File object.
            %       SPECS   - (optional) A structure specifying entity/suffix/modality names
            %                 and values to update in the BIDS filename. Default = struct()
            %       ROOTDIR - (optional) New root directory to replace the existing one.
            %                 If omitted or empty, the root directory is replaced with
            %                 OBJ.WORKDIR.
            %
            %   Example:
            %       specs = struct('acq','demo', 'run',1, 'suffix','M0map');
            %       root  = 'P:\workdir';
            %       bfile = bids.File('P:\rawdir\sub-004\anat\sub-004_acq-fl3d_MEGRE.nii.gz');
            %       bfile = obj.bfile_set(bfile, specs, root);
            %
            %       % Result:
            %       %   bfile.path = 'P:\workdir\sub-004\anat\sub-004_acq-demo_run-1_M0map.nii.gz'
            %
            %   See also: bids.File
            
            arguments
                obj
                bfile   (1,1) {mustBeA(bfile, {'bids.File','char','string'})}
                specs   (1,1) struct = struct()
                rootdir {mustBeTextScalar} = ''
            end

            % Parse the input arguments
            if ischar(bfile) || isstring(bfile)
                bfile = bids.File(char(bfile));
            end
            if ~strlength(rootdir)
                rootdir = obj.workdir;
            end

            % Go over the specs fields and update the bfile
            oldfname = bfile.filename;          % Store for later use
            oldjname = bfile.json_filename;     % Store for later use
            for field = fieldnames(specs)'
                value = specs.(char(field));
                if ~isempty(value)              % Convert to numerical values to string, but not []
                    value = string(value);
                end
                if ismember(field, ["suffix", "modality"])
                    bfile.(char(field)) = char(value);
                else
                    bfile.entities.(char(field)) = char(value);
                end
            end
            
            % Paths are not updated automatically with the new filename, so do that manually
            bfile.path           = replace(bfile.path,           oldfname, bfile.filename);
            bfile.metadata_files = replace(bfile.metadata_files, oldjname, bfile.json_filename);

            % Replace the rootdir (e.g. rawdir -> rootdir)
            if strlength(rootdir)
                oldroot              = extractBefore(bfile.path, bfile.bids_path);  % Ends with filesep
                bfile.path           = replace(bfile.path,           oldroot, fullfile(rootdir, filesep));
                bfile.metadata_files = replace(bfile.metadata_files, oldroot, fullfile(rootdir, filesep));
            end
        end

    end

    methods (Access = private)

        function pth = statusfile(obj, ext)
            %WORKERPATH Returns a workdir statusfile named after the worker
            pth = fullfile(replace(obj.subject.path, obj.BIDS.pth, obj.workdir), [regexp(class(obj), '[^.]+$', 'match', 'once') ext]);  % Only take the class basename, i.e. the last part after the dot
        end

    end

end

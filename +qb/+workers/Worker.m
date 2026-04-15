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


properties (Abstract, Constant)
    description     % Description of the work that is done
    needs           % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU         % Logical flag indicating if the worker can use GPU resources
end


properties (GetAccess = public, SetAccess = protected)
    name            % Basename of the worker
end


properties
    BIDS            % BIDS layout from bids-matlab (raw input data only)
    subject         % The subject that will be worked on
    config          % Configuration settings that are used to produce the work
    workdir         % Working directory for intermediate files
    outputdir       % Output directory for final results
    team            % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker resume
    force           % Force to start working, even if the subject is locked or existing results exist
    bidsfilter      % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(BIDSW_ses, 'data', bidsfilter.(workitem), run=1)`
    logger          % A logger object for keeping logs
end


methods (Abstract, Access = protected)

    initialize(obj)
    %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
    % subclasses to perform additional setup after the common Worker properties have been initialized.

end


methods (Abstract)

    get_work_done(obj, workitem)
    %GET_WORK_DONE Does the work done for the WORKITEM and recruits other workers as needed

end


methods

    function obj = Worker(BIDS, subject, config, workdir, outputdir, team, force, workitems)
        % Constructor for the abstract Worker class

        arguments
            BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
            subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
            config    (1,1) struct = struct()   % Configuration struct loaded from the config file
            workdir   {mustBeTextScalar} = ''   % Working directory for intermediate files
            outputdir {mustBeTextScalar} = ''   % Output directory for final results
            team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
            force     (1,1) logical = false     % Force to start working, even if the subject is locked or existing results exist
            workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
        end

        obj.BIDS      = BIDS;
        obj.subject   = subject;
        obj.config    = obj.flatvalues(config); % Replace struct("value", VALUE, "description", DESCRIPTION) leaves with their VALUE
        obj.workdir   = workdir;
        obj.outputdir = outputdir;
        obj.team      = team;
        obj.force     = force;
        obj.name      = string(erase(class(obj), 'qb.workers.'));  % Get the class name without package prefix
        obj.logger    = qb.workers.Logging(obj);

        % Restore rng settings because spm_coreg uses a legacy random number generator that crashes e.g. mwi_3cx_2R1R2s_dimwi
        if strcmpi(RandStream.getGlobalStream().Type, 'legacy')
            rng('default')
        end

        % Force subclass-specific construction step
        obj.initialize()

        % Make the workitems (if requested)
        if strlength(workitems)                 % isempty(string('')) -> false
            for workitem = string(workitems)
                obj.fetch(workitem);
            end
        end
    end

    function workitems = makes(obj)
        workitems = string(fieldnames(obj.bidsfilter)');
        if isempty(workitems)
            obj.logger.warning('%s does not seem to make anything!', obj.name)
        end
    end

    function work = fetch(obj, workitem)
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
        end

        % Check the input
        if ~ismember(workitem, obj.makes())
            obj.logger.error("Tell the manager that %s does not know what a %s workitem is", obj.name, workitem)
            work = {};
            return
        end

        % See if we can collect the requested workitem
        work = obj.query_ses(obj.BIDSW_ses(), 'data', obj.bidsfilter.(workitem));
        if isempty(work) || obj.force

            obj.logger.info("==> %s has started %s work on: %s", obj.name, workitem, obj.subject.path)

            % Check if the subject is already being worked on
            locked = obj.is_locked();
            if locked
                if obj.force
                    obj.logger.warning("Work will be done on %s but it was: %s", fileparts(obj.statusfile('.lock')), locked)
                else
                    obj.logger.error("%s was: %s", fileparts(obj.statusfile('.lock')), locked)
                    return
                end
            end

            % Check if there is a GPU available
            if obj.usesGPU
                if canUseGPU()
                    try
                        obj.logger.info("%s is set-up to use GPU: %s (%s)", obj.name, gpuDevice().Name, gpuDevice().ComputeCapability)
                    catch ME
                        obj.logger.warning("%s\n%s", getReport(ME))
                        validateGPU
                    end
                else
                    [status, out] = system('nvidia-smi --query-gpu=name --format=csv,noheader');
                    reason = 'but GPU acceleration is unavailable';
                    if status == 0 && ~isempty(strtrim(out))
                        reason = ['and the GPU was detected (' strtrim(out) '), but MATLAB cannot use it'];
                    end
                    obj.logger.error(['%s was configured to use a GPU, %s. Possible causes: no GPU allocated by the scheduler, incompatible ' ...
                                      'CUDA/driver, or missing Parallel Computing Toolbox license.'], obj.name, reason)
                end
            end

            % Store the matlab path (to avoid issues with workers that change the path, e.g. SEPIA) and restore it at the end of the work
            if ~isdeployed
                mpath   = path();
                restore = onCleanup(@() path(mpath));
            end
            [lastMsg, lastId] = lastwarn;   % Also store the last warning for ignoring certain annoying warnings

            % Get the work done
            cleanup = onCleanup(@obj.unlock);
            obj.lock()
            obj.get_work_done(workitem);     % This is where all the concrete methods are implemented

            % Restore rng settings because spm_coreg uses a legacy random number generator that crashes e.g. mwi_3cx_2R1R2s_dimwi
            if strcmpi(RandStream.getGlobalStream().Type, 'legacy')
                rng('default')
            end

            % Ignore the SPM setting random 'state' and the SEPIA rmpath warnings (-> lastwarn is displayed by qsubget())
            [~, newId] = lastwarn;
            if ismember(newId, {'MATLAB:RandStream:ActivatingLegacyGenerators', 'MATLAB:rmpath:DirNotFound', 'MATLAB:MKDIR:DirectoryExists'})
                lastwarn(lastMsg, lastId)
            end

            % Collect the requested workitem
            work = obj.query_ses(obj.BIDSW_ses(), 'data', obj.bidsfilter.(workitem));
            if ~isempty(work)
                obj.done()
                obj.logger.info(obj.name + " has finished working on: " + obj.subject.path)
            else
                obj.logger.error("%s could not produce the requested %s item (%s/%s)", obj.name, workitem, obj.subject.name, obj.subject.session)
            end

        else
            obj.logger.info("%s fetched %d requested %s item(s) (%s/%s)", obj.name, length(work), workitem, obj.subject.name, obj.subject.session)
        end

        % Make sure that the work exists
        for item = work
            if ~isfile(item)
                obj.logger.exception('%s said he made %s but it does not exist', obj.name, item)
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
            obj.logger.exception("%s asked for a %s workitem but nobody in the team knows what that is", obj.name, workitem)
        elseif sum(match) ~= 1
            obj.logger.exception('%s asked for a %s workitem but got multiple answers:%s', sprintf(' %s', workitems{match}))
        end

        % resolve the regexp workitem
        workitem   = workitems{match};

        % Put the coworker to work
        obj.logger.info("%s asks for %s workitem(s)", obj.name, workitem)
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
            fprintf(fid, "Locked for %s by %s on %s", class(obj), char(java.lang.System.getProperty('user.name')), datetime('now'));
            fclose(fid);
        else
            obj.logger.exception("%s could not lock %s", obj.name, lock_file)
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
            fprintf(fid, "%s work was done by %s on %s\n", class(obj), char(java.lang.System.getProperty('user.name')), datetime('now'));
            fclose(fid);
        else
            obj.logger.error("%s could not write a done-file in %s", obj.name, done_file)
        end
    end

    function label = sub(obj)
        %SUB Gets the sub-label from the subject data-structure
        label = strsplit(obj.subject.name, '-');
        label = label{end};
        if isempty(label)
            obj.logger.warning('Subject label could not be determined from subject.name: %s', obj.subject.name)
        end
    end

    function label = ses(obj)
        %SES Gets the ses-label from the subject data-structure
        label = strsplit(obj.subject.session, '-');
        label = label{end};
    end

    function subses = sub_ses(obj)
        % Parses the sub-#_ses-# prefix from a BIDS.subjects item
        subses = replace(erase(obj.subject.path, [obj.BIDS.pth filesep]), filesep,'_');
    end

    function BIDSW = BIDSW_ses(obj, workdir)
        %BIDSW_SES Gets a tolerant bids.layout() for the WORKDIR sub/ses data only (default: WORKDIR = obj.workdir)
        %
        % Waits up to 60 seconds for the workdir BIDS initialization to be ready, allowing the HPC file system latency to settle

        if nargin < 2 || isempty(workdir)
            workdir = obj.workdir;
        end
        
        % Check for the BIDS layout to be ready (HPC file system latency workaround)
        start = tic;
        while ~isfile(fullfile(workdir, 'dataset_description.json')) && toc(start) < 60
            pause(5);
        end
        if toc(start) >= 60
            obj.logger.warning('BIDS layout %s did not become available within 60 seconds', workdir)
        end

        % Make sure the sub/ses dir exists or bids.layout will error
        filter.sub = {obj.sub()};
        subsesdir  = "sub-" + obj.sub();
        if obj.ses()
            filter.ses = {obj.ses()};
            subsesdir  = fullfile(subsesdir, "ses-" + obj.ses());
        end
        [~,~] = mkdir(fullfile(workdir, subsesdir));        

        BIDSW = bids.layout(char(workdir), 'filter',filter, 'use_schema',false, 'index_derivatives',false, 'tolerant',true, 'verbose',false);
    end

    function [result, bfiles] = query_ses(obj, layout, query, varargin)
        %QUERY_SES A thin wrapper around bids.query that adds an additional filter for the current subject and session. It
        % also ensures that the output is always formatted as a row.
        %
        % Inputs:
        %   LAYOUT - BIDS directory name or BIDS structure (from bids.layout) to query
        %   QUERY  - The type of query to perform (e.g., 'data', 'metadata', 'runs', etc.)
        %   FILTER - (optional) Either a struct, named-values, or name-value pairs specifying additional filters for the
        %            query (i.e. as in bids.query), or a struct followed by the name-value pairs. It's possible to use
        %            regular as well as range expressions in the queried values. To exclude an entity, use '' or [].
        %
        % Output:
        %   RESULT - The result of the bids.query with the subject/session filter applied. NB: always a row cell array
        %   BFILES - The associated bids.File objects. NB: For this to work, QUERY must be 'data'
        %
        % Usage:
        %   RESULT = OBJ.QUERY_SES(LAYOUT, QUERY, [FILTER])
        %   RESULT = OBJ.QUERY_SES(LAYOUT, QUERY, struct(name1=value1, name2=value2, ...))
        %   RESULT = OBJ.QUERY_SES(LAYOUT, QUERY, 'name1', value1, 'name2', value2, ...)
        %   RESULT = OBJ.QUERY_SES(LAYOUT, QUERY, struct(name1=value1), name2=value2, ...)
        %
        % See also: bids.query

        % Parse the filter input
        bfilter = struct();
        if ~isempty(varargin) && isstruct(varargin{1})
            bfilter = varargin{1};
            varargin(1) = [];
        end
        if mod(length(varargin),2) ~= 0
            obj.logger.exception('QUERY_SES expects the FILTER to be either a struct, or name-value pairs or a struct followed by name-value pairs')
        end

        % Check if there is any data to query
        if ~isfield(layout, 'subjects') || ~isfield(layout.subjects, 'name') || ~ismember(obj.subject.name, {layout.subjects.name})
            result = {};
            bfiles = {};
            return
        end

        % Do the query with the subject/session + any additional filters added
        result = bids.query(layout, query, qb.utils.setfields(bfilter, 'sub',obj.sub(), 'ses',obj.ses(), varargin{:}));

        % Postprocess the query result (i.e. fix the quirky bids.query behavior)
        switch query
            case {'metadata', 'dependencies'}
                if isscalar(result) && ~iscell(result)
                    result = {result};  % Always return a cell array
                end
        end
        if size(result,2)==0 || size(result,1)>1
            result = result';           % Always return a row array
        end

        if nargout > 1
            bfiles = cell(size(result));
            if strcmp(query, 'data')
                for n = 1:numel(result)
                    bfiles{n} = bids.File(result{n});
                end
            else
                obj.logger.warning("The BFILES output can only be used with queries for 'data', not with queries for '%s'", query)
            end
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
        %       BFILE   - Either a bids.File object or a cell/string/character path to a
        %                 BIDS-formatted file. If a path is provided, it is converted
        %                 internally to a bids.File object.
        %       SPECS   - (optional) A structure specifying entity/suffix/modality names
        %                 and values to update in the BIDS filename. Default = struct()
        %       ROOTDIR - (optional) New root directory to replace the existing one.
        %                 If omitted or empty, the root directory is replaced with
        %                 OBJ.WORKDIR.
        %
        %   Example:
        %       specs = struct(acq='demo', run=1, suffix='M0map');
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
            bfile   {mustBeA(bfile, {'bids.File','char','string','cell'})}
            specs   (1,1) struct = struct()
            rootdir {mustBeTextScalar} = ''
        end

        % Parse the input arguments
        if ischar(bfile) || isstring(bfile) || iscellstr(bfile)
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
            obj.logger.error('Command failed with status %d\nOutput:\n%s', status, output)
        elseif ~silent && ~isempty(output)
            obj.logger.info(output)
        end
    end

end

methods (Access = private)

    function pth = statusfile(obj, ext)
        %WORKERPATH Returns a workdir statusfile named after the worker
        pth = fullfile(replace(obj.subject.path, obj.BIDS.pth, obj.workdir), obj.name + ext);
    end

    function config = flatvalues(obj, config)
        %FLATVALUES Recursively walks over the tree and replaces the struct("value",VAL, "description",DESC) leaves with VAL

        % Replace the leaf or recurse into each field
        if isfield(config, 'value') && isfield(config, 'description') && numel(fieldnames(config)) == 2
            config = config.value;
        elseif isstruct(config)     % NB: The check is needed when Workers initialize other Workers (with an already flattened config)
            for field = fieldnames(config)'
                config.(field{1}) = obj.flatvalues(config.(field{1}));
            end
        end
    end

end

end

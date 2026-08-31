classdef (Abstract) Coordinator < handle
%Coordinator Abstract base class for building a BIDS app control center (e.g. with a GUI to edit the CONFIG property)
%
% The manager doesn't know how the data is organized and needs assistance from the coordinator


properties
    BIDS                    % BIDS layout object from bids-matlab
    outputdir               % BIDSApp derivatives subdirectory where the output is stored
    workdir                 % Working directory for intermediate results
    deliverables            % The end products (workitems) requested by the user, for full list of possible deliverables, see obj.catalog()
    resumes                 % The resumes of all available workers
    config                  % Configuration struct loaded from the config file
    configfile              % Path to the configuration file
    workflowfile            % Path to the workflow file
    glossary = struct()     % Glossary struct loaded from the glossary.json file
    metadata = struct()     % A struct with metadata about the software package
end


methods (Abstract)
    config = get_config(obj, config)   % Reads CONFIG from the configuration file or writes to it if CONFIG is given
end


methods

    function obj = Coordinator(BIDS, outputdir, workdir, configfile)
        % Constructor for the abstract Coordinator class
        %
        % Inputs:
        %   BIDS       - BIDS layout object from bids-matlab
        %   OUTPUTDIR  - Path to the derivatives bidsapp subdirectory where output will be written
        %   WORKDIR    - Working directory for intermediate results. Default: outputdir/[APPNAME]_work
        %   CONFIGFILE - Path to a configuration file with workflow settings

        % Load existing workflow data
        obj.load_workflow()

        % Parse the inputs
        bidsapp = regexp(class(obj), '[^.]+$', 'match', 'once');  % Only take the class basename, i.e. the last part after the dot
        if isempty(outputdir) || strlength(outputdir) == 0
            if char(obj.outputdir)
                outputdir = string(obj.outputdir);
            else
                outputdir = fullfile(BIDS.pth, "derivatives", bidsapp);
            end
        end
        if isempty(workdir) || strlength(workdir) == 0
            if char(obj.workdir)
                workdir = string(obj.workdir);
            else
                workdir = fullfile(BIDS.pth, "derivatives", bidsapp + "_work");
            end
        end
        if isempty(configfile) || strlength(configfile) == 0
            configfile = string(obj.configfile);
        end

        % Initialize the derivatives and workdir datasets
        if ~isfile(fullfile(outputdir, 'dataset_description.json'))
            bids.init(char(outputdir), 'is_derivative', true)
        end
        if ~isfile(fullfile(workdir, 'dataset_description.json'))
            bids.init(char(workdir), 'is_derivative', true)
        end

        % Set the properties
        obj.BIDS         = BIDS;
        obj.outputdir    = outputdir;
        obj.workdir      = workdir;
        obj.configfile   = configfile;
        obj.workflowfile = regexprep(obj.configfile, "(.*)config(.*)\.json$", "$1workflow$2.mat");
        obj.config       = obj.get_config();
        obj.resumes      = obj.get_resumes();
        obj.deliverables = "";      % NB: This has to be called after get_resumes() because set.deliverables() needs to know the workitems
        glossfile = fullfile(fileparts(mfilename('fullpath')), 'glossary.json');
        if isfile(glossfile)
            obj.glossary = jsondecode(fileread(glossfile));
        end
    end

    function set.deliverables(obj, val)
        % Check if the deliverable exist and force anything assigned to be stored as a string row
        for product = string(val(:)')
            if product~="" && all(cellfun(@isempty, regexp(obj.catalog(), "^" + product + "$")))
                warning("QuIDBBIDS:Deliverables:Ambiguous", 'The "%s" deliverable was not found, it must match any of:%s', product, sprintf(' "%s"', obj.catalog()))
                return
            end
        end
        obj.deliverables = string(val(:)');
        obj.deliverables(obj.deliverables=="") = [];
    end

    function choose_products(obj)
        % TODO: Implement a GUI to choose the deliverables interactively
        obj.deliverables = qb.ChooseProducts(obj.resumes);
    end

    function items = catalog(obj)
        %CATALOG Gets or displays a list of all the workitems the workers can make

        makes = [];
        for worker = string(fieldnames(obj.resumes))'
            makes = [makes, obj.resumes.(worker).makes];       %#ok<AGROW>
        end
        if nargout
            items = unique(makes);
        else
            for item = unique(makes)
                if isfield(obj.glossary, item)
                    description = obj.glossary.(item);
                elseif endsWith(item, "_ortho")
                    description = sprintf('A 2D montage with 3 orthogonal (QC) slices of "%s"', item);
                else
                    description = '';
                end
                fprintf('%-*s : %s\n', 20, item, description)
            end
        end
    end

    function has_data = has_rawdata(obj, worker)
        % Checks whether all raw input data for this (prep) worker is available
        
        has_data = true;
        if isempty(dir(fullfile(obj.BIDS.pth, 'sub-*')))
            return      % -> Escape for unit-tests
        end

        worker_ = worker.handle(obj.BIDS, struct(), obj.config);
        for workitem = worker.needs
            if startsWith(workitem, 'raw') && isempty(bids.query(obj.BIDS, 'data', worker_.bidsfilter.(workitem)))
                has_data = false;
                fprintf('⚠  No "%s" input data found for %s\n', workitem, worker.name)
                return
            end
        end
    end

    function resumes = get_resumes(obj, CheckData)
        %GET_RESUMES Gets the resumes of the pool of workers that live in qb.workers and in the configfile folder.
        % Workers that do not have input data are excluded from the resumes if CHECKDATA is true.
        %
        % Output:
        %   RESUME.NAME.HANDLE      - The function handle
        %              .NAME        - Their personal name
        %              .DESCRIPTION - The description of what they do
        %              .MAKES       - The workitems they can make
        %              .NEEDS       - The workitems they need for work
        %              .USESGPU     - True if the worker can make use of the GPU
        %              .PREFERRED   - True if the worker was selected by the user
        %
        % NB: Assumes the qb.workers have a "Worker" substring in their m-filename

        arguments
            obj
            CheckData logical = true
        end

        resumes = {};
        wfiles  = dir(fullfile(fileparts(which("qb.workers.Worker")), "*Worker*.m"))';
        if ~isdeployed      % Add custom workers from the user config directory
            wfiles = [wfiles, dir(fullfile(fileparts(qb.resetconfig(false)), "workers", "*Worker*.m"))'];
        end
        fprintf("\nRegistering:\n")
        for wfile = wfiles
            if ~(strcmp(wfile.name, 'Worker.m') || startsWith(wfile.name, '.'))     % Exclude the abstract Worker class and hidden files
                if endsWith(wfile.folder, '+workers')
                    worker = qb.workers.(erase(wfile.name, '.m'))(obj.BIDS, struct(name='',session=''), obj.config);
                else                                % Custom workers in the user config directory should be on the MATLAB-path
                    worker = feval(erase(wfile.name, '.m'), obj.BIDS, struct(name='',session=''), obj.config);
                end
                resumes.(worker.name).handle      = str2func(class(worker));
                resumes.(worker.name).name        = worker.name;
                resumes.(worker.name).description = worker.description;
                resumes.(worker.name).makes       = worker.makes();
                resumes.(worker.name).needs       = worker.needs(:)';
                resumes.(worker.name).usesGPU     = worker.usesGPU;
                resumes.(worker.name).preferred   = false;
                fprintf('   - %s\n', worker.name)
            end
        end

        % Do smart pruning of workers that depend on missing input data. TODO: make it smarter, it may still include workers that depend on prepworkers that have missing input data (when multiple workers make the same workitem)
        if CheckData
            names = strings(1,0);
            for name = string(fieldnames(resumes))'
                if ~ismember(name, names) && obj.has_rawdata(resumes.(name))
                    names(end+1) = name;    %#ok<AGROW> Keep the worker itself 
                    depworkers(resumes.(name))
                end
            end
            for name = string(fieldnames(resumes))'
                if ~ismember(name, names)
                    fprintf('ℹ️  Discarding %s as (some of) its input data is missing\n', name)
                    resumes = rmfield(resumes, name);
                end
            end
        end

        function depworkers(resume)
            %DEPWORKERS Recursively find all workers that depend on the workitems made (as listed in the resume)
            for workitem = resume.makes         % Find all workers that need this workitem
                for name_ = string(fieldnames(resumes))'
                    if ~ismember(name_, names) && ismember(workitem, resumes.(name_).needs) && obj.has_rawdata(resumes.(name_))
                        names(end+1) = name_;   %#ok<AGROW>
                        depworkers(resumes.(name_))
                    end
                end
            end
        end
    end

    function load_workflow(obj, workflowfile)
        %LOAD_WORKFLOW Loads all coordinator properties from the workflowfile

        arguments
            obj
            workflowfile = obj.workflowfile
        end

        if isempty(workflowfile) || ~isfile(workflowfile)
            fprintf('🔧 No previous workflow settings found\n')
            return
        end

        % Load the workflow settings from the workflowfile
        fprintf('🔧 Loading workflow settings from: %s\n', workflowfile)
        load(workflowfile, 'coord')
        obj.workflowfile = workflowfile;

        % Set the workflow settings
        for property = string(fieldnames(coord)')
            obj.(property) = coord.(property);
        end
    end

    function save_workflow(obj, workflowfile)
        %SAVE_WORKFLOW Saves all coordinator properties to the workflowfile, except the BIDS and config data

        arguments
            obj
            workflowfile {mustBeTextScalar} = obj.workflowfile
        end

        % Collect the selected workflow settings
        for property = string(properties(obj)')
            if ~ismember(property, {'BIDS','config'})
                coord.(property) = obj.(property);
            end
        end

        % Save the workflow settings to the workflowfile
        if ~isfile(workflowfile)
            fprintf('🔧 Saving workflow settings to: %s\n', workflowfile)
        else
            fprintf('🔧 Overwriting workflow settings in: %s\n', workflowfile)
        end
        [~,~] = mkdir(fileparts(workflowfile));
        save(workflowfile, 'coord')
        obj.workflowfile = workflowfile;
    end

end

end

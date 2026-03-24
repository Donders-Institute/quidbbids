classdef (Abstract) Coordinator < handle
%Coordinator Abstract base class for building a BIDS app control center (e.g. with a GUI to edit the CONFIG property)
%
% The manager doesn't know how the data is organized and needs assistance from the coordinator


properties
    BIDS                    % BIDS layout object from bids-matlab
    outputdir               % BIDSApp derivatives subdirectory where the output is stored
    workdir                 % Working directory for intermediate results
    products                % The end productcs (workitems) requested by the user, full list of possible products, see obj.workitems()
    resumes                 % The resumes of all available workers
    configfile              % Path to the active configuration file
    workflowfile            % Path to the active workflow file
    config                  % Configuration struct loaded from the config file
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

        % Parse the inputs
        bidsapp = regexp(class(obj), '[^.]+$', 'match', 'once');  % Only take the class basename, i.e. the last part after the dot
        if strlength(outputdir) == 0
            outputdir = fullfile(BIDS.pth, "derivatives", bidsapp);
        end
        if strlength(workdir) == 0
            workdir = fullfile(BIDS.pth, "derivatives", bidsapp + "_work");
        end

        % Initialize the derivatives and workdir datasets
        if ~isfolder(outputdir)
            bids.init(char(outputdir), 'is_derivative', true)
        end
        if ~isfolder(workdir)
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
        obj.products     = "";      % NB: This has to be called after get_resumes() because set.products() needs to know the workitems
        glossfile = fullfile(fileparts(mfilename('fullpath')), 'glossary.json');
        if isfile(glossfile)
            obj.glossary = jsondecode(fileread(glossfile));
        end
    end

    function set.products(obj, val)
        % Check if the product exist and force anything assigned to be stored as a string row
        for product = string(val(:)')
            if product~="" && all(cellfun(@isempty, regexp(obj.workitems(), "^" + product + "$")))
                warning("QuIDBBIDS:Products:Ambiguous", "The '%s' product was not found, it must match any of:%s", product, sprintf(' "%s"', obj.workitems()))
                return
            end
        end
        obj.products = string(val(:)');
        obj.products(obj.products=="") = [];
    end

    function choose_products(obj)
        obj.products = qb.ChooseProducts(obj.coord.resumes);
    end

    function items = workitems(obj)
        %WORKITEMS Gets or displays a list of all the workitems the workers can make

        makes = [];
        for name = fieldnames(obj.resumes)'
            makes = [makes, obj.resumes.(name{1}).makes];       %#ok<AGROW>
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
                fprintf('%-*s : %s\n', 20, item, description);
            end
        end
    end

    function resumes = get_resumes(obj)
        %GET_RESUMES Gets the resumes of the pool of workers that live in qb.workers and in the configfile folder
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

        resumes = {};
        wfiles  = dir(fullfile(fileparts(which("qb.workers.Worker")), "*Worker*.m"))';
        if ~isdeployed      % Add custom workers from the user config directory
            wfiles = [wfiles, dir(fullfile(fileparts(qb.resetconfig(false)), "workers", "*Worker*.m"))'];
        end
        fprintf("\nRegistering:\n")
        for wfile = wfiles
            if ~strcmp(wfile.name, 'Worker.m')      % Exclude the abstract Worker class
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

    end

    function load_coord(obj, workflowfile)
        %LOAD_WORKFLOW Loads all coordinator properties from the workflowfile

        arguments
            obj
            workflowfile {mustBeTextScalar} = obj.workflowfile
        end

        if ~isfile(workflowfile)
            fprintf('🔧 No previous coordinator data found\n')
            return
        end

        fprintf('🔧 Loading coordinator data from: %s\n', workflowfile)
        load(workflowfile, 'coord')
        obj.workflowfile = workflowfile;

        % Set the coordinator data
        for property = string(fieldnames(coord)')
            obj.(property) = coord.(property);
        end
    end

    function save_coord(obj, workflowfile)
        %SAVE_WORKFLOW Saves all coordinator properties to the workflowfile, except the BIDS and config data

        arguments
            obj
            workflowfile {mustBeTextScalar} = obj.workflowfile
        end

        % Get the coordinator data
        for property = string(properties(obj)')
            if ~ismember(property, {'BIDS','config','configfile'})
                coord.(property) = obj.(property);
            end
        end

        fprintf('🔧 Saving coordinator data to: %s\n', workflowfile)
        [~,~] = mkdir(fileparts(workflowfile));
        save(workflowfile, 'coord', '-append')
        obj.workflowfile = workflowfile;
    end

end

end

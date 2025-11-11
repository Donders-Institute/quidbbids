classdef (Abstract) Coordinator < handle
    %Coordinator Abstract base class for building a BIDS app control center (e.g. with a GUI to edit the CONFIG property)
    %
    % The manager doesn't know how the data is organized and needs assistance of the coordinator


    properties
        BIDS            % BIDS layout object from bids-matlab
        outputdir       % BIDSApp derivatives subdirectory where the output is stored
        workdir         % Working directory for intermediate results
        resumes         % The resumes of all available workers
        configfile      % Path to the active configuration file
        config          % Configuration struct loaded from the config file
    end
    

    methods (Abstract)
        config = get_config(obj, config)   % Reads CONFIG from the configuration file or writes to it if CONFIG is given
    end

    
    methods

        function obj = Coordinator(BIDS, outputdir, workdir, configfile)
            % Constructor for the abstract Coordinator class
            %
            % Inputs:
            %   BIDSDIR    - BIDS layout object from bids-matlab
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

            % Initialize the QuIDBBIDS derivatives and workdir datasets.
            if ~isfolder(outputdir)
                bids.init(char(outputdir), 'is_derivative', true)
            end
            if ~isfolder(workdir)
                bids.init(char(workdir), 'is_derivative', true)
            end

            % Set the properties
            obj.BIDS       = BIDS;
            obj.outputdir  = outputdir;
            obj.workdir    = workdir;
            obj.configfile = configfile;
            obj.config     = obj.get_config();
            obj.resumes    = obj.get_resumes();
        end

        function items = workitems(obj)
            %WORKITEMS Gets a list of all the workitems the workers can make
            items = string(unique(horzcat(obj.resumes.makes)));
        end

        function resumes = get_resumes(obj)
            %GET_RESUMES Gets the resumes of the pool of workers that live in qb.workers and in the configfile folder
            %
            % Output:
            %   RESUME.NAME.HANDLE      - The function handle
            %              .NAME        - Their personal name
            %              .DESCRIPTION - The description of what they do
            %              .VERSION     - Their semantic version number
            %              .MAKES       - The workitems they can make
            %              .NEEDS       - The workitems they need for work
            %              .USESGPU     - True if the worker can make use of the GPU
            %              .PREFERRED   - True if the worker was selected by the user
            %
            % NB: Assumes the qb.workers have a "Worker" substring in their m-filename

            resumes = {};
            wfiles  = dir(fullfile(fileparts(which("qb.workers.Worker")), "*Worker*.m"))';             
            if ~isdeployed
                wfiles = [wfiles, dir(fullfile(fileparts(obj.configfile), "*Worker*.m"))'];
            end
            for wfile = wfiles
                if ~strcmp(wfile.name, 'Worker.m')   % Exclude the abstract Worker class
                    worker = qb.workers.(erase(wfile.name, '.m'))(struct(),struct('name','','session',''));
                    resumes.(worker.name).handle      = str2func(class(worker));
                    resumes.(worker.name).name        = worker.name;
                    resumes.(worker.name).description = worker.description;
                    resumes.(worker.name).version     = worker.version;
                    resumes.(worker.name).makes       = worker.makes();
                    resumes.(worker.name).needs       = worker.needs(:)';
                    resumes.(worker.name).usesGPU     = worker.usesGPU;
                    resumes.(worker.name).preferred   = false;
                end
            end

        end

    end

end
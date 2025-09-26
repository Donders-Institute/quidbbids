classdef QuIDBBIDS < handle
    %   ___       ___ ___  ___ ___ ___ ___  ___ 
    %  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
    % | (_) | || || || |) | _ \ _ \| || |) \__ \
    %  \__\_\\_,_|___|___/|___/___/___|___/|___/
    %
    % Quantitative Imaging Derived Biomarkers in BIDS
    % ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    %
    % The QuIDBBIDS class provides a framework for pre-processing and estimation of
    % quantitative MRI-derived biomarkers in the BIDS (Brain Imaging Data Structure)
    % format. It integrates several toolboxes (such as SPM, SEPIA, MWI and more) and
    % facilitates standardized, reproducible workflows for quantitative MRI.
    %
    % Quick start - Create a QuIDBBIDS object for your BIDS dataset:
    %
    %   quidb = qb.QuIDBBIDS();               % Select BIDS root directory via GUI
    %   quidb = qb.QuIDBBIDS(bids_dir);       % Specify BIDS root directory
    %   quidb = qb.QuIDBBIDS(bids_dir, ..);   % See constructor help for more details
    %
    % For comprehensive documentation with tutorials, examples, and API reference:
    %
    %   <a href="matlab: web('https://quidbbids.readthedocs.io')">Documentation on Read the Docs</a>
    % 
    % For more concise help on using a QuIDBBIDS object and its methods:


    properties
        config      % Configuration struct loaded from the config TOML file
        configfile  % Path to the active TOML configuration file
        bidsdir     % Root BIDS directory
        outputdir   % QuIDBBIDS derivatives directory where the output is stored
        workdir     % Working directory for intermediate results
        BIDS        % BIDS layout object from bids-matlab (raw input data only)
    end


    methods

        function obj = QuIDBBIDS(bidsdir, outputdir, workdir, configfile)
            % Initializes the QuIDBBIDS object for a given BIDS dataset
            %
            % OBJ = QuIDBBIDS(BIDSDIR, DERIVDIR, CONFIGFILE)
            %
            % Inputs:
            %   BIDSDIR    - Path to the root BIDS dataset directory. Default = user dialogue
            %   DERIVDIR   - Path to the QuIDBBIDS derivatives directory where output will be written.
            %                Default: [BIDSDIR]/derivatives/QuIDBBIDS
            %   WORKDIR    - Working directory for intermediate results. Default: outputdir/QuIDBBIDS_work.
            %   CONFIGFILE - Path to a TOML configuration file with pipeline settings.
            %                Default: [BIDSDIR]/derivatives/quidbbids/code/config.toml
            %
            % Usage:
            %   quidb = qb.QuIDBBIDS();             % Select BIDS root directory via GUI
            %   quidb = qb.QuIDBBIDS(bids_dir);     % Specify BIDS root directory
            %   etc.
            %
            % See also: qb.QuIDBBIDS (for overview)
            
            arguments
                bidsdir    {mustBeTextScalar} = ""
                outputdir  {mustBeTextScalar} = ""
                workdir    {mustBeTextScalar} = ""
                configfile {mustBeTextScalar} = ""
            end

            % Set the Matlab-path for the dependencies
            rootdir = fileparts(fileparts(mfilename("fullpath")));
            for toolbox = dir(fullfile(rootdir, "dependencies"))'
                toolpath = fullfile(rootdir, "dependencies", toolbox.name);
                if toolbox.isdir && ~any(strcmp(toolbox.name, [".", ".."]))
                    continue
                elseif ~any(strcmp(toolbox.name, ["sepia", "spm"]))
                    obj.addtoolbox(toolpath)
                else
                    obj.addtoolbox(toolpath, true)
                end
            end

            % Parse the inputs
            if strlength(bidsdir) == 0
                bidsdir = uigetdir(pwd, "Select the root BIDS directory");
            end
            if ~bidsdir || ~isfolder(bidsdir)
                return
            end
            if strlength(outputdir) == 0
                outputdir = fullfile(bidsdir, "derivatives", "QuIDBBIDS");
            end
            if strlength(workdir) == 0
                workdir = fullfile(bidsdir, "derivatives", "QuIDBBIDS_work");
            end
            if strlength(configfile) == 0
                configfile = fullfile(outputdir, "code", "config.toml");
            elseif isfolder(configfile)
                error("The configfile must be a file, not a folder: " + configfile)
            end

            % Initialize the QuIDBBIDS derivatives and workdir datasets.
            if ~isfolder(outputdir)
                bids.init(char(outputdir), ...          NB: matlab-bids does not handle strings
                          'is_derivative', true,...
                          'is_datalad_ds', false, ...
                          'tolerant', true, ...
                          'verbose', true)
            end
            if ~isfolder(workdir)
                bids.init(char(workdir), ...
                          'is_derivative', true,...
                          'is_datalad_ds', false, ...
                          'tolerant', true, ...
                          'verbose', false)

            % Set the properties
            obj.bidsdir    = string(bidsdir);
            obj.outputdir  = outputdir;
            obj.workdir    = workdir;
            obj.configfile = configfile;
            obj.config     = obj.getconfig(configfile);
            obj.BIDS       = bids.layout(bidsdir, ...
                                         'use_schema', true, ...
                                         'index_derivatives', false, ...
                                         'index_dependencies', false, ...
                                         'filter', obj.config.bids.select, ...
                                         'tolerant', true, ...
                                         'verbose', true);
            end
        end

        function configeditor(obj)
            % Opens a GUI to edit the processing options in the dataset configuration file
            %
            % Usage:
            %   obj = obj.configeditor();
            %
            % See also: qb.QuIDBBIDS (for overview)
        end

        function manager(obj)
        end

        function QSM(obj, subjects)
            % Loops over subjects to run QSM and R2-star pipelines
            %
            % Inputs:
            %   SUBJECTS - A matlab-bids struct array of subjects to process. Default: all
            %              subjects in the BIDS dataset.
            %
            % Usage:
            %   obj.QSM()             % Process all subjects
            %   obj.QSM(subjects)     % Specify a subset of subjects to process
            %
            % See also: qb.QuIDBBIDS (for overview)

            % Process the subjects (the implementation is in private/QSM_worker.m)
            if nargin < 2 || isempty(subjects)
                subjects = obj.BIDS.subjects;
            end
            if obj.config.useHPC
                qsubcellfun(@QSM_worker, repmat({obj}, size(subjects)), num2cell(subjects), 'memreq',3*1024^3, 'timreq',60*60)
            else
                QSM_worker(obj, subjects)
            end
        end

        function SCR(obj, subjects)
            % Loops over subjects to fit the SCR model
            %
            % Inputs:
            %   SUBJECTS - A matlab-bids struct array of subjects to process. Default: all
            %              subjects in the BIDS dataset.
            %
            % Usage:
            %   obj.SCR()           % Process all subjects
            %   obj.SCR(subjects)   % Specify a subset of subjects to process
            %
            % See also: qb.QuIDBBIDS (for overview)

            % Process the subjects (the implementation is in private/SCR_worker.m)
            if nargin < 2 || isempty(subjects)
                subjects = obj.BIDS.subjects;
            end
            if obj.config.useHPC
                qsubcellfun(@SCR_worker, repmat({obj}, size(subjects)), num2cell(subjects), 'memreq',3*1024^3, 'timreq',60*60)
            else
                SCR_worker(obj, subjects)
            end
        end

        function MCR(obj, subjects)
            % Loops over subjects to fit the MCR model
            %
            % Inputs:
            %   SUBJECTS - A matlab-bids struct array of subjects to process. Default: all
            %              subjects in the BIDS dataset.
            %
            % Usage:
            %   obj.MCR()            % Process all subjects
            %   obj.MCR(subjects)    % Specify a subset of subjects to process
            %
            % See also: qb.QuIDBBIDS (for overview)

            % Process the subjects (the implementation is in private/MCR_worker.m)
            if nargin < 2 || isempty(subjects)
                subjects = obj.BIDS.subjects;
            end
            if obj.config.useHPC
                qsubcellfun(@MCR_worker, repmat({obj}, size(subjects)), num2cell(subjects), 'memreq',3*1024^3, 'timreq',60*60)
            else
                MCR_worker(obj, subjects)
            end
        end

        function MCRGPU(obj, subjects)
            % Loops over subjects to fit the MCR model using GPU acceleration
            %
            % Usage:
            %   obj.MCRGPU()             % Process all subjects
            %   obj.MCRGPU(subjects)     % Specify a subset of subjects to process
            %
            % See also: qb.QuIDBBIDS (for overview)

            % Process the subjects (the implementation is in private/MCRGPU_worker.m)
            if nargin < 2 || isempty(subjects)
                subjects = obj.BIDS.subjects;
            end
            if obj.config.useHPC
                qsubcellfun(@MCRGPU_worker, repmat({obj}, size(subjects)), num2cell(subjects), 'memreq',3*1024^3, 'timreq',60*60)
            else
                MCRGPU_worker(obj, subjects)
            end
        end

        function config = getconfig(obj, configfile, config)
            % Read and optionally write QuIDBBIDS configuration file.
            %
            % CONFIG = GETCONFIG(CONFIGFILE) reads the configuration from the specified CONFIGFILE.
            % If it does not exist, a default configuration is copied from the user's HOME directory.
            %
            % CONFIG = GETCONFIG(CONFIGFILE, CONFIG) writes the provided CONFIG struct to CONFIGFILE
            % in TOML format. This updates or creates the configuration file.
            %
            % Inputs:
            %   CONFIGFILE  - Path to the TOML configuration file.
            %   CONFIG      - A struct with configuration parameters. If provided, GETCONFIG writes
            %                 this data to the CONFIGFILE, else it reads it from CONFIGFILE.
            %
            % Output:
            %   CONFIG      - A struct with the loaded configuration settings.
            %
            % The function ensures that a default config exists in:
            %   <HOME>/.quidbbids/<version>/config_default.toml
            %
            % Usage:
            %   config = obj.getconfig("myconfig.toml");
            %   obj.getconfig("myconfig.toml", config);
            
            arguments (Input)
                obj
                configfile {mustBeTextScalar, mustBeNonempty}
                config     (1,1) struct = struct()
            end

            arguments (Output)
                config struct
            end
            
            % Create a default configfile if it does not exist
            config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.toml");
            if ~isfile(config_default)
                disp("Creating default configuration file: " + config_default)
                [pth, name, ext] = fileparts(config_default);
                [~,~] = mkdir(pth);
                copyfile(fullfile(fileparts(mfilename("fullpath")), name + ext), config_default)
            end

            % Write or read the study configuration data (create if needed)
            if nargin > 2
                toml.write(configfile, config);
            else
                if ~isfile(configfile)
                    disp("Writing study configurations to: " + configfile)
                    [~,~] = mkdir(fileparts(configfile));
                    copyfile(config_default, configfile)
                end
                config = toml.map_to_struct(toml.read(configfile));
                config = obj.castInt64ToDouble(config);

                % Check for version conflicts
                if config.version ~= qb.version()
                    warning("The config file version (" + config.version + ") does not match the current QuIDBBIDS version (" + qb.version() + "). Please update your config file if needed.")
                end
            end

        end

    end


    methods(Access = private)

        function config = castInt64ToDouble(obj, config)
            % Recursively casts all int64 values in CONFIG into doubles.
            %
            % CONFIG = CASTINT64TODOUBLE(CONFIG) traverses CONFIG and converts all int64 scalars and
            % arrays into doubles. Useful for reading TOML files where integers are parsed as int64.
            
            if isstruct(config)
                f = fieldnames(config);
                for k = 1:numel(f)
                    config.(f{k}) = obj.castInt64ToDouble(config.(f{k}));
                end
            elseif iscell(config)
                config = cellfun(@obj.castInt64ToDouble, config, 'UniformOutput', false);
            elseif isa(config, 'int64')
                config = double(config);
            end
        end
        
    end


    methods(Access = private, Static)

        function addtoolbox(toolpath, recursive)
            % Add an external toolbox to the MATLAB path.
            %
            % ADDTOOLBOX(TOOLPATH, RECURSIVE) checks if the specified toolbox is
            % already available on the MATLAB path or installed as a MATLAB Add-On.
            % If not it attempts to:
            %   1. Enable it via the MATLAB Add-On manager if installed as an Add-On.
            %   2. Otherwise, it adds the given folder to the MATLAB path.
            %
            % Inputs:
            %   TOOLPATH  - Full path to the toolbox folder.
            %   RECURSIVE - If true, use genpath to add the toolbox folder recursively
            %               with all subfolders. Default: false

            arguments
                toolpath  {mustBeFolder}
                recursive (1,1) logical = false
            end

            [~, toolname] = fileparts(toolpath);
            if contains(path, filesep + toolname) || isdeployed
                return
            elseif any(strcmp(toolname, matlab.addons.installedAddons().Name)) && ~matlab.addons.isAddonEnabled(toolname)
                disp("Enabling add-on: " + toolname)
                matlab.addons.enableAddon(toolname)
            elseif isfolder(toolpath)
                disp("Adding path: " + toolpath)
                if recursive
                    addpath(genpath(toolpath))
                else
                    addpath(toolpath)
                end
                addpath(toolpath)
            else
                error("Cannot find '" + toolname + "' on the MATLAB-path, please make sure it is installed")
            end
        end
        
    end

end

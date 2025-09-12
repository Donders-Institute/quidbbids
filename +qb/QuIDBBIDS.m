classdef QuIDBBIDS
    %   ___       ___ ___  ___ ___ ___ ___  ___ 
    %  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
    % | (_) | || || || |) | _ \ _ \| || |) \__ \
    %  \__\_\\_,_|___|___/|___/___/___|___/|___/
    %
    % Quantitative Imaging Derived Biomarkers in BIDS
    % ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    %
    % QuIDBBIDS provides a framework for pre-processing and estimation of
    % quantitative MRI-derived biomarkers in the BIDS (Brain Imaging Data
    % Structure) format. It integrates several toolboxes (such as SEPIA,
    % SPM, ROMEO, and more) and facilitates standardized, reproducible
    % workflows for quantitative MRI.
    % 
    % For comprehensive documentation with tutorials, examples, and API reference:
    %
    %   <a href="matlab: web('https://quidbbids.readthedocs.io')">Documentation on Read the Docs</a>
    % 
    % For more concise help on specific usage:

    properties
        config
        configfile
        bidsdir
        derivdir
        workdir
        BIDS
    end


    methods

        function obj = QuIDBBIDS(bidsdir, derivdir, workdir, configfile)
            % Constructor for the QuIDBBIDS class
            %
            % OBJ = QuIDBBIDS(BIDSDIR, DERIVDIR, CONFIGFILE)
            %
            % Inputs:
            %   BIDSDIR    - (Required) Path to the root BIDS dataset directory.
            %   DERIVDIR   - (Optional) Path to the derivatives directory where output will be written.
            %                Default: [BIDSDIR]/derivatives
            %   WORKDIR    - Working directory for intermediate resuls. Default: derivdir/QuIDBBIDS_work.
            %   CONFIGFILE - (Optional) Path to a TOML configuration file with pipeline settings.
            %                Default: [BIDSDIR]/derivatives/quidbbids/code/config.toml
            %
            % Properties:
            %   config      - Configuration struct loaded from the config TOML file.
            %   configfile  - Path to the active TOML configuration file.
            %   bidsdir     - Root BIDS directory.
            %   derivdir    - Derivatives directory where the output is stored. Default: bidsdir/derivatives/QuIDBBIDS
            %   workdir     - Working directory for intermediate resuls.
            %   BIDS        - BIDS layout object from bids-matlab.

            % Parse the inputs
            arguments
                bidsdir    {mustBeTextScalar} = ""
                derivdir   {mustBeTextScalar} = ""
                workdir    {mustBeTextScalar} = ""
                configfile {mustBeTextScalar} = ""
            end

            if strlength(bidsdir) == 0
                bidsdir = uigetdir(pwd, "Select the root BIDS directory");
                if ~bidsdir
                    return
                end
            end
            if strlength(derivdir) == 0
                derivdir = fullfile(bidsdir, "derivatives", "QuIDBBIDS");
            end
            if strlength(workdir) == 0
                workdir = fullfile(bidsdir, "derivatives", "QuIDBBIDS_work");
            end
            if strlength(configfile) == 0
                configfile = fullfile(bidsdir, "derivatives", "quidbbids", "code", "config.toml");
            elseif isfolder(configfile)
                error("The configfile must be a file, not a folder: " + configfile)
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

            % Initialize the QuIDBBIDS derivatives dataset. NB: matlab-bids does not handle strings but expects classic character vectors
            if ~isfolder(derivdir)
                bids.init(derivdir, ...
                          'is_derivative', true,...
                          'is_datalad_ds', false, ...
                          'tolerant', true, ...
                          'verbose', true)
            end

            % Index the raw dataset
            obj.bidsdir    = string(bidsdir);
            obj.derivdir   = derivdir;
            obj.workdir    = workdir;
            obj.configfile = configfile;
            obj.config     = obj.getconfig(configfile);
            obj.BIDS       = bids.layout(bidsdir, ...
                                         'use_schema', true, ...
                                         'index_derivatives', true, ...
                                         'index_dependencies', false, ...
                                         'filter', obj.config.bids.select, ...
                                         'tolerant', true, ...
                                         'verbose', true);
            
        end

        function obj = configeditor(obj)
            % Method signature for editing the configuration - implementation is in configeditor.m
            obj = configeditor(obj);
        end

        function obj = prepSEPIA(obj)
            % External toplevel QuIDBBIDS function that loops over subjects to perform pre- and SEPIA-processing
            %
            % Processing steps:
            % 
            % 1. Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
            %    The results are blurry but within the common GRE space, hence, iterate the computation
            %    with the input images that have been realigned to the target in the common space
            % 2. Coregister all FA-MEGRE images to each T1w-like target image (using echo-1_mag), coregister
            %    coregister the B1 images as well to the M0 (which is also in the common GRE space)
            % 3. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
            %    to produce a minimal output mask (for Sepia)
            % 4. Run the Sepia QSM and R2-star pipelines
            obj = prepSEPIA(obj);       % Implementation is in private/prepSEPIA.m
        end

        function obj = fitSCR(obj)
            % Method signature for fitting SCR model - implementation is in fitSCR.m
            obj = fitSCR(obj);
        end

        function obj = fitMCR(obj)
            % Method signature for fitting MCR model - implementation is in fitMCR.m
            obj = fitMCR(obj);
        end

        function obj = fitMCRGPU(obj)
            % Method signature for fitting MCR model using GPU - implementation is in fitMCRGPU.m
            obj = fitMCRGPU(obj);
        end

    end


    methods(Static)

        function config = getconfig(configfile, config)
            % GETCONFIG Read and optionally write QuIDBBIDS configuration file.
            %
            % CONFIG = GETCONFIG(CONFIGFILE) reads the configuration from the specified CONFIGFILE.
            % If it does not exist, a default configuration is copied from the user's HOME directory.
            %
            % CONFIG = GETCONFIG(CONFIGFILE, CONFIG) writes the provided CONFIG struct to CONFIGFILE
            % in TOML format. This updates or creates the configuration file.
            %
            % Inputs:
            %     CONFIGFILE        - Path to the TOML configuration file.
            %     CONFIG (optional) - A struct with configuration parameters. If provided, GETCONFIG
            %                         writes this struct to CONFIGFILE in TOML format.
            %
            % Output:
            %     CONFIG - A struct with the loaded configuration settings.
            %
            % The function ensures that a default config exists in:
            %     <HOME>/.quidbbids/<version>/config_default.toml
            %
            % Examples:
            %     config = getconfig("myconfig.toml");
            %     getconfig("myconfig.toml", config);
            
            arguments
                configfile {mustBeTextScalar}
                config (1,1) struct = struct()  % Optional configuration struct
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
            if nargin > 1
                toml.write(configfile, config);
            else
                if ~isfile(configfile)
                    disp("Writing study configurations to: " + configfile)
                    [~,~] = mkdir(fileparts(configfile));
                    copyfile(config_default, configfile)
                end
                config = toml.map_to_struct(toml.read(configfile));
                if config.version ~= qb.version()
                    warning("The config file version (" + config.version + ") does not match the current QuIDBBIDS version (" + qb.version() + "). Please update your config file if needed.")
                end
            end

        end

    end


    methods(Static, Access = private)

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
            %   RECURSIVE - (Optional, logical) If true, use genpath to add the toolbox
            %               folder recursively with all subfolders. Default: false

            arguments
                toolpath {mustBeFolder}
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

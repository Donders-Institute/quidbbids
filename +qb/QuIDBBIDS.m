classdef QuIDBBIDS < qb.workers.Coordinator
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


    methods

        function obj = QuIDBBIDS(bidsdir, outputdir, workdir, configfile)
            % Initializes the concrete QuIDBBIDS Coordinator class for a given BIDS dataset
            %
            % OBJ = QuIDBBIDS(BIDSDIR, DERIVDIR, CONFIGFILE)
            %
            % Inputs:
            %   BIDSDIR    - Path to the root BIDS dataset directory. Default = user dialogue
            %   DERIVDIR   - Path to the QuIDBBIDS derivatives directory where output will be written.
            %                Default: [BIDSDIR]/derivatives/QuIDBBIDS
            %   WORKDIR    - Working directory for intermediate results. Default: outputdir/QuIDBBIDS_work.
            %   CONFIGFILE - Path to a TOML configuration file with workflow settings.
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

            if strlength(bidsdir) == 0
                bidsdir = uigetdir(pwd, "Select the root BIDS directory");
            end
            if strlength(configfile) == 0
                configfile = fullfile(bidsdir, "derivatives", "QuIDBBIDS", "code", "config.toml");  % A bit of a hack because obj is not yet fully constructed
            elseif isfolder(configfile)
                error("QuIDBBIDS:Nifti:InvalidInputArgument", "The configfile must be a file, not a folder: " + configfile)
            end

            config = qb.get_config_toml(configfile);    % Cannot call obj.get_config directly because obj is not yet fully constructed
            BIDS   = bids.layout(char(bidsdir), 'use_schema', true, ...
                                                'index_derivatives', false, ...
                                                'index_dependencies', false, ...
                                                'filter', config.bids.select, ...
                                                'tolerant', true, ...
                                                'verbose', true);
            obj@qb.workers.Coordinator(BIDS, outputdir, workdir, configfile)

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

        end

        function startGUI(obj)
        end

        function configeditor(obj)
            % Opens a GUI to edit the processing options in the dataset configuration file
            %
            % Usage:
            %   obj = obj.configeditor();
            %
            % See also: qb.QuIDBBIDS (for overview)
        end

        function manager = manager(obj, products)
            %GET_MANAGER Gets a workflow manager to get work
            %
            % Seel also: qb.workers.Manager

            arguments
                obj
                products {mustBeText} = ""
            end

            manager = qb.workers.Manager(obj, products);
        end

        function config = get_config(obj, config)
            % Read and optionally write QuIDBBIDS configuration file.
            %
            % CONFIG = GET_CONFIG() reads the configuration from CONFIGFILE. If it does not
            % exist, a default configuration is copied from the user's HOME directory.
            %
            % CONFIG = GET_CONFIG(CONFIG) writes the provided CONFIG struct to CONFIGFILE
            % (in TOML format). This updates or creates the configuration file.
            %
            % The function ensures that a default config exists in:
            %   <HOME>/.quidbbids/<version>/config_default.toml

            arguments (Input)
                obj
                config struct = struct()
            end

            arguments (Output)
                config struct
            end

            config = qb.get_config_toml(obj.configfile, config);    % Implementation is in get_config_toml to avoid circularity issues
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
                error('QuIDBBIDS:Dependency:MissingToolbox', "Cannot find '%s' on the MATLAB-path, please make sure it is installed", toolname)
            end
        end

    end

end

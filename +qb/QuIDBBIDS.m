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
        %   CONFIGFILE - Path to the configuration file with workflow settings. Passing 'force' uses the
        %                default config from the QuIDBBIDS folder in your HOME directory as default.
        %                Default: [BIDSDIR]/derivatives/quidbbids/code/config.json
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
        force = strcmp(configfile, "force");
        if strlength(configfile) == 0 || force
            configfile = fullfile(bidsdir, "derivatives", "QuIDBBIDS", "code", "config.json");  % A bit of a hack because obj is not yet fully constructed
            if force && isfile(configfile)
                display("Deleting existing config file: " + configfile)
                delete(configfile)
            end
        elseif isfolder(configfile)
            error("QuIDBBIDS:Nifti:InvalidInputArgument", "The configfile must be a file, not a folder: %s", configfile)
        end

        % Set the Matlab-path for the dependencies
        qb.addpath_deps()

        config = get_config(configfile);    % Cannot call obj.get_config directly because obj is not yet fully constructed / the superclass has not yet been called
        BIDS   = bids.layout(char(bidsdir), 'use_schema', true, ...
                                            'index_derivatives', false, ...
                                            'index_dependencies', false, ...
                                            'filter', config.General.BIDS.include.value, ...
                                            'tolerant', true, ...
                                            'verbose', true);
        obj@qb.workers.Coordinator(BIDS, outputdir, workdir, configfile)

    end

    function startGUI(obj)
    end

    function editinclusion(obj)
        % Opens a GUI to edit the BIDS inclusion filters for the dataset
        %
        % Usage:
        %   obj = obj.editinclusion();
        %
        % See also: qb.QuIDBBIDS (for overview) and qb.editconfig

        obj.config.General.BIDS.include.value = qb.BIDSIncludeGUI(obj.config.General.BIDS.include.value, obj.BIDS).waitForResult();
    end

    function editconfig(obj)
        % Opens a GUI to edit the processing options in the dataset configuration file
        %
        % Usage:
        %   obj = obj.editconfig();
        %
        % See also: qb.QuIDBBIDS (for overview)

        [obj.configfile, obj.config] = qb.configeditor(obj.configfile, obj.config);    % TODO: Add team workers
    end

    function manager = manager(obj)
        %GET_MANAGER Gets a workflow manager to get work done
        %
        % See also: qb.workers.Manager

        arguments
            obj
        end

        manager = qb.workers.Manager(obj);
    end

    function config = get_config(obj, config)
        % Read and optionally write QuIDBBIDS configuration file.
        %
        % CONFIG = GET_CONFIG() reads the configuration from CONFIGFILE. If it does not
        % exist, a default configuration is copied from the user's HOME directory.
        %
        % CONFIG = GET_CONFIG(CONFIG) writes the provided CONFIG struct to CONFIGFILE
        % (in JSON format). This updates or creates the configuration file.
        %
        % The function ensures that a default config exists in:
        %   <HOME>/.quidbbids/<version>/config_default.json

        arguments (Input)
            obj
            config struct = struct()
        end

        arguments (Output)
            config struct
        end

        config = get_config(obj.configfile, config);    % Implementation is in private/get_config to avoid circularity issues during object construction

    end

end

end

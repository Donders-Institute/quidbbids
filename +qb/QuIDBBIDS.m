classdef QuIDBBIDS < qb.workers.Coordinator
%   ___       ___ ___  ___ ___ ___ ___  ___
%  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
% | (_) | || || || |) | _ \ _ \| || |) \__ \
%  \__\_\\_,_|___|___/|___/___/___|___/|___/
%
% Quantitative Imaging Derived Biomarkers in BIDS
% ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
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
        %   CONFIGFILE - Path to the configuration file with workflow settings. Passing 'default' uses the
        %                default config from the QuIDBBIDS folder in your HOME directory as default.
        %                Default: [BIDSDIR]/code/QuIDBBIDS/config.json
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

        % Check the input
        if strlength(bidsdir) == 0
            if usejava('swing')
                bidsdir = uigetdir(pwd, "Select the root BIDS directory");
            end
            if isequal(bidsdir, 0) || strlength(bidsdir) == 0
                error('You must provide a BIDS input directory')
            end
        end

        % Check for the latest QuIDBBIDS version
        [ver, rel] = qb.version();
        if ~contains(ver, ["-" "+"]) && ~contains(rel, ["-" "+"])
            v = sscanf(ver, '%d.%d.%d');
            r = sscanf(rel, '%d.%d.%d');
            if any((v<r) & (cumsum(v~=r)==1))
                msg = sprintf('Your QuIDBBIDS version is v%s, but the latest released version is v%s', ver, rel);
                if usejava('swing')
                    helpdlg(msg, 'QuIDBBIDS Info')
                end
                warning('QuIDBBIDS:UpdateAvailable', msg)         %#ok<SPWRN>
            end
        end

        % Warn the user if the Matlab version is too old
        metadata = jsondecode(fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'project.json')));
        mversion = erase(metadata.project.dependencies.matlab, '>');
        if isMATLABReleaseOlderThan(mversion)
            msg = sprintf('Your MATLAB version (%s) is older than %s.\n\nQuIDBBIDS was developed for %s and later, so some GPU or other features may not work as expected', version('-release'), mversion, mversion);
            if usejava('swing')
                warndlg(msg, 'QuIDBBIDS Warning')
            end
            warning('QuIDBBIDS:MATLABVersion', msg)         %#ok<SPWRN>
        end

        % Get started by first setting-up the path
        fprintf(['\n⏱ Starting up QuIDBBIDS...' ...
                 '\n‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\n'])
        qb.addpath_deps()

        % Get or create the configuration settings
        default = strcmp(configfile, "default");
        if strlength(configfile) == 0 || default
            configfile = fullfile(bidsdir, "code", "QuIDBBIDS", "config.json");  % A bit of a hack because obj is not yet fully constructed
            if default && isfile(configfile)
                disp("🔧 Deleting existing config file: " + configfile)
                delete(configfile)
            end
        elseif isfolder(configfile)
            error("QuIDBBIDS:Nifti:InvalidInputArgument", "The configfile must be a file, not a folder: %s", configfile)
        end
        config = get_config(configfile);    % Cannot call obj.get_config directly because obj is not yet fully constructed / the superclass has not yet been called

        % Initialize the BIDS layout and call the superclass constructor
        BIDS   = bids.layout(char(bidsdir), use_schema        = true, ...
                                            index_derivatives = false, ...
                                            filter            = config.General.BIDS.include.value, ...
                                            tolerant          = true, ...
                                            verbose           = true);
        obj@qb.workers.Coordinator(BIDS, outputdir, workdir, configfile)

        % Add project metadata to the output folders
        obj.metadata = metadata;
        obj.add_metadata(obj.outputdir)
        obj.add_metadata(obj.workdir)
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

        oldVal = obj.config.General.BIDS.include.value;
        newVal = qb.GUI.EditInclude(oldVal, obj.BIDS).waitForResult();
        if ~isequal(newVal.modality, oldVal.modality) || isfield(newVal, 'sub') || isfield(newVal, 'ses')
            warning("QuIDBBIDS:Config:InclusionChanged", "The root of the BIDS inclusion filter has been changed. Please re-index the BIDS dataset")
        end
        obj.config.General.BIDS.include.value = newVal;
    end

    function editconfig(obj)
        % Opens a GUI to edit the processing options in the dataset configuration file
        %
        % Usage:
        %   obj = obj.editconfig();
        %
        % See also: qb.QuIDBBIDS (for overview)

        [obj.configfile, obj.config] = qb.configeditor(obj.configfile, obj.config, '', obj.BIDS);    % TODO: Add team workers
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


methods (Access = private)

    function add_metadata(obj, outputdir)
        % Adds project metadata to the QuIDBBIDS output folder

        arguments
            obj
            outputdir   {mustBeTextScalar}
        end

        % Check if the outputdir is already a QuIDBBIDS dataset
        descripfile = fullfile(outputdir, 'dataset_description.json');
        descrip     = fileread(descripfile);
        if ~contains(descrip, obj.metadata.project.name)
            descrip             = jsondecode(descrip);
            if endsWith(outputdir, '_work')
               descrip.Name     = [obj.metadata.project.name ' intermediate working data'];
            else
               descrip.Name     = [obj.metadata.project.name ' output data'];
            end
            descrip.BIDSVersion = obj.metadata.project.BIDSVersion;
            descrip.GeneratedBy = struct('Name',        obj.metadata.project.name, ...
                                         'Version',     qb.version(), ...
                                         'Description', obj.metadata.project.description, ...
                                         'CodeURL',     obj.metadata.project.urls.repository);
            bids.util.jsonencode(char(descripfile), descrip)
        end
    end

end

end

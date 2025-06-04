classdef QuIDBBIDS
    %   ___       ___ ___  ___ ___ ___ ___  ___ 
    %  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
    % | (_) | || || || |) | _ \ _ \| || |) \__ \
    %  \__\_\\_,_|___|___/|___/___/___|___/|___/
    %
    % Quantitative Imaging Derived Biomarkers in bidspath
    % ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    %
    % For more information, see the <a href="matlab: web('https://github.com/Donders-Institute/quidbbids')">QuIDBBIDS GitHub repository</a>

    %%
    properties
        version
        settings
        settingsfile
        bidsdir
        outputdir
        layout
    end

    %%
    methods

        function obj = QuIDBBIDS(bidsdir, outputdir, settingsfile)
            % QuIDBBIDS constructor

            arguments
                bidsdir      {mustBeFolder}
                outputdir    {mustBeTextScalar} = ""
                settingsfile {mustBeTextScalar} = ""
            end

            if outputdir == "" || isempty(outputdir)
                outputdir = fullfile(bidsdir, "derivatives", "quidbbids");
            end
            if settingsfile == "" || isempty(settingsfile)
                settingsfile = fullfile(bidsdir, "derivatives", "quidbbids", "code", "settings.json");
            end

            rootdir       = fileparts(fileparts(mfilename("fullpath")));
            obj.bidsdir   = bidsdir;
            obj.outputdir = outputdir;
            obj.settings  = obj.getsettings(settingsfile);

            % Set the Matlab-path to the dependencies
            mpkg = jsondecode(fileread(fullfile(rootdir, "resources", "mpackage.json")));
            deps = mpkg.dependencies;
            if isfield(deps, "bids-matlab") && isfield(deps.bids-matlab, "path")     % = Future format???
                obj.addtoolbox(deps.bids-matlab.path)
            end
            if isempty(which("bids.layout"))
                if any(strcmp("bids-matlab", matlab.addons.installedAddons().Name))
                    disp("Enabling add-on: bids-matlab")
                    matlab.addons.enableAddon("bids-matlab")
                else
                    obj.addtoolbox(fullfile(rootdir, "bids-matlab"))
                end
            end
            if isempty(which("spm"))
                obj.addtoolbox(fullfile(rootdir, "spm"))
            end

            obj.layout = bids.layout(bidsdir);
        
        end

        function settings = getsettings(~, settingsfile)
            % FUNCTION settings = getsettings(settingsfile)
            %
            % Read/write the settings from the bidsdir or from the default settings in home
            %
            % INPUTS:
            %   settingsfile - The JSON-file with all QuIDBBIDS settings. DEFAULT:
            %                  bidsdir/derivatives/quidbbids/code/settings.json
            % OUTPUTS:
            %   settings     - A struct with all settings to run QuIDBBIDS
            
            % Create default settings if needed
            settingsname = "settings.json";
            def_settings = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), settingsname);
            if ~isfile(def_settings)
                disp("Creating default settings file: " + def_settings)
                if ~isfolder(fileparts(def_settings))
                    mkdir(fileparts(def_settings));
                end
                copyfile(fullfile(fileparts(mfilename("fullpath")), settingsname), def_settings)
            end

            % Create (if needed) and read the settingsfile
            if ~isfile(settingsfile)
                disp("Writing study settings to: " + settingsfile)
                if ~isfolder(fileparts(settingsfile))
                    mkdir(fileparts(settingsfile));
                end
                copyfile(def_settings, settingsfile)
            end
            settings = jsondecode(fileread(settingsfile));
        end

    end

    %%
    methods(Access = private)

        function addtoolbox(~, toolpath)
            % Add the toolbox rootfodler to the MATLAB path
            [~, toolname] = fileparts(toolpath);
            if isfolder(toolpath)
                disp("Adding path: " + toolpath)
                addpath(toolpath)
            else
                error(["Cannot find '" toolname "' on the MATLAB-path, please make sure it is installed"])
            end
        end

    end

end

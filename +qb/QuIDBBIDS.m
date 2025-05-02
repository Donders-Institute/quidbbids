classdef QuIDBBIDS
    %   ___       ___ ___  ___ ___ ___ ___  ___ 
    %  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
    % | (_) | || || || |) | _ \ _ \| || |) \__ \
    %  \__\_\\_,_|___|___/|___/___/___|___/|___/
    %
    % Quantitative Imaging Derived Biomarkers in BIDS
    % ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    %
    % For more information, see the <a href="matlab: web('https://github.com/Donders-Institute/quidbbids')">QuIDBBIDS GitHub repository</a>

    properties
        bidsdir
    end

    methods
        function obj = QuIDBBIDS(bidsdir)
            % QuIDBBIDS constructor
            arguments
                bidsdir {mustBeFolder}
            end

            obj.bidsdir = bidsdir;

            % Set the Matlab-path to the dependencies
            root = fileparts(fileparts(mfilename("fullpath")));
            if isempty(which("bids.layout"))
                if any(strcmp("bids-matlab", matlab.addons.installedAddons().Name))
                    disp("Enabling add-on: bids-matlab")
                    matlab.addons.enableAddon("bids-matlab")
                else
                    BIDS = fullfile(root, "bids-matlab");
                    if exist(BIDS, "dir")
                        disp("Adding path: " + BIDS)
                        addpath(BIDS)
                    else
                        error("Cannot find 'bids-matlab' add-on/path, please make sure it is installed")
                    end
                end
            end
            if isempty(which("spm"))
                spm = fullfile(root, "spm");
                if exist(spm, "dir")
                    disp("Adding path: " + spm)
                    addpath(spm)
                else
                    error("Cannot find 'spm' on the MATLAB-path, please make sure it is installed")
                end
            end

        end
    end
end

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
        layout
    end

    methods
        function obj = QuIDBBIDS(varargin)

            % Set the Matlab-path to the dependencies
            root = fileparts(fileparts(mfilename("fullpath")));
            if isempty(which("bids.layout"))
                BIDS = fullfile(root, "bids-matlab");
                if exist(BIDS, "dir")
                    disp("Adding path: " + BIDS)
                    addpath(BIDS)
                else
                    error("Cannot find 'bids-matlab' path: " + BIDS)
                end
            end
            if isempty(which("spm"))
                spm = fullfile(root, "spm");
                if exist(spm, "dir")
                    disp("Adding path: " + spm)
                    addpath(spm)
                else
                    error("Cannot find 'spm' path: " + spm)
                end
            end

            % Load the BIDS-layout
            obj.layout = bids.layout(varargin{:});

        end
    end
end

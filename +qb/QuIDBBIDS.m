classdef QuIDBBIDS
    %   ___       ___ ___  ___ ___ ___ ___  ___ 
    %  / _ \ _  _|_ _|   \| _ ) _ )_ _|   \/ __|
    % | (_) | || || || |) | _ \ _ \| || |) \__ \
    %  \__\_\\_,_|___|___/|___/___/___|___/|___/
    %
    % For more information, see the <a href="matlab: web('https://github.com/Donders-Institute/quidbbids')">QuIDBBIDS GitHub repository</a>

    properties
        layout
    end

    methods
        function obj = QuIDBBIDS(varargin)

            % Set the Matlab-path
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
            if isempty(which("nifti"))
                nii = fullfile(root, "spm_readwrite_nii");
                if exist(nii, "dir")
                    disp("Adding path: " + nii)
                    addpath(nii)
                else
                    error("Cannot find 'spm_readwrite_nii' path: " + nii)
                end
            end

            % Load the BIDS-layout
            obj.layout = bids.layout(varargin{:});

        end
    end
end

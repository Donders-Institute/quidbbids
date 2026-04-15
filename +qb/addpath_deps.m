function addpath_deps()
%ADDPATH_DEPS Adds the QuIDBBIDS dependencies to the MATLAB path if needed
%
% This function automatically handles:
%   - MATLAB Add-Ons (enables them if installed but disabled)
%   - Regular dependencies are added recursively with all subfolders
%   - 'sepia', 'spm', 'bids-matlab' are added with their root folder only,
%     including running the 'sepia_addpath()' function
%
% See also: ADDPATH, GENPATH, MATLAB.ADDONS

% Skip entirely if deployed
if isdeployed
    warning('QuIDBBIDS:Deployed:MATLABPath', 'Running in deployed mode, so MATLAB path cannot be altered/restored. This may cause issues with some workers (e.g. QSM/MCR/MWI)!')
    return
end

rootdir = fileparts(fileparts(mfilename("fullpath")));
for toolbox = dir(fullfile(rootdir, "dependencies"))'
    
    % Check if the dependency is on the path already
    if contains(path, [filesep toolbox.name]) || any(strcmp(toolbox.name, [".", ".."]))
        continue
    end

    % Enable the add-onn or add the path to the dependency
    toolpath = fullfile(rootdir, "dependencies", toolbox.name);
    if toolbox.isdir && length(dir(fullfile(toolpath, '*'))) == 3   % Only a .git file is present if not initialized
        warning('QuIDBBIDS:Dependency:MissingToolbox', 'Empty dependency: %s\nPossible solution:\ngit submodule update --init --recursive', toolpath)
        continue
    elseif any(strcmp(toolbox.name, ["sepia", "spm", "bids-matlab"]))
        addtoolbox(toolpath, false)     % Add the rootfolder only
        if strcmp(toolbox.name, "sepia")
            sepia_addpath()
        end
    else
        addtoolbox(toolpath, true)      % Add everything
    end
    
end

% Add the custom workers to the path
workerpath = fullfile(fileparts(qb.resetconfig(false)), 'workers');
if ~contains(path, workerpath)
    disp("Adding path: " + workerpath)
    addpath(workerpath)
end


function addtoolbox(toolpath, recursive)
% Add an external toolbox/dependency to the MATLAB path.
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
%               with all subfolders

arguments
    toolpath  {mustBeFolder}
    recursive (1,1) logical
end

[~, toolname] = fileparts(toolpath);
if any(strcmp(toolname, matlab.addons.installedAddons().Name)) && ~matlab.addons.isAddonEnabled(toolname)
    disp("Enabling add-on: " + toolname)
    matlab.addons.enableAddon(toolname)
elseif isfolder(toolpath)
    disp("Adding path: " + toolpath)
    if recursive
        addpath(genpath(toolpath))
    else
        addpath(toolpath)
    end
else
    error('QuIDBBIDS:Dependency:MissingToolbox', "Cannot find '%s' on the MATLAB-path, please make sure it is installed", toolname)
end

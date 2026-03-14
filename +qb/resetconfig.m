function config_default = resetconfig(force)
%RESETCONFIG Reset the QuIDBBIDS user configuration to the factory defaults.
%
% CONFIG_DEFAULT = RESETCONFIG() restores the `config_default.json` file in the QuIDBBIDS user settings
% directory to the factory default configuration. Any existing configuration file will be overwritten.
%
% CONFIG_DEFAULT = RESETCONFIG(FORCE) controls whether an existing configuration file is overwritten.
% If FORCE is false and the file already exists, it will be left unchanged.
%
% OUTPUT
%   CONFIG_DEFAULT - The fullpath of the `config_default.json` file that was written to disk.

arguments
    force logical = true
end

config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.json");
if ~force && isfile(config_default)
    return
end

disp("🔧 Creating factory default configuration: " + config_default)
if isfile(config_default)
    delete(config_default)
end
[pth, name, ext] = fileparts(config_default);
[~,~] = mkdir(fullfile(pth, 'workers'));    % Also create the workers subfolder
copyfile(fullfile(fileparts(mfilename("fullpath")), "private", name + ext), config_default)
writelines(["# QuIDBBIDS user settings", "", ...
            "## Default Configuration", ...
            "This folder contains the default configuration settings used by QuIDBBIDS. You may adapt the `config_default.json` file to suit your needs, for example to reflect acquisition conventions at your institute.", "",...
            "Do not use this file to adjust study-specific settings, as those are stored in the corresponding bids/derivatives directory.", "", ...
            "If the configuration file is deleted, it will automatically be restored from the factory default.", "", ...
            "## Workers", ...
            "Custom workers can be placed in the `workers` folder. Any file following the naming pattern `*Worker*.m` will automatically be detected and made available alongside the built-in (factory) workers."], ...
            fullfile(pth, 'README.md'))

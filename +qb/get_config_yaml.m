function config = get_config_yaml(configfile, config)
%GET_CONFIG_YAML Helper function to read and optionally write QuIDBBIDS configuration file.
%
% CONFIG = GET_CONFIG_YAML(CONFIGFILE) reads the configuration from the specified CONFIGFILE.
% If it does not exist, a default configuration is copied from the user's HOME directory.
%
% CONFIG = GET_CONFIG_YAML(CONFIGFILE, CONFIG) writes the provided CONFIG struct to CONFIGFILE
% in YAML format. This updates or creates the configuration file.
%
% Inputs:
%   CONFIG - A struct with configuration parameters. If provided, GETCONFIG writes this
%            data to the CONFIGFILE, else it reads it from CONFIGFILE.
%
% Output:
%   CONFIG - A struct with the loaded configuration settings.
%
% The function ensures that a default config exists in:
%   <HOME>/.quidbbids/<version>/config_default.yaml
%
% Usage:
%   config = get_config_yaml("myconfig.yaml");
%   get_config_yaml("myconfig.yaml", config);

arguments (Input)
    configfile   {mustBeTextScalar}
    config (1,1) struct = struct()
end

arguments (Output)
    config struct
end

% Create a default configfile if it does not exist
config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.yaml");
if ~isfile(config_default)
    disp("Creating default configuration file: " + config_default)
    [pth, name, ext] = fileparts(config_default);
    [~,~] = mkdir(pth);
    copyfile(fullfile(fileparts(mfilename("fullpath")), name + ext), config_default)
end

% Write or read the study configuration data (create if needed)
if nargin > 1
    yaml.dumpFile(configfile, config)
else
    if ~isfile(configfile)
        disp("Writing study configuration to: " + configfile)
        [~,~] = mkdir(fileparts(configfile));
        copyfile(config_default, configfile)
    end
    config = yaml.loadFile(configfile);

    % Check for version conflicts
    if config.version ~= qb.version()
        warning("QuIDBBIDS:Config:VersionMismatch", "The config file version (%s) does not match the current QuIDBBIDS version (%s). Please update your config file if needed", config.version, qb.version())
    end
end

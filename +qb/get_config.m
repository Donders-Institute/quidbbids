function config = get_config(configfile, config)
%GET_CONFIG_JSON Helper function to read and optionally write QuIDBBIDS configuration file.
%
% CONFIG = GET_CONFIG_JSON(CONFIGFILE) reads the configuration from the specified CONFIGFILE.
% If it does not exist, a default configuration is copied from the user's HOME directory.
%
% CONFIG = GET_CONFIG_JSON(CONFIGFILE, CONFIG) writes the provided CONFIG struct to CONFIGFILE
% in JSON format. This updates or creates the configuration file.
%
% Inputs:
%   CONFIG - A struct with configuration parameters. If provided, GETCONFIG writes this
%            data to the CONFIGFILE, else it reads it from CONFIGFILE.
%
% Output:
%   CONFIG - A struct with the loaded configuration settings.
%
% The function ensures that a default config exists in:
%   <HOME>/.quidbbids/<version>/config_default.json
%
% Usage:
%   config = get_config("myconfig.json");
%   get_config("myconfig.json", config);

arguments (Input)
    configfile   {mustBeTextScalar}
    config (1,1) struct = struct()
end

arguments (Output)
    config struct
end

% Create a default configfile if it does not exist
config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.json");
if ~isfile(config_default)
    disp("Creating default configuration file: " + config_default)
    [pth, name, ext] = fileparts(config_default);
    [~,~] = mkdir(pth);
    copyfile(fullfile(fileparts(mfilename("fullpath")), name + ext), config_default)
end

% Write or read the study configuration data (create if needed)
if nargin > 1       % Write JSON
    fid = fopen(configfile, 'w');
    fprintf(fid, '%s', jsonencode(config, 'PrettyPrint', true));
    fclose(fid);
else                % Read JSON
    if ~isfile(configfile)
        disp("Writing study configuration to: " + configfile)
        [~,~] = mkdir(fileparts(configfile));
        copyfile(config_default, configfile)
    end
    config = jsondecode(fileread(configfile));

    % Check for version conflicts
    try
        if ~strcmp(config.version.value, qb.version())
            warning("QuIDBBIDS:Config:VersionMismatch", "The config file version (%s) does not match the current QuIDBBIDS version (%s). Please update your config file if needed", config.version.value, qb.version())
        end
    catch exception
        warning("QuIDBBIDS:Config:ParseError", "Could not parse: %s", configfile)
    end
end

function config = get_config_toml(configfile, config)
%GET_CONFIG_TOML Helper function to read and optionally write QuIDBBIDS configuration file.
%
% CONFIG = GET_CONFIG_TOML(CONFIGFILE) reads the configuration from the specified CONFIGFILE.
% If it does not exist, a default configuration is copied from the user's HOME directory.
%
% CONFIG = GET_CONFIG_TOML(CONFIGFILE, CONFIG) writes the provided CONFIG struct to CONFIGFILE
% in TOML format. This updates or creates the configuration file.
%
% Inputs:
%   CONFIG - A struct with configuration parameters. If provided, GETCONFIG writes this
%            data to the CONFIGFILE, else it reads it from CONFIGFILE.
%
% Output:
%   CONFIG - A struct with the loaded configuration settings.
%
% The function ensures that a default config exists in:
%   <HOME>/.quidbbids/<version>/config_default.toml
%
% Usage:
%   config = get_config_toml("myconfig.toml");
%   get_config_toml("myconfig.toml", config);

arguments (Input)
    configfile   {mustBeTextScalar}
    config (1,1) struct = struct()
end

arguments (Output)
    config struct
end

% Create a default configfile if it does not exist
config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.toml");
if ~isfile(config_default)
    disp("Creating default configuration file: " + config_default)
    [pth, name, ext] = fileparts(config_default);
    [~,~] = mkdir(pth);
    copyfile(fullfile(fileparts(mfilename("fullpath")), name + ext), config_default)
end

% Write or read the study configuration data (create if needed)
if nargin > 2
    toml.write(configfile, config);
else
    if ~isfile(configfile)
        disp("Writing study configuration to: " + configfile)
        [~,~] = mkdir(fileparts(configfile));
        copyfile(config_default, configfile)
    end
    config = toml.map_to_struct(toml.read(configfile));
    config = castInt64ToDouble(config);

    % Check for version conflicts
    if config.version ~= qb.version()
        warning("The config file version (" + config.version + ") does not match the current QuIDBBIDS version (" + qb.version() + "). Please update your config file if needed.")
    end
end


function config = castInt64ToDouble(config)
% Recursively casts all int64 values in CONFIG into doubles.
%
% CONFIG = CASTINT64TODOUBLE(CONFIG) traverses CONFIG and converts all int64 scalars and
% arrays into doubles. Useful for reading TOML files where integers are parsed as int64.

if isstruct(config)
    f = fieldnames(config);
    for k = 1:numel(f)
        config.(f{k}) = castInt64ToDouble(config.(f{k}));
    end
elseif iscell(config)
    config = cellfun(@castInt64ToDouble, config, 'UniformOutput', false);
elseif isa(config, 'int64')
    config = double(config);
end

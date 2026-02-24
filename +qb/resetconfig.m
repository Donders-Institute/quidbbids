function resetconfig()
%RESETCONFIG Resets the config_default.json file in your home directory to factory default

config_default = fullfile(char(java.lang.System.getProperty("user.home")), ".quidbbids", qb.version(), "config_default.json");

disp("🔧 Creating factory default configuration: " + config_default)
if isfile(config_default)
    delete(config_default)
end
[pth, name, ext] = fileparts(config_default);
[~,~] = mkdir(pth);
copyfile(fullfile(fileparts(mfilename("fullpath")), "private", name + ext), config_default)

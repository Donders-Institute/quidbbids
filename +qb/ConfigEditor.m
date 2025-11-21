function [configfile, config] = configeditor(configfile, workers)
% [CONFIGFILE, CONFIG] = CONFIGEDITOR(CONFIGFILE, WORKERS)
% 
% Opens a GUI for editing QuIDBBIDS configuration files
%
% Inputs:
%   CONFIGFILE - Path to QuIDBBIDS config file (string/char). If empty or
%                not provided, a file dialog will open.
%   WORKERS    - Cell array of worker names to edit. If empty or not
%                provided, all workers are included.
%
% Outputs:
%   CONFIGFILE - Path to the configuration file used
%   CONFIG     - Modified configuration structure
% 
% Example:
%   [configfile, config] = qb.configeditor();
%   [configfile, config] = qb.configeditor('config.json', {'General', 'QSMWorker'})

if nargin < 1 || isempty(configfile)
    [f,p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file');
    if isequal(f,0)
        % User cancelled: return empties
        configfile = [];
        config = [];
        return
    end
    configfile = fullfile(p,f);
end
if nargin < 2
    workers = [];
end

app = qb.ConfigEditorGUI(configfile, workers);
uiwait(app.Fig);   % Pause until window closes

configfile = app.ConfigFile;
config = app.Config;

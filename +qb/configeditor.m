function [configfile, config] = configeditor(configfile, config, workers, BIDS)
% [CONFIGFILE, CONFIG] = CONFIGEDITOR(CONFIGFILE, WORKERS)
% 
% Opens a GUI for editing QuIDBBIDS configuration files
%
% Inputs:
%   CONFIGFILE - Path to QuIDBBIDS config file (string/char). If empty or not
%                provided, a file dialog will open.
%   CONFIG     - QuIDBBIDS configuration structure. If empty or not provided,
%                then it is loaded from CONFIGFILE.
%   WORKERS    - Cell array of worker names to edit. If empty or not provided,
%                all workers are included.
%   BIDS       - BIDS layout object to be used for editing BIDS inclusion filters
%
% Outputs:
%   CONFIGFILE - Path to the configuration file used
%   CONFIG     - Modified configuration structure
% 
% Example:
%   [configfile, config] = qb.configeditor();
%   [configfile, config] = qb.configeditor('config.json', {'General', 'QSMWorker'})

arguments
    configfile {mustBeTextScalar} = ''
    config     struct             = []          % Configuration struct loaded from the config file
    workers    cell               = {}
    BIDS       struct             = struct()    % BIDS layout object to be used for editing BIDS inclusion filters
end

app = qb.GUI.ConfigEditor(configfile, config, workers, BIDS);

if nargout
    uiwait(app.Fig);   % Pause until window closes
    configfile = app.ConfigFile;
    config = app.Config;
end

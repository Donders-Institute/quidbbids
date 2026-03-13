classdef Logging < handle
%LOGGING Keeps logs for workers that work on a subject in a BIDS dataset
%
% Log messages are displayed in the terminal as well as saved in the originating
% subject folder. In addition warnings, errors and exceptions are saved in error
% and warning logfiles, in order to facilitate QC workflows.
%
% See also: qb.QuIDBBIDS (for overview)

properties
    worker  % The worker that is logging its messages
    logdir  % The directory where the logs will be stored
end

methods

    function obj = Logging(worker)
        % Constructor for the Logging class

        arguments
            worker  qb.workers.Worker
        end

        obj.worker = worker;
        obj.logdir = fullfile(obj.worker.outputdir, 'logs', regexp(class(worker), '[^.]+$', 'match', 'once'));   % Only take the class basename, i.e. the last part after the dot
    end

    function debug(obj, message, varargin)
        %INFO Writes a formatted messages for debugging purposes
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.debug("This is a debug message: %s", var1)
        %
        % See also: sprintf

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        obj.info(message, {"DEBUG"}, varargin{:})
    end

    function verbose(obj, message, varargin)
        %INFO Writes a formatted message to a logfile only
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.verbose("This is a verbose message: %s", var1)
        %
        % See also: sprintf

        % NB: varargin(1): {level_} = private use to set the log level

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        % Parse the private level_ argument if provided
        if ~isempty(varargin) && iscell(varargin{1})
            level_      = varargin{1}{1};
            varargin(1) = [];
        else
            level_      = "VERBOSE";
        end

        % Log to disk
        [~,~]   = mkdir(obj.logdir);
        logfile = fullfile(obj.logdir, [obj.sub_ses() '.log']);
        fid     = fopen(logfile, 'a');
        if fid ~= -1
            fprintf(fid, "[%s] %s\t| %s\n", datetime('now'), level_, sprintf(message, varargin{:}));
            fclose(fid);
        else
            warning("QuIDBBIDS:Logging:IOError", "[Error %d] Failed to write to %s", fid, logfile)
        end

        % TODO: Also log in the terminal if user sets the terminal logging level to VERBOSE
        % if strcmpi(obj.config.loglevel, "VERBOSE")
        %     fprintf('%s\t| %s\n', level_, message)  % TODO: colorize it with cprintf from the File Exchange???
        % end
    end

    function info(obj, message, varargin)
        %INFO Writes a formatted message to a logfile and to the terminal
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.info("This is an info message: %s", var1)
        %
        % See also: sprintf

        % NB: varargin(1): {level_} = private use to set the log level

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        % Parse the private level_ argument if provided
        if ~isempty(varargin) && iscell(varargin{1})
            level_      = varargin{1}{1};
            varargin(1) = [];
        else
            level_      = "INFO";
        end

        % Log to disk
        obj.verbose(message, {level_}, varargin{:})

        % Also log in the terminal
        fprintf('%s\t| %s\n', level_, sprintf(message, varargin{:}))  % TODO: colorize it with cprintf from the File Exchange???
    end

    function warning(obj, message, varargin)
        %WARNING Writes a formatted message to a warningfile, a logfile and to the terminal
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.warning("This is a warning message: %s", var1)
        %
        % See also: warning, sprintf

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        % Add the warning to the stack trace
        ws = warning('off', 'all');
        warning(sprintf("QuIDBBIDS:%s:Warning", obj.worker.name), message, varargin{:})
        warning(ws)
    
        % Log on disk and in the terminal
        obj.loghandler(message, '_warnings', varargin{:})
    end

    function error(obj, message, varargin)
        %ERROR Writes a formatted message to an errorfile, a logfile and to the terminal
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.error("This is an error message: %s", var1)
        %
        % See also: error, sprintf

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        % Quietly add the error to the stack trace for easier debugging in the terminal, but also log it on disk and in the terminal
        try
            error(sprintf("QuIDBBIDS:%s:Error", obj.worker.name), message, varargin{:});
        catch ME
            obj.loghandler(message, '_errors', varargin{:})
        end
    end

    function exception(obj, message, varargin)
        %EXCEPTION Writes a formatted message to an errorfile, a logfile and to the terminal. Then it raises the error
        %
        % Input:
        %   MESSAGE : Text message with optional format specifiers
        %   VARARGIN: Optional arguments to be used with the format specifiers in MESSAGE
        %
        % Usage:
        %   obj.exception("This is an exception message: %s", var1)
        %
        % See also: error, sprintf

        arguments
            obj
            message {mustBeText}
        end

        arguments (Repeating)
            varargin
        end

        obj.loghandler(message, '_errors', varargin{:})             % Log on disk and normally
        error('QuIDBBIDS:FatalException', message, varargin{:})     % Also raise an error
    end

end

methods (Access = ?TestLogging)

    function subses = sub_ses(obj)
        % Parses the sub-#_ses-# prefix from a BIDS.subjects item.
        if ~isfield(obj.worker.subject, 'path') || ~isfield(obj.worker.BIDS, 'pth')
            subses = 'sub-unknown_ses-unknown';
        else
            subses = replace(erase(obj.worker.subject.path, [obj.worker.BIDS.pth filesep]), filesep,'_');
        end
    end

    function loghandler(obj, message, suffix, varargin)
        % Writes a formatted message to warning/error logfiles as well as to the info file and terminal

        % Write to the warning/error files
        [~,~]   = mkdir(obj.logdir);
        logfile = fullfile(obj.logdir, [obj.sub_ses() suffix '.log']);
        fid     = fopen(logfile, 'a');
        if fid ~= -1
            fprintf(fid, "[%s] %s\n", datetime('now'), sprintf(message, varargin{:}));
            fclose(fid);
        else
            warning("QuIDBBIDS:Logging:IOError", "[Error] Failed to write to %s", logfile)
        end

        % Write to the info file and terminal
        obj.info(message, {upper(suffix(2:end-1))}, varargin{:})   % Assumes suffix starts with a '_' and ends with a plural 's'
    end

end

end

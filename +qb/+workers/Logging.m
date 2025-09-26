classdef Logging < handle
    %LOGGING Keeps logs for workers that work on a subject in a BIDS dataset
    % 
    % Log messages are displayed in the terminal as well as saved in the originating
    % subject folder. In addition warnings, errors and exceptions are saved in error
    % and warning sidecar files, in order to facilitate QC workflows.
    %
    % See also: qb.QuIDBBIDS (for overview)


    properties
        outputdir   % The QuIDBBIDS output directory where the logs will be stored
        worker      % The name of the worker that is logging its messages
    end
    

    methods

        function obj = Logging(worker)
            %LOGGER Initializes the logging object

            arguments
                worker qb.workers.Worker
            end
            
            obj.outputdir = fullfile(worker.quidb.outputdir, 'logs', class(obj));
            obj.worker    = worker;
            [~,~]         = mkdir(obj.outputdir);

        end

        function debug(obj, message)
            %INFO Writes a formatted messages for debugging purposes

            arguments
                obj
                message {mustBeText}
            end

            obj.info(message, "DEBUG")
        end

        function verbose(obj, message, level_)
            %INFO Writes a formatted message to a logfile only. level_ = private

            arguments
                obj
                message {mustBeText}
                level_  {mustBeText} = "VERBOSE"
            end

            % Log to disk
            logfile = fullfile(obj.outputdir, [obj.sub_ses() '.log']);
            fid     = fopen(logfile, 'a');
            if fid ~= -1
                fprintf(fid, "[%s] %s\t| %s\n", datetime('now'), level_, message);
                fclose(fid);
            else
                warning("[Error %d] Failed to write to %s", fid, logfile)
            end

            % TODO: Also log in the terminal if user sets the terminal logging level to VERBOSE
            % if strcmpi(quidb.config.loglevel, "VERBOSE")
            %     fprintf('%s\t| %s\n', level_, message)  % TODO: colorize it with cprintf from the File Exchange???
            % end
        end

        function info(obj, message, level_)
            %INFO Writes a formatted message to a logfile and to the terminal. level_ = private

            arguments
                obj
                message {mustBeText}
                level_  {mustBeText} = "INFO"
            end

            % Log to disk
            obj.verbose(message, level_)

            % Also log in the terminal
            fprintf('%s\t| %s\n', level_, message)  % TODO: colorize it with cprintf from the File Exchange???
        end

        function warning(obj, message)
            %WARNING Writes a formatted message to a warningfile, a logfile and to the terminal

            arguments
                obj
                message {mustBeText}
            end

            obj.loghandler(message, '_warnings')    % Log on disk and normally
        end

        function error(obj, message)
            %ERROR Writes a formatted message to an errorfile, a logfile and to the terminal

            arguments
                obj
                message {mustBeText}
            end

            obj.loghandler(message, '_errors')      % Log on disk and normally
        end

        function exception(obj, message)
            %EXCEPTION Writes a formatted message to an errorfile, a logfile and to the terminal. Then it raises the error

            arguments
                obj
                message {mustBeText}
            end

            obj.loghandler(message, '_errors')      % Log on disk and normally
            error(message)                          % Also raise an error
        end

    end

    methods (Access = private)

        function subses = sub_ses(obj)
            % Parses the sub-#_ses-# prefix from a BIDS.subjects item
            subses = replace(erase(obj.worker.subject.path, [obj.worker.quidb.BIDS.pth filesep]), filesep,'_');
        end

        function loghandler(obj, message, suffix)
            % Writes a formatted message to warning/error sidecar files as well as to the info file and terminal

            % Write to the warning/error files
            logfile = fullfile(obj.outputdir, [obj.sub_ses() suffix '.log']);
            fid     = fopen(logfile, 'a');
            if fid ~= -1
                fprintf(fid, "[%s] %s\n", datetime('now'), message);
                fclose(fid);
            else
                warning("[Error %d] Failed to write to %s", fid, logfile)
            end

            % Write to the info file and terminal
            obj.info(message, upper(suffix(2:end-1)))   % Assumes suffix starts with a '_' and ends with a plural 's'
        end

    end

end

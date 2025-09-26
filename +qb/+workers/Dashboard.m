classdef Dashboard < handle
    % Provides a status overview of the work that is being or has been done


    properties
        BIDS        % The BIDS layout that the workers are working on
        logdir      % The directory where the logfiles reside
    end


    methods

        function obj = Dashboard(BIDS, logdir)

            arguments
                BIDS    struct
                logdir  {mustBeFolder}
            end

            obj.BIDS   = BIDS;
            obj.logdir = logdir;
        end

        function busy = working_on(obj)
            %WORKING_ON Returns the list of subjects currently being processed
            busy = [];
            for subject = obj.BIDS.subjects
                lock_file = fullfile(subject.path, [class(obj) '_worker.lock']);
                if isfile(lock_file)
                    busy(end+1) = subject;
                end
            end
        end

        function done = work_done(obj)
            %WORK_DONE Returns the list of subjects that have completed processing
            done = [];
            for subject = obj.BIDS.subjects
                done_file = fullfile(subject.path, [class(obj) '_worker.done']);
                if isfile(done_file)
                    done(end+1) = subject;
                end
            end
        end

        function subjects = has_warnings(obj, verbose)
            %HAS_WARNINGS Returns the list of subjects that encountered warnings
            
            arguments
                obj      qb.QuIDBBIDS
                verbose  (1,1) logical = false
            end

            subjects = [];
            for subject = obj.BIDS.subjects
                warning_file = fullfile(obj.logdir, [obj.sub_ses(subject) '_warnings.log']);
                if isfile(warning_file)
                    subjects(end+1) = subject;
                    if verbose
                        fprintf("Warnings in %s:\n", subject.path);
                        lines = strtrim(strsplit(fileread(warning_file), '\n'));
                        fprintf('| %s\n', lines{:});
                    end
                end
            end
        end

        function subjects = has_errors(obj, verbose)
            %HAS_ERRORS Returns the list of subjects that encountered errors

            arguments
                obj      qb.QuIDBBIDS
                verbose  (1,1) logical = false
            end
            
            subjects = [];
            for subject = obj.BIDS.subjects
                error_file = fullfile(obj.logdir, [obj.sub_ses(subject) '_errors.log']);
                if isfile(error_file)
                    subjects(end+1) = subject;
                    if verbose
                        fprintf("Errors in %s:\n", subject.path);
                        lines = strtrim(strsplit(fileread(error_file), '\n'));
                        fprintf('| %s\n', lines{:});
                    end
                end
            end
        end

    end


    methods (Access = private)

        function subses = sub_ses(obj, subject)
            % Parses the sub-#_ses-# prefix from a BIDS.subjects item
            subses = replace(erase(subject.path, [obj.BIDS.pth filesep]), filesep,'_');
        end

    end

end
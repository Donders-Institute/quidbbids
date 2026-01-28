classdef Dashboard < handle
%DASHBOARD Provides a status overview of the work that is being or has been done
%
% See also: qb.workers.Manager


properties
    coord       % The BIDS layout that the workers are working on
    workitem    % The workitem of interest
    subjects    % The subjects being processed
    jobIDs      % A subject map with qsubfeval job identifiers
    fig         % The dashboard figure (if any)
end


methods

    function obj = Dashboard(coord, workitem, subjects, jobIDs)
        %DASHBOARD Constructs a Dashboard GUI object

        arguments
            coord    struct
            workitem {mustBeTextScalar}
            subjects string
            jobIDs   containers.Map
        end

        obj.coord    = coord;
        obj.workitem = workitem;
        obj.subjects = subjects;
        obj.jobIDs   = jobIDs;
        if obj.coord.config.General.useHPC.value
            obj.fig = qb.GUI.DashboardHPC(obj.coord, obj.workitem, obj.jobIDs); % TODO: implement
        else
            obj.fig = timer;    % Lightweight dummy handle object
            delete(obj.fig)
        end
    end

    function completed = work_done(obj)
        %WORK_DONE Returns a list of jobID keys (subject names) that have completed

        completed = string.empty;
        ws = warning('off', 'FieldTrip:qsub:jobNotAvailable');
        for subject = obj.subjects
            [~, options] = qsubget(obj.jobIDs(subject), 'output', 'cell', 'StopOnError', StopOnError);
            if ~isempty(options)
                completed(end+1) = subject;                 %#ok<AGROW>
                writelines(options.diary, fullfile(obj.coord.outputdir, 'logs', sprintf('diary_%s.txt',subject)), WriteMode='append');
            end
        end
        warning(ws)
    end

    function update(obj)
        %UPDATE Updates the dashboard figure (if any)
        if isvalid(obj.fig)
            % TODO: implement
        end
    end

    function subjects = has_warnings(obj, verbose, level_)
        %HAS_WARNINGS Returns the list of subjects that encountered warnings
        
        arguments
            obj      qb.QuIDBBIDS
            verbose  (1,1) logical = false
            level_   string {mustBeMember(level_, ["warnings", "errors"])} = "warnings"
        end

        subjects = [];
        for worker = dir(fullfile(obj.coord.outputdir, 'logs', '*Worker'))'
            for subject = obj.subjects
                logfile = fullfile(obj.coord.outputdir, 'logs', worker.name, sprintf('%s_%s.log', subject, level_));
                if isfile(logfile) && dir(logfile).bytes > 0
                    subjects(end+1) = subject;                  %#ok<AGROW>
                    if verbose
                        fprintf("QuIDBBIDS %s found for %s:\n", level_, subject)
                        fprintf('| %s\n', readlines(logfile))
                    end
                end
            end
        end
        subjects = unique(subjects);
    end

    function subjects = has_errors(obj, verbose)
        %HAS_ERRORS Returns the list of subjects that encountered errors

        arguments
            obj      qb.QuIDBBIDS
            verbose  (1,1) logical = false
        end
        
        subjects = obj.has_warnings(verbose, "errors");
    end

end


methods (Access = private)

    function subses = sub_ses(obj, subject)
        % Parses the sub-#_ses-# prefix from a BIDS.subjects item
        subses = replace(erase(subject.path, [obj.coord.BIDS.pth filesep]), filesep,'_');
    end

end

end
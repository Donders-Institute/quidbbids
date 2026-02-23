classdef Dashboard < handle
%DASHBOARD Provides a status overview of the work that is being or has been done
%
% See also: qb.workers.Manager


properties
    coord       % The coordinator with the BIDS layout that the workers are working on
    workitem    % The workitem of interest
    jobIDs      % A subses map with qsubfeval job identifiers
    completed = string.empty()   % The list of subses keys of jobs that have completed
    fig         % The dashboard figure (if any)
end


methods
    
    function obj = Dashboard(coord, workitem, jobIDs)
        %DASHBOARD Constructs a Dashboard GUI object
        
        arguments
            coord    qb.workers.Coordinator
            workitem {mustBeTextScalar}
            jobIDs   containers.Map
        end
        
        obj.coord    = coord;
        obj.workitem = workitem;
        obj.jobIDs   = jobIDs;
        if obj.coord.config.General.useHPC.value || obj.coord.config.General.useParallel.value
            % obj.fig = qb.GUI.DashboardHPC(obj.coord, obj.workitem, obj.jobIDs); % TODO: implement
            obj.fig = waitbar(0, 'Completed jobs', 'Name','QuIDBBIDS WIP dashboard');   % WIP dummy handle object
        else
            obj.fig = timer;    % Lightweight dummy handle object
            delete(obj.fig)
        end
    end
    
    function completed = work_done(obj)
        %WORK_DONE Returns a list of jobID keys (subject_session names) that have completed and writes their diary to disk
        
        completed = obj.completed;
        if isempty(obj.jobIDs.keys)
            return
        end
        
        ws = warning('off', 'FieldTrip:qsub:jobNotAvailable');
        for subses = string(obj.jobIDs.keys)
            
            % Skip if the job was already found as completed
            if ismember(subses, completed)
                continue
            end

            % Collect the job output and write the diary to disk
            if obj.coord.config.General.useHPC.value
                [~, options] = qsubget(obj.jobIDs(subses), 'output', 'cell', 'StopOnError', false);
                if ~isempty(options)
                    completed(end+1) = subses;              %#ok<AGROW>
                    diary            = char(obj.ft_getopt(options, 'diary'));
                    writelines(diary, fullfile(obj.coord.outputdir, 'logs', sprintf('diary_%s.txt',subses)), WriteMode='append');
                end
            elseif obj.coord.config.General.useParallel.value && ismember(obj.jobIDs(subses).State, {'finished','failed'})
                completed(end+1) = subses;                  %#ok<AGROW>
                if strcmp(obj.jobIDs(subses).State, 'failed')
                    warning("QuIDBBIDS:Dashboard:JobMonitor", "Producing %s for subject %s failed:\n%s", obj.workitem, subses, getReport(obj.jobIDs(subses).Error,'extended'))
                end
            end
        end
        warning(ws)
        obj.completed = unique(completed);
    end
    
    function update(obj)
        %UPDATE Updates the dashboard figure (if any)
        if isvalid(obj.fig)
            % TODO: implement
            waitbar(length(obj.completed)/length(obj.jobIDs.keys), obj.fig)
        end
    end
    
    function subjects = has_warnings(obj, verbose, level_)
        %HAS_WARNINGS Returns the list of subjects that encountered warnings
        
        arguments
            obj
            verbose  (1,1) logical = false
            level_   string {mustBeMember(level_, ["warnings", "errors"])} = "warnings"
        end
        
        subjects = string.empty();
        for worker = dir(fullfile(obj.coord.outputdir, 'logs', '*Worker'))'
            for subses = string(obj.jobIDs.keys)

                logfile = fullfile(obj.coord.outputdir, 'logs', worker.name, sprintf('%s_%s.log', subses, level_));
                if isfile(logfile) && dir(logfile).bytes > 0
                    subjects(end+1) = subses;                   %#ok<AGROW>
                    if verbose
                        fprintf("\n⛔ QuIDBBIDS %s found for %s:\n", level_, subses)
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
            obj
            verbose  (1,1) logical = false
        end
        
        subjects = obj.has_warnings(verbose, "errors");
    end
    
end


methods (Access = private)
    
    function val = ft_getopt(~, opt, key)
        % FT_GETOPT(OPT, KEY) gets the value of a specified option from a cell-array with key-value pairs.
        %
        % opt = cell-array
        % key = string
        
        % get the key-value from the cell-array
        if mod(length(opt),2)
            error('optional input arguments should come in key-value pairs, i.e. there should be an even number');
        end
        
        % the 1st, 3rd, etc. contain the keys, the 2nd, 4th, etc. contain the values
        keys = opt(1:2:end);
        vals = opt(2:2:end);
        
        if ~all(cellfun(@ischar, keys))
            error('optional input arguments should come in key-value pairs')
        end
        
        hit = find(strcmpi(key, keys));
        if isempty(hit)
            val = [];
        elseif isscalar(hit)
            val = vals{hit};
        else
            error('multiple input arguments with the same name');
        end
    end
    
end

end

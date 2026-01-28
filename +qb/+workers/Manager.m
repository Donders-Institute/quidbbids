classdef Manager < handle
%MANAGER Manages the entire workflow to make the end products that the user wants
%
% This class defines the common interface and base functionality for interacting with the user,
% composing workflows, setting config parameters, creating a team of workers from the pool, and
% putting the team to work.
%
% Interactive workflow:
%   0. User initializes the workflow and calls Manager
%   1. Manager loads an existing workflow from the output directory (if present) and asks user
%      what products to make
%   2. Manager assembles a team that can make the products (and asks the user for help if needed)
%   3. Manager lets the user tweak the config parameters and saves it all back in the output folder
%   4. Manager puts the team to work (subject by subject or in parallel):
%       a. For each end product, the manager asks the responsible team worker to produce it
%       b. If this worker needs a workitem to get the work done, he/she will ask another
%          team worker to produce it. In turn, that worker can ask other team workers to
%          produce their workitems -- all the way up until only raw BIDS data items are needed
%   5. Manager monitors the progress of the workers and informs the user until all work is done
%   6. Manager fetches the end products and copies them to the output directory
%
% Batch workflow:
%
% Usage:
%
% Limitation:
%   In the workflow, each workitem is always made by the same worker, i.e. it is not possible to
%   have a certain workitem produced by one worker in one part of the workflow, but in another part
%   have that same workitem produced by another worker. The alternative would be to specify the
%   complete workflow (i.e. all nodes in the graph), which is a much more complicated thing to do
%
% See also: qb.QuIDBBIDS (for overview)


properties
    team = struct()     % The resumes of the workers that will produce the products: team.(workitem) -> worker resume
    coord               % The coordinator that help the manager with administrative tasks
    force = false       % Force workers to start working, even if the subject is locked or existing results exist
end


methods

    function obj = Manager(coord)
        % Constructor for the Manager class

        arguments
            coord     qb.workers.Coordinator    % The coordinator that help the manager with administrative tasks
        end

        obj.coord = coord;                      % The coordinator that help the manager with administrative tasks
        obj.create_team()
    end

    function create_team(obj, workitems, recurse_)
        %CREATE_TEAM Selects workers from the pool that together are capable of making the
        % WORKITEMS (products).
        %
        % Asks the user for help if needed. The assembled team is stored in the TEAM property.
        %
        % NB: RECURSE_ is a private argument that should not be used

        arguments
            obj
            workitems {mustBeText} = obj.coord.products
            recurse_ logical       = false
        end

        % Reset the team
        if ~recurse_
            obj.team = struct();
        end

        % Find and select one capable worker per workitem
        for workitem = string(workitems(:)')                % The workitem with optional regexp pattern

            % First put all capable workers in the team
            for name = fieldnames(obj.coord.resumes)'       % Iterate over all available workers
                worker = obj.coord.resumes.(char(name));
                makes = worker.makes();
                match = ~cellfun(@isempty, regexp(makes, "^" + workitem + "$"));
                % Add to the team if the worker is capable
                for workitem_ = makes(match)                % Loop over the actual workitems (without optional regexp pattern)
                    if isfield(obj.team, workitem_)         % Append the worker to the list
                        if ~ismember(func2str(worker.handle), cellfun(@func2str, {obj.team.(workitem_).handle}, 'UniformOutput', false))    % Check if we haven't already added this worker
                            obj.team.(workitem_)(end+1) = worker;
                        end
                    else                                    % Or create a new list
                        obj.team.(workitem_) = worker;
                    end
                end
            end
            if all(cellfun(@isempty, regexp(fieldnames(obj.team), "^" + workitem + "$")))
                error('QuIDBBIDS:WorkItem:NotFound', 'Could not find a worker that can make: %s', workitem)
            end

            % Then select one worker per workitem and recursively add the workers needed to make the workitem
            for item = fieldnames(obj.team)'                % NB: workitem_ is without regexp pattern
                if regexp(char(item), workitem)
                    workitem_ = char(item);
                    obj.selectworker(workitem_)             % Keep the preferred worker only (if multiple)
                    if length(obj.team.(workitem_)) > 1     % User cancelled the selection
                        return
                    end
                    if ~isempty(obj.team.(workitem_).needs) % Recursively add upstream workers to the team
                        obj.create_team(obj.team.(workitem_).needs, true)
                    end
                end
            end

        end
    end

    function load_workflow(obj)
    end

    function save_workflow(obj)
        %SAVE_WORKFLOW Saves the PRODUCT and TEAM properties to the output directory
    end

    function start_workflow(obj, subjects)
        %START_WORKFLOW For each end product, asks the responsible team worker to fetch it. Logs the screen output in a diary.
        %
        % Inputs:
        %   SUBJECTS - String array with subject names for which the workflow should be executed. Default is all subjects in the BIDS layout
        %
        % Examples:
        %   mgr.start_workflow()                      % Starts the workflow for all subjects
        %   mgr.start_workflow(["sub-01", "sub-02"])  % Starts the workflow for subjects sub-01 and sub-02 only

        arguments
            obj
            subjects string = "";
        end

        % Parse the subjects for which the workflow should be executed
        if strlength(subjects) > 0
            sel = false(size(obj.coord.BIDS.subjects));
            for subject = subjects(:)'
                sel(strcmp({obj.coord.BIDS.subjects.name}, subject)) = true;
            end
            subjects = obj.coord.BIDS.subjects(sel);
        else
            subjects = obj.coord.BIDS.subjects;
        end

        % Start a diary to log the screen output
        logdir = fullfile(obj.coord.outputdir, 'logs');
        [~,~]  = mkdir(logdir);
        diary(fullfile(logdir, 'workflow_diary.txt'))
        cleanup = onCleanup(@() diary('off'));

        % Block the start button in the GUI (if any) and initialize the workers
        disp("============= Starting workflow at " + string(datetime('now')) + " =============")
        for product = obj.coord.products      % TODO: sort such that MEGREprepWorker products (if any) are fetched first
            worker = obj.team.(product).handle;
            jobIDs = containers.Map('KeyType','char', 'ValueType','char');
            for subject = subjects

                % Skip if we are not at the modality level, i.e. at the subject level while sessions are present
                if ~ismember("anat", fieldnames(subject)) || isempty(subject.anat)
                    continue
                end

                % Ask the worker to fetch the product for this subject
                args = {obj.coord.BIDS, subject, obj.coord.config, obj.coord.workdir, obj.coord.outputdir, obj.team};
                if obj.coord.config.General.useHPC.value
                    jobIDs(obj.sub_ses(subject)) = qsubfeval(worker, args{:}, product, obj.coord.config.General.HPC.value{:});  % NB: products are passed directly instead of calling fetch()
                else
                    worker(args{:}).fetch(product, obj.force);      % TODO: Catch the work done (at some point)
                end

            end

            % Monitor the progress of the workers until all work is done and report any errors or warnings
            obj.monitor_progress(product, subjects, jobIDs)
        end

        % Unblock the start button in the GUI (if any)
        disp("============= Finished workflow at " + string(datetime('now')) + " =============")
    end

    function monitor_progress(obj, workitem, subjects, jobIDs)
        %MONITOR_PROGRESS Watches over the progress of the workers until all work is done

        arguments
            obj
            workitem {mustBeTextScalar}
            subjects struct
            jobIDs   containers.Map
        end

        % Launch a dashboard
        dashboard = qb.workers.Dashboard(obj.coord, workitem, subjects, jobIDs);

        % Wait until all work is done
        while length(dashboard.work_done()) < length(jobIDs.keys)
            pause(1)
            dashboard.update()
        end

        % Report any errors or warnings
        dashboard.has_warnings(true)
        dashboard.has_errors(true)

        % Close the dashboard
        if isvalid(dashboard.fig)
            close(dashboard.fig)
        end
    end

end


methods (Access = private)

    function subses = sub_ses(obj, subject)
        % Parses the sub-#_ses-# prefix from a BIDS.subjects item
        subses = replace(erase(subject.path, [obj.coord.BIDS.pth filesep]), filesep,'_');
    end

    function selectworker(obj, workitem)
        % Helper function for CREATE_TEAM to select a worker for this (non-regexp) workitem and make him/her the "preferred worker"

        workers = obj.team.(workitem);
        if isscalar(workers)
            return
        end

        % Check if any of the workers is preferred. If not ask the user and make the worker preferred
        if ~any([workers.preferred])
            uiwait(helpdlg({"There are multiple workers that can produce: " + workitem, "Please select the one you want to use"}, "Create team"))
            chosen = qb.GUI.askuser(workers, workitem);
            if chosen
                workers(chosen).preferred = true;
            else
                return
            end
        end

        % Keep the preferred worker only
        obj.team.(workitem) = workers([workers.preferred]);
        
        if length(obj.team.(workitem)) ~= 1
            error('QuIDBBIDS:WorkItem:InvalidCount', "Expected only a single workitem, but got %d", length(obj.team.(workitem)))
        end
    end

end

end

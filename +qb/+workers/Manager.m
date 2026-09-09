classdef Manager < handle
%MANAGER Manages the entire workflow to make the deliverables that the user wants
%
% This class defines the common interface and base functionality for interacting with the user,
% composing workflows, setting config parameters, creating a team of workers from the pool, and
% putting the team to work.
%
% Workflow:
%   0. User initializes the workflow and calls Manager
%   1. Manager loads an existing workflow from the output directory (if present) and asks user
%      what deliverables to make
%   2. Manager assembles a team that can make the deliverables (and asks the user for help if needed)
%   3. Manager lets the user tweak the config parameters and saves it all back in the output folder
%   4. Manager puts the team to work (subject by subject or in parallel):
%       a. For each end deliverable, the manager asks the responsible team worker to produce it
%       b. If this worker needs a workitem to get the work done, he/she will ask another
%          team worker to produce it. In turn, that worker can ask other team workers to
%          produce their workitems -- all the way up until only raw BIDS data items are needed
%   5. Manager monitors the progress of the workers and informs the user until all work is done
%   6. Manager fetches the deliverables and copies them to the output directory
%
% Limitation:
%   In the workflow, each workitem is always made by the same worker, i.e. it is not possible to
%   have a certain workitem produced by one worker in one part of the workflow, but in another part
%   have that same workitem produced by another worker. The alternative would be to specify the
%   complete workflow (i.e. all nodes in the graph), which is a much more complicated thing to do
%
% See also: qb.QuIDBBIDS (for overview)


properties
    team = struct.empty()   % The resumes of the workers that will produce the deliverables: team.(workitem) -> worker resume
    workflow = digraph()    % The workflow graph as a MATLAB digraph object
    coord                   % The coordinator that help the manager with administrative tasks
    force = strings(1,0)    % List of workers for which the work should be forced, even if the subject is locked or existing results exist
    interactive = true      % If true, the manager will ask the user for help when needed (false = useful for automated testing)
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

    function set.force(obj, val)
        % Check if the force property is stored as a valid string row
        if ~ismember(class(val), {'string', 'char'})
            error('QuIDBBIDS:Manager:InvalidForce', 'The force property must be a string or char array')
        end
        workers = fieldnames(obj.coord.resumes);   %#ok<MCSUP>
        if strlength(val) == 0
            obj.force = strings(1,0);
        elseif all(ismember(string(val), workers))
            obj.force = string(val(:)');
        else
            error('QuIDBBIDS:Manager:InvalidForce', 'The force property must be a subset of the available workers:%s', sprintf(' "%s"', workers{:}))
        end
    end

    function create_team(obj, workitems, recurse_)
        %CREATE_TEAM Selects workers from the pool that together are capable of making the WORKITEMS (deliverables).
        %
        % Asks the user for help if needed. The assembled team is stored in the TEAM property, which is a struct
        % with fields corresponding to the workitems and value corresponding to the resume of the worker that will
        % produce the workitem.
        %
        % NB: RECURSE_ is a private argument that should not be used

        arguments
            obj
            workitems {mustBeText} = obj.coord.deliverables
            recurse_ logical       = false
        end

        % Reset the team
        if ~recurse_
            obj.team = struct();
        end

        if isempty(workitems)
            return
        end

        % Find and select one capable worker per workitem
        for workitem = string(workitems(:)')                % The workitem with optional regexp pattern

            % Filter out the raw/deriv workitems
            if startsWith(workitem, ["raw", "deriv"])
                continue
            end

            % First put all capable workers in the team
            for name = fieldnames(obj.coord.resumes)'       % Iterate over all available workers
                worker = obj.coord.resumes.(char(name));
                makes  = worker.makes();
                items  = ~cellfun(@isempty, regexp(makes, "^" + workitem + "$"));

                % Add to the team if the worker is capable
                for workitem_ = makes(items)                % Loop over the actual matching workitems (without optional regexp pattern)
                    if isfield(obj.team, workitem_)         % Append the worker to the list
                        if ~ismember(worker.name, [obj.team.(workitem_).name])    % Check if we haven't already added this worker
                            obj.team.(workitem_)(end+1) = worker;
                        end
                    else                                    % Or create a new list
                        obj.team.(workitem_) = worker;
                    end
                end
            end
            if all(cellfun(@isempty, regexp(fieldnames(obj.team), "^" + workitem + "$")))
                error('QuIDBBIDS:WorkItem:NoWorker', 'Could not find a worker + input data for making: %s', workitem)
            end

            % Then select one worker per workitem and recursively add the workers needed to make the workitem
            for item = fieldnames(obj.team)'                % NB: workitem_ is without regexp pattern
                if regexp(char(item), workitem)
                    workitem_ = char(item);
                    obj.selectworker(workitem_)             % Keep the preferred worker only (if multiple)
                    if length(obj.team.(workitem_)) > 1     % User cancelled the selection
                        return
                    end
                    obj.create_team(obj.team.(workitem_).needs, true)   % Recursively add upstream workers to the team
                end
            end

        end

        % Plot and save the team workflow graph
        if ~recurse_
            obj.workflow = obj.draw_workflow();
            H = findall(groot, Tag='workflow_graph');
            if isvalid(H)
                saveas(H, regexprep(obj.coord.workflowfile, "(.*)\.mat$", "$1.png"))
            end
        end

    end

    function members = team_members(obj)
        %TEAM_MEMBERS Returns the names of the workers in the team

        members = string.empty();
        for workitem = string(fieldnames(obj.team))'
            members(end+1) = string(obj.team.(workitem).name);  %#ok<AGROW>
        end
        if ~isempty(members)
            members = unique(members);
        end
    end

    function load_mgr(obj, workflowfile)
        %LOAD_WORKFLOW Loads all manager properties from the workflowfile

        arguments
            obj
            workflowfile {mustBeTextScalar} = obj.coord.workflowfile
        end

        if ~isfile(workflowfile)
            fprintf('🔧 No previous manager data found\n')
            return
        end

        fprintf('🔧 Loading manager data from: %s\n', workflowfile)
        load(workflowfile, 'mgr')
        obj.coord.workflowfile = workflowfile;

        % Set the manager data
        for property = string(fieldnames(mgr)')
            obj.(property) = mgr.(property);
        end
    end

    function save_mgr(obj, workflowfile)
        %SAVE_WORKFLOW Saves all manager properties to the workflowfile, except the COORD handle

        arguments
            obj
            workflowfile {mustBeTextScalar} = obj.coord.workflowfile
        end

        % Get the manager data
        for property = string(properties(obj)')
            if ~ismember(property, {'coord'})
                mgr.(property) = obj.(property);
            end
        end

        fprintf('💾 Saving manager data to: %s\n', workflowfile)
        [~,~] = mkdir(fileparts(workflowfile));
        save(workflowfile, 'mgr', '-append')
        obj.coord.workflowfile = workflowfile;
    end

    function start_workflow(obj, subjects)
        %START_WORKFLOW For each deliverable, asks the responsible team worker to fetch it. Logs the screen output in a diary.
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

        % Block the start button in the GUI (if any)

        % Start a diary to log the screen output
        logdir = fullfile(obj.coord.outputdir, 'logs');
        [~,~]  = mkdir(logdir);
        diary(fullfile(logdir, 'diary_workflow.txt'))
        diary_off = onCleanup(@() diary('off'));

        if isempty(obj.coord.deliverables)
            disp('❌ The list of deliverables is empty, there is nothing to do')
            return
        end

        % Save the config and workflow data, so that the workflow can be resumed later
        obj.coord.get_config(obj.coord.config);
        obj.coord.save_coord()

        % Avoid issues with persistent memory locks of the qsublist function
        if obj.coord.config.General.useHPC.value
            ws = warning('off', 'MATLAB:DELETE:DeletedFileFromPackage');
            restore = onCleanup(@() warning(ws));
            cleanup = onCleanup(@() qsublist('killall'));
            batch = obj.getbatch();         % -> qsubfeval()
            if mislocked('qsublist') && obj.interactive
                answer = questdlg(sprintf('You have old/unreturned qsub(feval) jobs in memory,\nprobably caused by previous crashes, that may cause issues.\n\nCan I cleanup the bookkeeping?'), ...
                    'Locked qsublist detected', 'Yes', 'No', 'Cancel', 'Yes');
                if isempty(answer) || strcmp(answer, 'Cancel')
                    return
                elseif strcmp(answer, 'Yes')
                    munlock('qsublist')
                    clear('qsublist')   % TODO: make this less brutal by only clearing the submitted jobs
                end
            end
        end

        % Parse the subjects for which the workflow should be executed
        if strlength(subjects)
            sel = false(size(obj.coord.BIDS.subjects));
            for subject = subjects(:)'
                sel(strcmp({obj.coord.BIDS.subjects.name}, subject)) = true;
            end
            subjects = obj.coord.BIDS.subjects(sel);
        else
            subjects = obj.coord.BIDS.subjects;
        end

        % Check if there are still lock-files around from previous crashes
        lockfiles = dir(fullfile(obj.coord.workdir, '**', '*.lock'));
        if ~isempty(lockfiles)
            fprintf('🔒 Found %d existing lockfile(s)\n', length(lockfiles))
            if obj.interactive
                sample = fullfile(lockfiles(1).folder, lockfiles(1).name);
                answer = questdlg(sprintf('Found %d existing lockfile(s), probably caused by previous crashes. Here is a sample:\n\n..%s:\n%s\n\nShall I clean them up?', ...
                length(lockfiles), extractAfter(sample, 'derivatives'), fileread(sample)), 'Lockfiles detected', 'Yes', 'No', 'Yes');
                if strcmp(answer, 'Yes')
                    lockfiles = fullfile({lockfiles.folder}, {lockfiles.name});
                    fprintf('🔓 Deleting %d existing lockfile(s)\n', length(lockfiles))
                    delete(lockfiles{:})
                end
            end
        end

        % Check if our team is up-to-date
        if ~all(isfield(obj.team, obj.coord.deliverables))
            disp("🔄 Manager updates the team")
            obj.create_team()
        end

        % Clear the worker error/warning logs
        for member = obj.team_members()
            for suffix = ["warnings", "errors"]
                for logfile = dir(fullfile(obj.coord.outputdir, 'logs', member, sprintf('sub-*_%s.log', suffix)))'
                    delete(fullfile(logfile.folder, logfile.name))
                end
            end
        end

        % Delete the workitems from the forced workers and their downstream dependencies (so that they will be re-made)
        if ~isempty(obj.force)
            if isempty(findall(groot, Tag='workflow_graph'))
                obj.draw_workflow();        % Recreate the workflow graph if it was closed by the user
            end
            H = findall(groot, Tag='workflow_graph');
            workers = fieldnames(obj.coord.resumes);
            BIDSW   = bids.layout(char(obj.coord.workdir), use_schema=false, index_derivatives=false, index_dependencies=false, tolerant=true, verbose=false);
            for worker = obj.force

                % Remove the non-preferred edges to find the downstream nodes of the forced worker
                prunedflow = obj.workflow;
                for node = string(prunedflow.Nodes.Name)'
                    if ~ismember(node, workers) && indegree(prunedflow, node) > 1   % If it's not a worker, then it must be a workitem
                        for parent = prunedflow.predecessors(node)'
                            if ~strcmp(parent, obj.team.(node).name)                % Remove the edge if the parent worker is not preferred
                                prunedflow = rmedge(prunedflow, parent, node);
                            end
                        end
                    end
                end
                downstream = bfsearch(prunedflow, worker);

                % Highlight the downstream edges
                if isvalid(H)
                    [s, t] = findedge(obj.workflow);
                    idx    = ismember(obj.workflow.Nodes.Name(s), downstream);
                    highlight(H, s(idx), t(idx), LineStyle=':')
                end

                % Delete the workitems from the forced workers and their downstream dependencies (so that they will be re-made)
                for node = downstream'
                    if ismember(node, workers)
                        depworker = obj.coord.resumes.(node).handle(obj.coord.BIDS, struct(), obj.coord.config);
                        for workitem = depworker.makes
                            items = replace(erase(bids.query(BIDSW, 'data', depworker.bidsfilter.(workitem)),'.gz'),'.nii','.*');   % TODO: Fix BIDSW for QSMWorker, which uses a custom workdir
                            if ~isempty(items)
                                fprintf('🗑️ Deleting %s -> %s items from the workdir\n', depworker.name, workitem)
                                delete(items{:})
                            end
                        end
                    end
                end
            end
            if isvalid(H)
                L = findall(ancestor(H,'Figure'), Type='Legend'); drawnow
                if L.Position(2) < 0.1      % Move the legend a bit up if the best Position is 'South'
                    L.Position(2) = L.Position(2) + 0.045;
                end
                delete(findall(ancestor(H,'Figure'), 'Type', 'textboxshape'))
                annotation('textbox', [L.Position(1), L.Position(2)-0.045, L.Position(3), 0.035], String='{\bf--} Enforced', FontSize=L.FontSize, BackgroundColor=L.Color)
                saveas(H, regexprep(obj.coord.workflowfile, "(.*)\.mat$", "$1.png"))
            end
        end

        % Dispatch the workers
        fprintf("\n============= Starting workflow at %s =============\n", datetime('now'))
        for product = obj.coord.deliverables      % TODO: sort such that MEGREprepWorker deliverables (if any) are fetched first
            Worker = obj.team.(product).handle;
            name   = obj.team.(product).name;
            jobIDs = dictionary();
            for subject = subjects

                % Skip if we are not at the modality level, i.e. at the subject level while sessions are present
                if ~ismember("anat", fieldnames(subject)) || isempty(subject.anat)
                    continue
                end

                % Ask the worker to fetch the deliverable for this subject
                args = {obj.coord.BIDS, subject, obj.coord.config, obj.coord.workdir, obj.coord.outputdir, obj.team};
                fprintf('▶ Manager dispatched %s to make the "%s" deliverable for %s/%s\n', name, product, subject.name, subject.session)  % The wide Unicode character may not display correctly in all environments
                if obj.coord.config.General.useHPC.value
                    jobIDs(obj.sub_ses(subject)) = qsubfeval(Worker, args{:}, product, obj.coord.config.General.HPC.value{:}, 'batch', batch);  % NB: deliverables are passed directly instead of calling fetch()
                elseif obj.coord.config.General.useParallel.value
                    jobIDs(obj.sub_ses(subject)) = parfeval(Worker, 0, args{:}, product);
                else
                    Worker(args{:}).fetch(product);      % TODO: Catch the work done (at some point)
                end

            end

            % Monitor the progress of the workers until all work is done and report any errors or warnings
            obj.monitor_progress(product, jobIDs)

            % Copy the deliverables to the output directory
            obj.copy_to_outputdir(Worker(args{:}), product, subjects)
        end

        % Unblock the start button in the GUI (if any)
        fprintf("============= Finished workflow at %s =============\n\n", datetime('now'))
    end

    function workflow = draw_workflow(obj)
        %DRAW_WORKFLOW() Draw dependency graph with workers and workitems
        %
        % draw_workflow displays a bipartite graph where:
        %   - Blue nodes represent workers (labelled by their NAME property)
        %   - Green nodes represent workitems
        %   - Orange nodes represent deliverables (final requested workitems)
        %   - Edges from workers to workitems show what each worker produces (makes)
        %   - Edges from workitems to workers show what each worker needs
        %   - Edges in deliverable upstream subtrees are thicker
        %
        % Returns:
        %   WORKFLOW     - MATLAB digraph object representing the workflow graph with all workers and workitems

        if isempty(fieldnames(obj.team))
            disp('⚠ No team data found, cannot draw workflow graph')  % The wide Unicode character may not display correctly in all environments
            workflow = digraph();
            return
        end

        % Collect all unique workers and workitems
        tooltips    = {};
        workers     = {};
        workerNames = strings(1,0);
        workitems   = strings(1,0);
        for item = string(fieldnames(obj.team))'
            worker             = obj.team.(item);
            workers{end+1}     = worker;                                    %#ok<AGROW>
            workerNames(end+1) = worker.name;                               %#ok<AGROW>
            workitems          = [workitems worker.makes() worker.needs];   %#ok<AGROW>
            tooltips{end+1}    = join(worker.description, newline);         %#ok<AGROW>
        end
        [workerNames, idx] = unique(workerNames, 'stable');
        workers            = workers(idx);
        workitems          = unique(workitems(workitems ~= ""));
        tooltips           = [tooltips(idx), cellfun(@(item) obj.coord.glossary.(item), workitems, UniformOutput=false)];

        % Build edges = [source_idx, target_idx]
        edges    = [];
        nWorkers = length(workerNames);
        for i = 1:nWorkers
            
            % Edges from worker to workitems it makes
            for item = workers{i}.makes
                edges(end+1, :) = [i, nWorkers + find(workitems == item)];      %#ok<AGROW>
            end
            
            % Edges from workitems it needs to worker
            for item = workers{i}.needs
                edges(end+1, :) = [nWorkers + find(workitems == item), i];      %#ok<AGROW>
            end
        end

        % Build node lists for the graph (workers come first, then workitems)
        nodes = [workerNames, workitems];

        % Create the workflow graph
        workflow = digraph(edges(:,1), edges(:,2), [], nodes);

        % Identify nodes in upstream subtree of deliverables using graph traversal
        deliverableNodes = nWorkers + find(ismember(workitems, obj.coord.deliverables));
        upstream = flipedge(workflow);
        deliverableTree = false(size(nodes));
        for d = deliverableNodes
            deliverableTree(bfsearch(upstream, d)) = true;
        end

        % Select edges to highlight: only highlight the preferred worker when multiple workers produce the same workitem.
        highlightTree = deliverableTree(edges(:,2));                                            % Indexing outgoing edges(:,2) includes all edges
        for node = find(indegree(workflow) > 1 & (1:numel(nodes))' > nWorkers)'                 % Find workitems made by multiple workers
            for edge = find(edges(:,2) == node)'                                                % Find all incoming edges to this workitem
                if ~strcmp(workerNames(edges(edge,1)), obj.team.(workitems(node - nWorkers)).name)  % Remove incoming edges from non-preferred workers from the tree
                    highlightTree(edge) = false;
                end
            end
        end

        % Node types: 1=worker(blue), 2=workitem(green), 3=deliverable(orange), 4=raw/deriv(grey)
        nodeTypes                                                           = ones(size(nodes));
        nodeTypes(nWorkers+1:end)                                           = 2;
        nodeTypes(deliverableNodes)                                         = 3;
        nodeTypes(nWorkers + find(startsWith(workitems, ["raw", "deriv"]))) = 4;

        % Plot the workflow graph
        clf
        H = plot(workflow, ...
                NodeLabel    = ["  " + workerNames, " " + workitems], ...       % Add spaces as node labels overlap with markers in the digraph plot
                Layout       = 'layered', ...
                NodeCData    = nodeTypes, ...
                MarkerSize   = [12 * ones(size(workerNames)), 10 * ones(size(workitems))], ...
                NodeFontSize = 8, ...
                LineWidth    = 1.5, ...
                ArrowSize    = 10, ...
                Interpreter  = 'none', ...
                Tag          = 'workflow_graph');
        blue   = [0.16 0.5 0.73];   % = RTD blue #2980B9
        green  = [0 0.8 0];
        orange = [1 0.6 0];
        grey   = [0.7 0.7 0.7];
        colormap([blue; green; orange; grey])
        title('Workflow graph')

        % Add datatips for the workers and workitems
        H.DataTipTemplate.Interpreter = 'none';
        H.DataTipTemplate.DataTipRows = dataTipTextRow('', tooltips);

        % Highlight edges in deliverable subtrees
        highlight(H, ...
                edges(highlightTree, 1), ...
                edges(highlightTree, 2), ...
                EdgeColor=[0.5 0.5 0.5], LineWidth=3)     % highlight makes the specified EdgeColor lighter

        % Add a custom legend
        hold('on')
        plot(NaN, NaN, 'o', MarkerFaceColor=grey)
        plot(NaN, NaN, 'o', MarkerFaceColor=blue)
        plot(NaN, NaN, 'o', MarkerFaceColor=green)
        plot(NaN, NaN, 'o', MarkerFaceColor=orange)
        legend('', 'Raw data', 'Workers', 'Workitems', 'Deliverables', Location='best')
        hold('off')
    end

end


methods (Access = private)

    function copy_to_outputdir(obj, worker, deliverable, subjects)
        %COPY_TO_OUTPUTDIR Copies the deliverables from the workdir to the outputdir

        arguments
            obj
            worker      qb.workers.Worker
            deliverable string
            subjects    struct
        end
        
        labels = extractAfter({subjects.name}, 'sub-');
        BIDSW  = bids.layout(char(worker.workdir), filter=struct(sub={labels}), use_schema=false, index_derivatives=false, index_dependencies=false, tolerant=true, verbose=false);
        for source = string(bids.query(BIDSW, 'data', worker.bidsfilter.(deliverable)))'
            target = bids.File(char(source));
            target.entities.tag = char(worker.config.General.tag);
            target.path = fullfile(obj.coord.outputdir, target.bids_path, target.filename);
            worker.logger.info('-> Saving "%s" deliverable as: %s', deliverable, target.path)
            qb.utils.copybfile(source, target, ismember(worker.name, obj.force))
        end
    end

    function monitor_progress(obj, workitem, jobIDs)
        %MONITOR_PROGRESS Watches over the progress of the workers until all work is done

        arguments
            obj
            workitem {mustBeTextScalar}
            jobIDs   dictionary
        end

        if ~jobIDs.numEntries
            return
        end

        % Launch a dashboard
        dashboard = qb.workers.Dashboard(obj.coord, workitem, jobIDs);

        % Wait until all work is done
        while length(dashboard.work_done()) < length(jobIDs.keys)
            pause(1)
            dashboard.update()
        end

        % Report any errors or warnings
        dashboard.has_warnings(true);
        dashboard.has_errors(true);

        % Close the dashboard
        if isvalid(dashboard.fig)
            close(dashboard.fig)
        end
    end

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

        % Check if there is exactly one preferred worker. If not, ask the user to select one.
        if obj.interactive
            if sum([workers.preferred]) > 1
                error('QuIDBBIDS:Workers:MultiplePreferred', "Found multiple preferred workers for workitem '%s'", workitem)
            elseif ~any([workers.preferred])
                chosen = qb.GUI.selectworker(workers, workitem);
                if chosen
                    workers(chosen).preferred = true;
                else
                    return
                end
            end
        end

        % Keep the preferred worker only
        obj.team.(workitem) = workers([workers.preferred]);
        
        if length(obj.team.(workitem)) ~= 1
            error('QuIDBBIDS:WorkItem:InvalidCount', "Expected only a single workitem, but got %d", length(obj.team.(workitem)))
        end
    end

    function batch = getbatch(~)
        % GETBATCH returns an incrementing number that can be used to distinguish subsequent QSUBFEVAL calls

        persistent batch_

        if isempty(batch_)
            batch_ = 0;
        end
        batch_ = batch_ + 1;
        batch = batch_;
    end

end

end

function draw_workflow(team, deliverables)
%DRAW_WORKFLOW Draw dependency graph with workers and workitems
%
% draw_workflow(TEAM) displays a bipartite graph where:
%   - Blue nodes represent workers (labelled by their NAME property)
%   - Green nodes represent workitems
%   - Orange nodes represent deliverables (final requested workitems)
%   - Edges from workers to workitems show what each worker produces (makes)
%   - Edges from workitems to workers show what each worker needs
%   - Edges in deliverable upstream subtrees are thicker
%
% Inputs:
%   TEAM         - Struct as created by Manager.create_team()
%   DELIVERABLES - Row vector of deliverable workitem names (default: fieldnames(team))

arguments
    team         (1,1) struct
    deliverables (1,:) string
end

if isempty(fieldnames(team))
    disp('⚠  No team data found, cannot draw workflow graph')
    return
end

% Collect all unique workers and workitems
workers     = {};
workerNames = strings(1,0);
workitems   = strings(1,0);
for item = string(fieldnames(team))'
    w = team.(item);
    workers{end+1} = w;
    workerNames(end+1) = w.name;
    workitems = [workitems w.makes(w.makes ~= "") w.needs(w.needs ~= "")];
end
[workerNames, idx] = unique(workerNames, 'stable');
workers = workers(idx);
workitems = unique(workitems);

% Build edges = [source_idx, target_idx]
edges = [];
nWorkers = length(workerNames);
for i = 1:nWorkers
    
    % Edges from worker to workitems it makes (except raw workitems)
    for m = workers{i}.makes
        if ~isempty(m) && ismember(m, workitems)
            edges(end+1, :) = [i, nWorkers + find(workitems == m, 1)];
        end
    end
    
    % Edges from workitems it needs to worker
    for n = workers{i}.needs
        if ~isempty(n) && ismember(n, workitems)
            edges(end+1, :) = [nWorkers + find(workitems == n, 1), i];
        end
    end
end

% Build node lists for the graph (workers come first, then workitems)
nodes = [workerNames workitems];

% Create the workflow graph
workflow = digraph(edges(:,1), edges(:,2), [], nodes);

% Identify edges in upstream subtree of deliverables using graph traversal
deliverableNodeIdx = nWorkers + find(ismember(workitems, deliverables));
upstream = flipedge(workflow);
inDeliverableTree = false(size(nodes));
for d = deliverableNodeIdx
    inDeliverableTree(bfsearch(upstream, d)) = true;
end

% Node types: 1=worker(blue), 2=workitem(green), 3=deliverable(orange), 4=raw/deriv(grey)
nodeTypes = ones(size(nodes));
nodeTypes(nWorkers+1:end) = 2;
nodeTypes(deliverableNodeIdx) = 3;
nodeTypes(nWorkers + find(startsWith(workitems, ["raw", "deriv"]))) = 4;

% Plot the workflow graph
H = plot(workflow, ...
         Layout       = 'layered', ...
         NodeCData    = nodeTypes, ...
         MarkerSize   = [12 * ones(size(workerNames)), 10 * ones(size(workitems))], ...
         NodeFontSize = 8, ...
         LineWidth    = 1.5, ...
         ArrowSize    = 10, ...
         Interpreter  = 'none');
colormap([0 0 1; 0 1 0; 1 0.6 0; 0.7 0.7 0.7])  % blue, green, orange, grey
title('Workflow graph')

% Highlight edges in deliverable subtrees
highlight(H, ...
          edges(inDeliverableTree(edges(:, 2)), 1), ...
          edges(inDeliverableTree(edges(:, 2)), 2), ...
          EdgeColor=[0.5 0.5 0.5], LineWidth=3)

% Add a custom legend
hold on
plot(NaN, NaN, 'o', MarkerFaceColor=[0.7 0.7 0.7])  % grey
plot(NaN, NaN, 'o', MarkerFaceColor='blue')
plot(NaN, NaN, 'o', MarkerFaceColor='green')
plot(NaN, NaN, 'o', MarkerFaceColor=[1 0.6 0])      % orange
legend('', 'Input data', 'Workers', 'Workitems', 'Deliverables', Location='northeast')
hold off

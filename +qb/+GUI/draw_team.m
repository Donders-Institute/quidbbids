function draw_team(team, deliverables)
%DRAW_TEAM Draw dependency graph with workers and workitems
%
%   draw_team(TEAM) displays a bipartite graph where:
%     - Blue nodes represent workers (labelled by their NAME property)
%     - Green nodes represent workitems
%     - Purple nodes represent deliverables (final requested workitems)
%     - Edges from workers to workitems show what each worker produces (makes)
%     - Edges from workitems to workers show what each worker needs
%     - Edges in deliverable upstream subtrees are thicker
%
% Inputs:
%   TEAM - Struct as created by Manager.create_team()
%   DELIVERABLES - Row vector of deliverable workitem names (default: fieldnames(team))

arguments
    team (1,1)         struct
    deliverables (1,:) string
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

% Build edges: [source_idx, target_idx] (edge goes from workitem to worker)
% Special rule: if a worker makes a workitem starting with 'raw' or 'deriv', treat it as a need
edges = [];
nWorkers = length(workerNames);
for i = 1:nWorkers
    
    % Edges from worker to workitems it makes (except raw workitems)
    for m = workers{i}.makes
        if ~isempty(m) && ismember(m, workitems)
            if startsWith(m, ["raw", "deriv"])
                % Treat as need: edge from workitem to worker
                edges(end+1, :) = [nWorkers + find(workitems == m, 1), i];
            else
                % Normal make: edge from worker to workitem
                edges(end+1, :) = [i, nWorkers + find(workitems == m, 1)];
            end
        end
    end
    
    % Edges from workitems it needs to worker
    for n = workers{i}.needs
        if ~isempty(n) && ismember(n, workitems)
            edges(end+1, :) = [nWorkers + find(workitems == n, 1), i];
        end
    end
end

% Create the workflow graph
workflow = digraph(edges(:,1), edges(:,2));

% Build node lists for the graph (workers come first, then workitems)
nodes = [workerNames workitems];

% Identify edges in upstream subtree of deliverables using graph traversal
deliverableNodeIdx = nWorkers + find(ismember(workitems, deliverables));
upstreamG = flipedge(workflow);
inDeliverableTree = false(size(nodes));
for d = deliverableNodeIdx
    inDeliverableTree(bfsearch(upstreamG, d)) = true;
end

% Node types: 1=worker(blue), 2=workitem(green), 3=deliverable(purple)
nodeTypes = ones(length(nodes), 1);
nodeTypes(nWorkers+1:end) = 2;
nodeTypes(deliverableNodeIdx) = 3;

% Plot the workflow graph
markerSizes = 10 * ones(length(nodes), 1);
markerSizes(1:nWorkers) = 12;
h = plot(workflow, ...
    Layout       = 'layered', ...
    NodeLabel    = nodes, ...
    NodeCData    = nodeTypes, ...
    MarkerSize   = markerSizes, ...
    NodeFontSize = 8, ...
    LineWidth    = 1.5, ...
    ArrowSize    = 10, ...
    Interpreter  = 'none');
colormap([0 0 1; 0 1 0; 0.7 0 0.7])

% Highlight edges in deliverable subtrees
hold on
highlight(h, ...
    edges(inDeliverableTree(edges(:, 2)), 1), ...
    edges(inDeliverableTree(edges(:, 2)), 2), ...
    EdgeColor=[0.5 0.5 0.5], LineWidth=3)

% Add legend
plot(NaN, NaN, 'o', MarkerFaceColor = [0 0 1])
plot(NaN, NaN, 'o', MarkerFaceColor = [0 1 0])
plot(NaN, NaN, 'o', MarkerFaceColor = [0.7 0 0.7])
legend('', 'Workers', 'Workitems', 'Deliverables', Location = 'northeast')

title('Workflow graph')

function draw_workflow(team, deliverables)
%DRAW_WORKFLOW(TEAM) Draw dependency graph with workers and workitems
%
% draw_workflow displays a bipartite graph where:
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
    disp('⚠  No team data found, cannot draw workflow graph')  % Spaces are added to deal with the wide Unicode character
    return
end

% Collect all unique workers and workitems
workers     = {};
workerNames = strings(1,0);
workitems   = strings(1,0);
for item = string(fieldnames(team))'
    worker             = team.(item);
    workers{end+1}     = worker;
    workerNames(end+1) = worker.name;
    workitems          = [workitems worker.makes() worker.needs];
end
[workerNames, idx] = unique(workerNames, 'stable');
workers            = workers(idx);
workitems          = unique(workitems(workitems ~= ""));

% Build edges = [source_idx, target_idx]
edges    = [];
nWorkers = length(workerNames);
for i = 1:nWorkers
    
    % Edges from worker to workitems it makes
    for item = workers{i}.makes
        edges(end+1, :) = [i, nWorkers + find(workitems == item)];
    end
    
    % Edges from workitems it needs to worker
    for item = workers{i}.needs
        edges(end+1, :) = [nWorkers + find(workitems == item), i];
    end
end

% Build node lists for the graph (workers come first, then workitems)
nodes = ["  " + workerNames, " " + workitems];  % Add spaces as node labels overlap with markers in the digraph plot

% Create the workflow graph
workflow = digraph(edges(:,1), edges(:,2), [], nodes);

% Identify nodes in upstream subtree of deliverables using graph traversal
deliverableNodeIdx = nWorkers + find(ismember(workitems, deliverables));
upstream = flipedge(workflow);
deliverableTree = false(size(nodes));
for d = deliverableNodeIdx
    deliverableTree(bfsearch(upstream, d)) = true;
end

% Select edges to highlight: only highlight the preferred worker when multiple workers produce the same workitem.
highlightTree = deliverableTree(edges(:,2));                                            % Indexing outgoing edges(:,2) includes all edges
for node = find(indegree(workflow) > 1 & (1:numel(nodes))' > nWorkers)'                 % Find workitems made by multiple workers
    for edge = find(edges(:,2) == node)'                                                % Find all incoming edges to this workitem
        if ~strcmp(workerNames(edges(edge,1)), team.(workitems(node - nWorkers)).name)  % Remove incoming edges from non-preferred workers from the tree
            highlightTree(edge) = false;
        end
    end
end

% Node types: 1=worker(blue), 2=workitem(green), 3=deliverable(orange), 4=raw/deriv(grey)
nodeTypes                                                           = ones(size(nodes));
nodeTypes(nWorkers+1:end)                                           = 2;
nodeTypes(deliverableNodeIdx)                                       = 3;
nodeTypes(nWorkers + find(startsWith(workitems, ["raw", "deriv"]))) = 4;

% Plot the workflow graph
H = plot(workflow, ...
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

% Highlight edges in deliverable subtrees
highlight(H, ...
          edges(highlightTree, 1), ...
          edges(highlightTree, 2), ...
          EdgeColor=[0.5 0.5 0.5], LineWidth=3)     % highlight makes the specified EdgeColor lighter

% Add a custom legend
hold on
plot(NaN, NaN, 'o', MarkerFaceColor=grey)
plot(NaN, NaN, 'o', MarkerFaceColor=blue)
plot(NaN, NaN, 'o', MarkerFaceColor=green)
plot(NaN, NaN, 'o', MarkerFaceColor=orange)
legend('', 'Raw data', 'Workers', 'Workitems', 'Deliverables', Location='best')
hold off

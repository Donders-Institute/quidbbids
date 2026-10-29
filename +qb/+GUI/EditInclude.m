classdef EditInclude < handle
% EditInclude - GUI for filtering and displaying file trees
%
% Usage:
%   include = struct(modality={{'anat','fmap'}}, suffix={{'MEGRE','VFA'}});
%   BIDS    = bids.layout('/path/to/directory');
%   include = qb.GUI.EditInclude(include, BIDS).waitForResult();

properties
    Fig
    coord
    IncludeField
    ExcludeField
    Tree
    IncludeOriginal
    IncludeCurrent
    IncludeResult
    ExcludeOriginal
    ExcludeCurrent
    ExcludeResult
    NodeMap
    Arrow = fullfile(matlabroot,'toolbox','matlab','icons','greencircleicon.gif');  % -> Include tagging icon (alternative: help_gs.png)
end

methods
    
    function obj = EditInclude(coord)
        % Constructor to build the GUI and file tree from the root directory

        arguments
            coord qb.workers.Coordinator
        end
        
        obj.coord           = coord;
        obj.IncludeOriginal = coord.include;
        obj.IncludeCurrent  = coord.include;
        obj.ExcludeOriginal = coord.exclude;
        obj.ExcludeCurrent  = coord.exclude;
        obj.NodeMap         = dictionary(string.empty, matlab.ui.container.TreeNode.empty);

        % Create figure
        obj.Fig = uifigure(Name=['BIDS Include Editor - ' coord.BIDS.pth], Position=[200 200 800 600], CloseRequestFcn=@(src, evt) obj.onCancel());

        % Main grid
        mainGrid = uigridlayout(obj.Fig, [1 2]);
        mainGrid.RowHeight     = {'1x'};
        mainGrid.ColumnWidth   = {'fit', '1x'};
        mainGrid.ColumnSpacing = 20;
        mainGrid.Padding       = [20 20 20 10];   % [left bottom right top]

        %--- FILTER AREA
        filterGrid = uigridlayout(mainGrid, [5 1]);
        filterGrid.ColumnWidth = {'1x'};
        filterGrid.RowHeight   = {20, '1x', 20, '1x', 'fit'};
        filterGrid.RowSpacing  = 5;
        filterGrid.Padding     = [0 0 0 0];

        % Include label and field
        uilabel(filterGrid, Text='Include filter');
        obj.IncludeField                 = uitextarea(filterGrid);
        obj.IncludeField.Value           = jsonencode(obj.IncludeCurrent, 'PrettyPrint',true);
        obj.IncludeField.ValueChangedFcn = @(src, evt) obj.onIncludeChanged();
        obj.IncludeField.Tooltip         = 'Edit the BIDS include filter in JSON format. Click outside the box to apply your changes';

        % Exclude label and field
        uilabel(filterGrid, Text='Exclude filter');
        obj.ExcludeField                 = uitextarea(filterGrid);
        obj.ExcludeField.Value           = jsonencode(obj.ExcludeCurrent, 'PrettyPrint',true);
        obj.ExcludeField.ValueChangedFcn = @(src, evt) obj.onExcludeChanged();
        obj.ExcludeField.Tooltip         = 'Edit the BIDS exclude filter in JSON format. Click outside the box to apply your changes';

        % Buttons
        buttonGrid = uigridlayout(filterGrid, [1 3]);
        buttonGrid.RowHeight   = {'fit'};
        buttonGrid.ColumnWidth = {60, 60, 60};
        buttonGrid.Padding     = [0 0 0 10];   % [left bottom right top]
        uibutton(buttonGrid, Text='✗ Cancel', ButtonPushedFcn=@(src, evt) obj.onCancel());
        uibutton(buttonGrid, Text='↺ Reset',  ButtonPushedFcn=@(src, evt) obj.onReset());
        uibutton(buttonGrid, Text='✓ Done',   ButtonPushedFcn=@(src, evt) obj.onDone());

        %--- TREE AREA
        treeGrid             = uigridlayout(mainGrid, [2 1]);
        treeGrid.RowHeight   = {20, '1x'};
        treeGrid.RowSpacing  = 5;
        treeGrid.ColumnWidth = {'1x'};
        treeGrid.Padding     = [0 0 0 0];
        uilabel(treeGrid, Text='Data inclusion tree');
        obj.Tree             = uitree(treeGrid);
        obj.Tree.Tooltip     = 'Tree view of the BIDS data structure. Green circles indicate included files/folders';

        % Build the BIDS tree structure (without sidecars and hidden files)
        P = uiprogressdlg(obj.Fig, Title='Building the data inclusion tree', Message='Please wait...', Icon=get(groot,'defaultFigureIcon'), Indeterminate='on');
        for file = dir(fullfile(coord.BIDS.pth, "**", "*"))'
            obj.addNodeToTree(file, obj.Tree)
        end
        close(P)

        % Find and tag the included files
        obj.tagTree()
    end
    
    function addNodeToTree(obj, file, parentNode)
        % Add a file or directory node to the tree using a path->node map

        % Skip sidecars and hidden files
        if (startsWith(file.name, 'sub-') && endsWith(file.name, '.json')) || startsWith(file.name, '.')
            return
        end
        
        subPath = obj.coord.BIDS.pth;
        for part = split(extractAfter(fullfile(file.folder,file.name), [obj.coord.BIDS.pth filesep]), filesep)'
            subPath = fullfile(subPath, part{1});
            if ismember(subPath, keys(obj.NodeMap))
                parentNode = obj.NodeMap(subPath);
            else
                newNode              = uitreenode(parentNode, Text=part{1});
                newNode.UserData     = subPath;
                obj.NodeMap(subPath) = newNode;
                parentNode           = newNode;
            end
        end
    end
    
    function tagNode(obj, node, included)
        % Recursively tag a node and its children
        
        % Check if this node or any node in its subtree is included
        tag = any(startsWith(included, node.UserData));
        if tag && ~strcmp(node.Icon, obj.Arrow)
            node.Icon = obj.Arrow;
        elseif ~tag && ~isempty(node.Icon)
            node.Icon = '';
        end
        
        % Recursively tag children
        for i = 1:numel(node.Children)
            obj.tagNode(node.Children(i), included)
        end
    end

    function tagTree(obj)
        % Queries the BIDS folder and tags the tree based on the IncludeCurrent filter
        P = uiprogressdlg(obj.Fig, Title='Building the data inclusion tree', Message='Please wait...', Icon=get(groot,'defaultFigureIcon'), Indeterminate='on');
        cleanup = onCleanup(@() close(P));
        BIDS = obj.coord.pruneBIDS(obj.coord.fullBIDS, obj.IncludeCurrent, obj.ExcludeCurrent);
        included = bids.query(BIDS, 'data');
        for node = obj.Tree.Children'
            obj.tagNode(node, included)
        end
    end
    
    function onIncludeChanged(obj)
        % Callback when include field changes
        try
            obj.IncludeCurrent = jsondecode(strjoin(obj.IncludeField.Value, newline));
            obj.tagTree()
        catch ME
            uialert(obj.Fig, sprintf('Invalid JSON format: %s', ME.message), 'Parse Error')
        end
    end
    
    function onExcludeChanged(obj)
        % Callback when exclude field changes
        try
            obj.ExcludeCurrent = jsondecode(strjoin(obj.ExcludeField.Value, newline));
            obj.tagTree()
        catch ME
            uialert(obj.Fig, sprintf('Invalid JSON format: %s', ME.message), 'Parse Error')
        end
    end
    
    function onCancel(obj)
        % Callback for Cancel button & close request
        obj.IncludeResult = obj.IncludeOriginal;
        obj.ExcludeResult = obj.ExcludeOriginal;
        delete(obj.Fig)
    end
    
    function onReset(obj)
        % Callback for Reset button
        obj.IncludeField.Value = jsonencode(obj.IncludeOriginal, PrettyPrint=true);
        obj.ExcludeField.Value = jsonencode(obj.ExcludeOriginal, PrettyPrint=true);
        obj.IncludeCurrent     = obj.IncludeOriginal;
        obj.ExcludeCurrent     = obj.ExcludeOriginal;
        obj.tagTree()
    end
    
    function onDone(obj)
        % Callback for Done button
        obj.IncludeResult = obj.IncludeCurrent;
        obj.ExcludeResult = obj.ExcludeCurrent;
        delete(obj.Fig)
    end
    
    function [include, exclude] = waitForResult(obj)
        % Wait for user to click Done or Cancel and return the include filter (as a struct)
        waitfor(obj.Fig)
        include = obj.IncludeResult;
        exclude = obj.ExcludeResult;
    end
    
end

end

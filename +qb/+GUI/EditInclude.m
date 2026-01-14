classdef EditInclude < handle
    % EditInclude - GUI for filtering and displaying file trees
    %
    % Usage:
    %   include = struct('modality', {{'anat','fmap'}}, 'suffix', {{'MEGRE','VFA'}});
    %   BIDS    = bids.layout('/path/to/directory');
    %   include = qb.GUI.EditInclude(include, BIDS).waitForResult();
    
    properties
        Fig
        BIDS
        InputField
        Tree
        IncludeOriginal
        IncludeCurrent
        IncludeResult
        NodeMap
        Arrow = fullfile(matlabroot,'toolbox','matlab','icons','greenarrowicon.gif');  % -> Include tagging icon (alternative: help_gs.png)
    end
    
    methods
        function obj = EditInclude(include, BIDS)
            % Constructor
            arguments
                include struct
                BIDS    struct
            end
            
            obj.BIDS            = BIDS;
            obj.IncludeOriginal = include;
            obj.IncludeCurrent  = include;
            obj.NodeMap         = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            obj.buildGUI()
            obj.query(obj.IncludeCurrent)
        end
        
        function buildGUI(obj)
            % Build the GUI and file tree from the root directory

            % Create figure
            obj.Fig = uifigure('Name', ['BIDS Include Editor - ' obj.BIDS.pth], 'Position', [200 200 800 500], 'CloseRequestFcn', @(src, evt) obj.onCancel());

            % Main grid
            mainGrid = uigridlayout(obj.Fig, [1 2]);
            mainGrid.RowHeight     = {'1x'};
            mainGrid.ColumnWidth   = {'fit', '1x'};
            mainGrid.ColumnSpacing = 20;
            mainGrid.Padding       = [20 20 20 10];   % [left bottom right top]

            %--- INCLUDE AREA
            includeGrid = uigridlayout(mainGrid, [3 1]);
            includeGrid.ColumnWidth = {'1x'};
            includeGrid.RowHeight   = {20, '1x', 'fit'};
            includeGrid.RowSpacing  = 5;
            includeGrid.Padding     = [0 0 0 0];

            % Input label and field
            uilabel(includeGrid, 'Text', 'Include filter');
            obj.InputField                 = uitextarea(includeGrid);
            obj.InputField.Value           = jsonencode(obj.IncludeCurrent, 'PrettyPrint',true);
            obj.InputField.ValueChangedFcn = @(src, evt) obj.onInputChanged();
            obj.InputField.Tooltip         = 'Edit the BIDS include filter in JSON format. Click outside the box to apply your changes';

            % Buttons
            buttonGrid = uigridlayout(includeGrid, [1 3]);
            buttonGrid.RowHeight   = {'fit'};
            buttonGrid.ColumnWidth = {60, 60, 60};
            buttonGrid.Padding     = [0 0 0 10];   % [left bottom right top]
            uibutton(buttonGrid, 'Text', '✗ Cancel', 'ButtonPushedFcn', @(src, evt) obj.onCancel());
            uibutton(buttonGrid, 'Text', '↺ Reset',  'ButtonPushedFcn', @(src, evt) obj.onReset());
            uibutton(buttonGrid, 'Text', '✓ Done',   'ButtonPushedFcn', @(src, evt) obj.onDone());

            %--- TREE AREA
            treeGrid             = uigridlayout(mainGrid, [2 1]);
            treeGrid.RowHeight   = {20, '1x'};
            treeGrid.RowSpacing  = 5;
            treeGrid.ColumnWidth = {'1x'};
            treeGrid.Padding     = [0 0 0 0];
            uilabel(treeGrid, 'Text', 'Data inclusion tree');
            obj.Tree             = uitree(treeGrid);
            obj.Tree.Tooltip     = 'Tree view of the BIDS data structure. Green arrows indicate included files/folders';

            % Build tree structure
            for file = dir(fullfile(obj.BIDS.pth, "**", "*"))'
                if file.isdir || (startsWith(file.name, 'sub-') && endsWith(file.name, '.json'))
                    continue
                end
                obj.addNodeToTree(fullfile(file.folder, file.name), obj.Tree)
            end

            % Find and tag the included files
            obj.query(obj.IncludeCurrent)
        end
        
        function addNodeToTree(obj, fullPath, parentNode)
            % Add a file or directory node to the tree using a path->node map
            
            subPath = obj.BIDS.pth;
            for part = strsplit(extractAfter(fullPath, [obj.BIDS.pth filesep]), filesep)                
                subPath = fullfile(subPath, part{1});
                if isKey(obj.NodeMap, subPath)
                    parentNode = obj.NodeMap(subPath);
                else
                    newNode              = uitreenode(parentNode, 'Text', part{1});
                    newNode.UserData     = subPath;
                    obj.NodeMap(subPath) = newNode;
                    parentNode           = newNode;
                end
            end
        end
        
        function tagTree(obj, included)
            % Tags tree nodes based on included BIDS file list
            for node = obj.Tree.Children'
                obj.tagNode(node, included)
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
        
        function onInputChanged(obj)
            % Callback when input field changes
            try
                obj.IncludeCurrent = jsondecode(strjoin(obj.InputField.Value, newline));
                obj.query(obj.IncludeCurrent)
            catch ME
                uialert(obj.Fig, sprintf('Invalid JSON format: %s', ME.message), 'Parse Error')
            end
        end
        
        function query(obj, include)
            % Queries the BIDS folder and tags the tree based on the include filter
            obj.tagTree(string(bids.query(obj.BIDS, 'data', include)))
        end
        
        function onCancel(obj)
            % Callback for Cancel button
            obj.IncludeResult = obj.IncludeOriginal;
            delete(obj.Fig)
        end
        
        function onReset(obj)
            % Callback for Reset button
            obj.InputField.Value = jsonencode(obj.IncludeOriginal, 'PrettyPrint',true);
            obj.IncludeCurrent   = obj.IncludeOriginal;
            obj.query(obj.IncludeCurrent)
        end
        
        function onDone(obj)
            % Callback for Done button
            obj.IncludeResult = obj.IncludeCurrent;
            delete(obj.Fig)
        end
        
        function [result, BIDS] = waitForResult(obj)
            % Wait for user to click Done or Cancel and return the include filter (as a struct)
            waitfor(obj.Fig)
            result = obj.IncludeResult;
            BIDS   = obj.BIDS;
        end
        
    end
end

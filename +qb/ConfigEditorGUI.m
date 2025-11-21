classdef ConfigEditorGUI < handle
% ConfigEditorGUI  GUI-based JSON config editor
%
%   Usage (example from a wrapper):
%       app = qb.ConfigEditorGUI(configfile, workers);
%       uiwait(app.Fig);
%       config = app.Config;
%
%   - If configfile is empty or not provided, a file dialog is opened.
%   - workers: optional cell array of top-level keys to show (empty => all)
%
% Save this file as: ConfigEditorGUI.m

    properties
        % Public for wrapper access
        Fig
        ConfigFile
        Config
    end

    properties (Access = private)
        OrigConfig

        UIFig
        Tree
        RootNodes % array of top-level nodes (children of tree)

        % Right-side editor
        DescArea    % uitextarea (non-editable)
        ValField    % uieditfield (or uieditfield('text'))
        ValLabel    % uilabel for the value field that we can update
        ResetLeafBtn

        % Search controls
        SearchField
        BtnSearchNext
        BtnSearchPrev
        SearchMatches % cell array of nodes that match
        SearchIndex = 0

        % Bottom buttons
        BtnLoad
        BtnSave
        BtnResetAll
        BtnCancel

        Workers
    end

    methods
        function obj = ConfigEditorGUI(configfile, workers)
            % CONFIGEDITORGUI Constructor to validate input and ask for file if needed

            if nargin < 1 || isempty(configfile)
                [f,p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file');
                if isequal(f,0)
                    % user cancelled - create an invisible figure and return
                    obj.Fig = [];
                    obj.ConfigFile = [];
                    obj.Config = [];
                    return
                end
                configfile = fullfile(p,f);
            end
            obj.ConfigFile = configfile;

            if nargin < 2
                workers = [];
            end
            obj.Workers = workers;

            % Read JSON
            try
                txt = fileread(configfile);
                obj.Config = jsondecode(txt);
            catch ME
                errordlg(['Unable to read/parse JSON: ' ME.message],'File Error');
                obj.Fig = [];
                return
            end
            obj.OrigConfig = obj.Config;

            % Build GUI
            obj.buildGUI();

            % Populate tree
            obj.populateTree();
        end

        function delete(obj)
            % Destructor-like convenience to close figure if still open
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                close(obj.Fig);
            end
        end
    end

    methods (Access = private)

        % build GUI layout with uifigure
        function buildGUI(obj)

            % Create main uifigure
            obj.UIFig = uifigure('Position',[300 200 1000 650]);
            obj.Fig = obj.UIFig;
            obj.updateWindowTitle()

            % Left panel (tree + search)
            leftX = 10; leftW = 360;
            % Tree area rectangle in pixels
            % Create search label and field
            uilabel(obj.UIFig,'Text','Search:','Position',[leftX 600 50 22],'HorizontalAlignment','left');
            obj.SearchField = uieditfield(obj.UIFig,'text','Position',[leftX+55 600 leftW-55 24], 'ValueChangedFcn',@(src,~)obj.onSearchChanged(), 'Value','');

            % Prev/Next buttons
            obj.BtnSearchPrev = uibutton(obj.UIFig,'Text','◀','Position',[leftX 570 40 24],    'ButtonPushedFcn',@(~,~)obj.searchPrev());
            obj.BtnSearchNext = uibutton(obj.UIFig,'Text','▶','Position',[leftX+45 570 40 24], 'ButtonPushedFcn',@(~,~)obj.searchNext());

            % Info label for search state
            uilabel(obj.UIFig,'Text','(supports *, ? and regex wildcards)','Position',[leftX+95 570 260 18], 'FontAngle','italic', 'HorizontalAlignment','left');

            % Tree (use uitree within uifigure)
            obj.Tree = uitree(obj.UIFig,'Position',[leftX 20 leftW 530], 'Multiselect','off', 'SelectionChangedFcn',@(src,evt)obj.nodeSelected(evt));

            % Right panel (Description and edit area)
            rpX = leftX + leftW + 20;
            rpW = 1000 - rpX - 20;
            obj.DescArea = uitextarea(obj.UIFig,'Position',[rpX 450 rpW 175],'Editable','off');

            % Value label and field
            obj.ValLabel = uilabel(obj.UIFig,'Text','Value:','Position',[rpX 420 200 22],'HorizontalAlignment','left');
            obj.ValField = uieditfield(obj.UIFig,'text','Position',[rpX 380 rpW 40], 'ValueChangedFcn',@(src,~)obj.updateLeafFromField());

            % Reset leaf button
            obj.ResetLeafBtn = uibutton(obj.UIFig,'Text','Reset','Position',[rpX+rpW-110 340 100 30], 'ButtonPushedFcn',@(~,~)obj.resetLeaf());

            % Bottom row buttons
            btnY = 20; btnH = 30; btnW = 70; gap = 15;
            obj.BtnLoad     = uibutton(obj.UIFig,'Text','Load',     'Position',[rpX+20 btnY btnW btnH],              'ButtonPushedFcn',@(~,~)obj.loadJSON());
            obj.BtnSave     = uibutton(obj.UIFig,'Text','Save',     'Position',[rpX+20+btnW+gap btnY btnW btnH],     'ButtonPushedFcn',@(~,~)obj.saveJSON());
            obj.BtnResetAll = uibutton(obj.UIFig,'Text','Reset All','Position',[rpX+20+2*(btnW+gap) btnY btnW btnH], 'ButtonPushedFcn',@(~,~)obj.resetAll());
            obj.BtnCancel   = uibutton(obj.UIFig,'Text','Cancel',   'Position',[rpX+20+3*(btnW+gap) btnY btnW btnH], 'ButtonPushedFcn',@(~,~)close(obj.UIFig));

            % Use ValueChangedFcn with a custom approach for Enter key detection. We'll modify the existing ValueChangedFcn to handle Enter key behavior
            obj.SearchField.ValueChangedFcn = @(src,evt)obj.onSearchFieldChanged(evt);
        end

        % populate tree directly with top-level keys (no single "config" root)
        function populateTree(obj)
            delete(obj.Tree.Children); % clear existing nodes

            % Decide top-level keys to show
            if isempty(obj.Workers)
                topKeys = fieldnames(obj.Config);
            else
                topKeys = obj.Workers(:);
            end

            obj.RootNodes = gobjects(0);
            for k = 1:numel(topKeys)
                key = topKeys{k};
                if ~isfield(obj.Config,key)
                    continue;
                end
                node = uitreenode(obj.Tree,'Text',key,'NodeData',obj.Config.(key));
                obj.buildSubtree(node, obj.Config.(key));
                obj.RootNodes(end+1) = node; 
            end

            % Clear search state
            obj.SearchMatches = {};
            obj.SearchIndex = 0;
        end

        % recursively add children to the tree up to leaves
        function buildSubtree(obj, parentNode, value)
            if isstruct(value)
                names = fieldnames(value);
                for i = 1:numel(names)
                    nm = names{i};
                    child = value.(nm);
                    if obj.isLeaf(child)
                        uitreenode(parentNode,'Text',nm,'NodeData',child);
                    else
                        node = uitreenode(parentNode,'Text',nm,'NodeData',child);
                        obj.buildSubtree(node, child);
                    end
                end
            end
        end

        function tf = isLeaf(obj, S)
            % More robust leaf detection
            if ~isstruct(S)
                tf = false;
                return
            end
            fields = fieldnames(S);
            tf = ismember('value', fields) && ismember('description', fields) && numel(fields) == 2;
        end

        % callback when a tree node is selected
        function nodeSelected(obj, evt)
            nodes = evt.SelectedNodes;
            if isempty(nodes)
                obj.DescArea.Value = '';
                obj.ValField.Value = '';
                obj.ValLabel.Text = 'Value:'; % Reset to default
                return
            end
            node = nodes(1);
            data = node.NodeData;

            % Update the value label to show the selected node's name
            obj.ValLabel.Text = [node.Text ':'];
            
            if obj.isLeaf(data)
                % Show description and the current value
                if isstring(data.description)
                    obj.DescArea.Value = cellstr(data.description);
                elseif ischar(data.description)
                    obj.DescArea.Value = {data.description};
                else
                    % fallback: encode as JSON
                    obj.DescArea.Value = {jsonencode(data.description)};
                end

                % Format value for display
                obj.ValField.Value = obj.valueToStringForDisplay(data.value);
            else
                obj.DescArea.Value = {'(not editable)'};
                obj.ValField.Value = '';
            end
        end

        % Format various MATLAB types to a string representation suitable for editing
        function s = valueToStringForDisplay(~, val)
            if isnumeric(val) && isscalar(val)
                s = num2str(val);
            else
                % For arrays, objects, cells, use JSON representation for clarity
                try
                    s = jsonencode(val);
                catch
                    % fallback: use mat2str for numeric arrays
                    if isnumeric(val)
                        s = mat2str(val);
                    else
                        s = char(string(val));
                    end
                end
            end
        end

        % Attempt to update current selected leaf value from the ValField contents
        function updateLeafFromField(obj)
            sel = obj.Tree.SelectedNodes;
            if isempty(sel)
                return
            end
            node = sel(1);
            data = node.NodeData;
            oldVal = data.value;
            txt = strtrim(obj.ValField.Value);

            % Try robust parsing:
            % - If oldVal numeric: try JSON decode or str2num
            % - If oldVal logical: accept true/false/1/0
            % - If oldVal is char/string: accept as string (if user provided JSON string decode if quoted)
            % - For cell/struct/array: prefer jsondecode
            newVal = [];
            parsedOK = false;
            try
                if isnumeric(oldVal)
                    % If user typed JSON array like [1,2,3], jsondecode will work
                    if startsWith(txt,'[') && endsWith(txt,']') && contains(txt,',')
                        try
                            newVal = jsondecode(txt);
                            parsedOK = isnumeric(newVal) || islogical(newVal);
                        catch                   % fallback to str2num
                            tmp = str2num(txt); %#ok<ST2NM>
                            if ~isempty(tmp)
                                newVal = tmp;
                                parsedOK = true;
                            end
                        end
                    else
                        tmp = str2num(txt); %#ok<ST2NM>
                        if ~isempty(tmp)
                            newVal = tmp;
                            parsedOK = true;
                        end
                    end

                elseif islogical(oldVal)
                    if any(strcmpi(txt,{'true','1'}))
                        newVal = true; parsedOK = true;
                    elseif any(strcmpi(txt,{'false','0'}))
                        newVal = false; parsedOK = true;
                    else
                        try
                            tmp = jsondecode(txt);
                            if islogical(tmp)
                                newVal = tmp; parsedOK = true;
                            end
                        catch
                        end
                    end

                elseif ischar(oldVal) || isstring(oldVal)
                    % If user provided JSON string with quotes, decode it:
                    try
                        decoded = jsondecode(txt);
                    catch
                        decoded = [];
                    end
                    if ~isempty(decoded) && ischar(decoded)
                        newVal = string(decoded);
                        parsedOK = true;
                    else
                        % plain text: keep as string
                        newVal = string(txt);
                        parsedOK = true;
                    end

                else
                    % struct/cell/other: attempt jsondecode
                    try
                        newVal = jsondecode(txt);
                        parsedOK = true;
                    catch
                        % as a last resort, attempt eval (risky) only for numeric arrays
                        try
                            tmp = str2num(txt); %#ok<ST2NM>
                            if ~isempty(tmp)
                                newVal = tmp; parsedOK = true;
                            end
                        catch
                        end
                    end
                end
            catch
                parsedOK = false;
            end

            if ~parsedOK
                warndlg('Could not parse the value into the required type. Try JSON format for arrays/objects (e.g. [1,2,3] or {"a":1}).','Parse error');
                return
            end

            % Accept new value
            data.value = newVal;
            node.NodeData = data;

            % Update underlying obj.Config: find path and set there too
            path = obj.nodePath(node);
            obj.Config = obj.setValueInStruct(obj.Config, path, data);
        end

        % Reset selected leaf to original value
        function resetLeaf(obj)
            sel = obj.Tree.SelectedNodes;
            if isempty(sel), return; end
            node = sel(1);
            origLeaf = obj.getOriginalLeaf(node);
            node.NodeData.value = origLeaf.value;
            % Update display
            obj.nodeSelected(struct('SelectedNodes',node));
            % Update main config too
            path = obj.nodePath(node);
            obj.Config = obj.setValueInStruct(obj.Config, path, node.NodeData);
        end

        % Reset all to original config
        function resetAll(obj)
            obj.Config = obj.OrigConfig;
            obj.populateTree();
            obj.nodeSelected(struct('SelectedNodes',[]));            % Clear the right panel
        end

        % Load JSON from a new file selected via file dialog and repopulate the tree
        function loadJSON(obj)
            % Open file dialog to select JSON file
            [f, p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file to load', fileparts(obj.ConfigFile));
            if isequal(f, 0)
                return
            end
            obj.ConfigFile = fullfile(p, f);
            
            try
                % Read and parse the new JSON file
                obj.Config = jsondecode(fileread(obj.ConfigFile));
                
                % Update the application state and window title
                obj.OrigConfig = obj.Config;
                obj.updateWindowTitle()
                
                % Refresh the tree and clear right panel
                obj.populateTree();
                obj.nodeSelected(struct('SelectedNodes',[]));
                
            catch ME
                errordlg(['Unable to load/parse JSON: ' ME.message],'Load error');
            end
        end

        % Save current tree -> JSON file selected via file dialog
        function saveJSON(obj)

            % Open file dialog to select save location
            [f, p] = uiputfile({'*.json','JSON Files (*.json)'}, 'Save configuration as...', obj.ConfigFile);
            if isequal(f, 0)
                return  % User cancelled
            end
            obj.ConfigFile = fullfile(p, f);
            obj.updateWindowTitle()
            
            % Reconstruct struct from tree and save
            obj.Config = obj.treeToStruct();            
            try
                obj.jsonwrite(obj.ConfigFile, obj.Config);
            catch ME
                errordlg(['Failed to save: ' ME.message],'Save error');
            end
        end

        % Reconstruct struct from tree nodes
        function S = treeToStruct(obj)
            S = struct();
            for i = 1:numel(obj.RootNodes)
                key = obj.RootNodes(i).Text;
                S.(key) = obj.nodeToStruct(obj.RootNodes(i));
            end
        end

        function s = nodeToStruct(obj, node)
            children = node.Children;
            if isempty(children)
                % leaf node's NodeData is itself a struct with fields value & description
                s = node.NodeData;
                return
            end
            s = struct();
            for i = 1:numel(children)
                nm = children(i).Text;
                s.(nm) = obj.nodeToStruct(children(i));
            end
        end

        % Helper: set value in nested struct given path cell array
        function S = setValueInStruct(~, S, path, leafStruct)
            % path: e.g. {'MCRWorker','fixed_params','x_i'}
            if isempty(path)
                return
            end
            if isscalar(path)
                S.(path{1}) = leafStruct;
                return
            end
            key = path{1};
            if ~isfield(S,key)
                S.(key) = struct();
            end
            S.(key) = setfield_recursive(S.(key), path(2:end), leafStruct);

            function out = setfield_recursive(subS, remainingPath, leafStruct)
                if isscalar(remainingPath)
                    subS.(remainingPath{1}) = leafStruct;
                    out = subS;
                    return
                else
                    k2 = remainingPath{1};
                    if ~isfield(subS,k2)
                        subS.(k2) = struct();
                    end
                    subS.(k2) = setfield_recursive(subS.(k2), remainingPath(2:end), leafStruct);
                    out = subS;
                end
            end
        end

        % Get original leaf from OrigConfig by node path
        function leaf = getOriginalLeaf(obj, node)
            path = obj.nodePath(node);
            cur = obj.OrigConfig;
            for i = 1:numel(path)
                if isfield(cur, path{i})
                    cur = cur.(path{i});
                else
                    error('Original config path not found');
                end
            end
            leaf = cur;
        end

        % Build path (cell array of keys) from a node up to top-level
        function path = nodePath(~, node)
            path = {};
            cur = node;
            
            % Traverse up the tree until we hit the root tree object
            while ~isempty(cur) && ~isa(cur, 'matlab.ui.container.Tree')
                % Only add nodes that have Text property (uitreenode objects)
                if isprop(cur, 'Text')
                    path = [{cur.Text}, path];
                end
                cur = cur.Parent;
            end
        end

        % SEARCH: invoked when search field changes or enter pressed
        function onSearchChanged(obj)
            % Do not auto-select; just update the matches list
            obj.updateSearchMatches(strtrim(obj.SearchField.Value))
        end

        function collectLeafMatches(obj, node, qlow)
            % Check if this node is a leaf (has value and description)
            if obj.isLeaf(node.NodeData)
                % This is a leaf node - check if its name matches search
                if contains(lower(node.Text), qlow)
                    obj.SearchMatches{end+1} = node; 
                end
            else
                % This is not a leaf - continue searching in children
                for i = 1:numel(node.Children)
                    obj.collectLeafMatches(node.Children(i), qlow);
                end
            end
        end

        function collectMatchesRecursive(obj, node, qlow)
            % Check if this node has any leaf descendants
            if obj.hasLeafDescendants(node)
                % Check if node text matches search
                if contains(lower(node.Text), qlow)
                    obj.SearchMatches{end+1} = node; 
                end
            end
            
            % Continue searching in children
            for i = 1:numel(node.Children)
                obj.collectMatchesRecursive(node.Children(i), qlow);
            end
        end

        %% SEARCH: Find any node matching pattern
        function updateSearchMatches(obj, q)
            obj.SearchMatches = {};
            obj.SearchIndex = 0;            
            if isempty(q)
                return
            end
            
            % Convert search query to regex pattern with smart wildcard handling
            pattern = lower(strtrim(q));
            pattern = strrep(pattern, '*', '.*'); % Convert * to .* for regex
            pattern = strrep(pattern, '?', '.');  % Convert ? to . for regex
            if ~startsWith(pattern, '^')
                pattern = ['^', pattern];
            end
            if ~endsWith(pattern, '$')
                pattern = [pattern, '$'];
            end

            % Search across all nodes in tree
            fprintf('Searching for pattern: "%s"\n', pattern); % Debug
            roots = obj.RootNodes;
            for r = 1:numel(roots)
                obj.collectMatchingNodes(roots(r), pattern);
            end

            % Show what we found
            fprintf('Found %d matches:\n', numel(obj.SearchMatches));
            for i = 1:numel(obj.SearchMatches)
                node = obj.SearchMatches{i};
                if obj.isLeaf(node.NodeData)
                    % For leaf nodes, show the value
                    valueStr = obj.valueToStringForDisplay(node.NodeData.value);
                    fprintf('  Match %d: %s = %s\n', i, node.Text, valueStr);
                else
                    % For non-leaf nodes, just show the key
                    fprintf('  Match %d: %s (non-editable)\n', i, node.Text);
                end
            end
            
            % If matches found, select first
            if ~isempty(obj.SearchMatches)
                obj.SearchIndex = 1;
            end
        end

        function collectMatchingNodes(obj, node, pattern)
            % Check if this node's text matches the pattern
            nodeText = lower(node.Text);
            if ~isempty(regexp(nodeText, pattern, 'once'))
                obj.SearchMatches{end+1} = node; 
            end
            
            % Continue searching in all children
            for i = 1:numel(node.Children)
                obj.collectMatchingNodes(node.Children(i), pattern);
            end
        end

        function onSearchFieldChanged(obj, evt)
            % Only trigger search when field is non-empty
            q = strtrim(obj.SearchField.Value);
            if ~isempty(q)
                obj.updateSearchMatches(q);
                if ~isempty(obj.SearchMatches)
                    obj.SearchIndex = 1;
                    obj.selectMatch(obj.SearchIndex);
                else
                    uialert(obj.UIFig,'No matches found.','Search');
                end
            else
                % Clear search state when field is empty
                obj.SearchMatches = {};
                obj.SearchIndex = 0;
            end
        end

        function selectMatch(obj, idx)
            if isempty(obj.SearchMatches) || idx < 1 || idx > numel(obj.SearchMatches)
                return
            end
            node = obj.SearchMatches{idx};
            
            % Make node visible (expand parents)
            obj.expandParents(node);
            
            % Select node
            obj.Tree.SelectedNodes = node;
            
            % Update UI display manually
            obj.nodeSelected(struct('SelectedNodes',node));
            
            % Update SearchIndex
            obj.SearchIndex = idx;
            
            % Scroll to make the node visible (if possible)
            drawnow
            try
                % Try to ensure the selected node is visible
                node.scrollIntoView();
            catch
                % If scrollIntoView is not available, just continue
            end
        end

        function expandParents(obj, node)
            % Expand parents up to top to make the node visible
            cur = node.Parent;
            while ~isempty(cur) && ~isa(cur,'uitree')
                try
                    % Try different methods to expand nodes
                    if isprop(cur, 'Expanded')
                        cur.Expanded = true;
                    elseif ismethod(cur, 'expand')
                        cur.expand();
                    end
                catch
                    % If expansion fails, continue anyway
                end
                cur = cur.Parent;
            end
        end

        function searchNext(obj)
            if isempty(obj.SearchMatches)
                return
            end
            obj.SearchIndex = obj.SearchIndex + 1;
            if obj.SearchIndex > numel(obj.SearchMatches)
                obj.SearchIndex = 1; % Wrap around to first
            end
            obj.selectMatch(obj.SearchIndex);
        end

        function searchPrev(obj)
            if isempty(obj.SearchMatches)
                return
            end
            obj.SearchIndex = obj.SearchIndex - 1;
            if obj.SearchIndex < 1
                obj.SearchIndex = numel(obj.SearchMatches); % Wrap around to last
            end
            obj.selectMatch(obj.SearchIndex);
        end

        % Helper method to check if a node has leaf descendants
        function tf = hasLeafDescendants(obj, node)
            % If this node itself is a leaf parent
            if ~isempty(node.Children) && all(arrayfun(@(child) obj.isLeaf(child.NodeData), node.Children))
                tf = true;
                return
            end
            
            % Check if any children have leaf descendants
            for i = 1:numel(node.Children)
                if obj.hasLeafDescendants(node.Children(i))
                    tf = true;
                    return
                end
            end
            
            tf = false;
        end

        % Convert MATLAB struct -> JSON file (embedded)
        function jsonwrite(~, filename, data)
            % Try modern pretty print option; fallback if not supported
            try
                txt = jsonencode(data, 'PrettyPrint', true);
            catch
                txt = jsonencode(data); % no pretty print
            end
            fid = fopen(filename,'w');
            if fid < 0
                error('Cannot open file for writing: %s', filename);
            end
            fwrite(fid, txt, 'char');
            fclose(fid);
        end

        % Update window title with current config file path
        function updateWindowTitle(obj)
            if isempty(obj.ConfigFile)
                windowTitle = 'QuIDBBIDS Config Editor - No file loaded';
            else
                pathParts = strsplit(obj.ConfigFile, filesep);
                if length(pathParts) > 5
                    displayPath = fullfile('...', pathParts{end-2:end});
                else
                    displayPath = obj.ConfigFile;
                end
                windowTitle = ['QuIDBBIDS Config Editor - ' displayPath];
            end
            
            if ~isempty(obj.UIFig) && isvalid(obj.UIFig)
                obj.UIFig.Name = windowTitle;
            end
        end

    end

end

classdef ConfigEditorGUI < handle
% ConfigEditorGUI is a GUI-based JSON config editor
%
% Input:
%  CONFIGFILE - If empty or not provided, a file dialog is opened.
%  CONFIG     - If  is empty or not provided, a file dialog is opened.
%  WORKERS    - Optional cell array of top-level keys to show (empty => all)
%
% Usage:
%  app = qb.ConfigEditorGUI(configfile, config, workers);
%  uiwait(app.Fig);
%
% See also: qb.configeditor

    properties
        Fig
        ConfigFile
        Config
    end

    properties (Access = ?TestConfigEditorGUI)
        OrigConfig
        Workers
        Tree
        RootNodes           % array of top-level nodes (children of tree)

        % Right-side editor
        DescArea            % uitextarea (non-editable)
        ValField            % uieditfield (or uieditfield('text'))
        ValLabel            % uilabel for the value field that we can update
        ResetLeafBtn

        % Search controls
        SearchField
        BtnSearchNext
        BtnSearchPrev
        SearchMatches       % cell array of nodes that match
        SearchIndex = 0
        SearchResultsLabel  % uilabel for search results counter

        % Bottom buttons
        BtnLoad
        BtnSave
        BtnResetAll
        BtnCancel
    end

    methods
        function obj = ConfigEditorGUI(configfile, config, workers)
            % CONFIGEDITORGUI Constructor to validate input and ask for file if needed
            %
            % See the QB.CONFIGEDITOR wrapper for usage

            % Get the configfile
            if nargin < 1 || isempty(configfile)
                [f,p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file');
                if isequal(f,0)
                    obj.ConfigFile = [];
                    return
                end
                configfile = fullfile(p,f);
            end
            obj.ConfigFile = configfile;

            % Get the config
            if nargin < 2 || isempty(config) || isempty(fieldnames(config))
                try
                    txt = fileread(configfile);
                    config = jsondecode(txt);
                catch ME
                    errordlg(['Unable to read/parse JSON: ' ME.message],'File Error')
                    return
                end
            end
            obj.Config     = config;
            obj.OrigConfig = config;

            % Set the workers that are to be edited
            if nargin < 3
                workers = {};
            end
            obj.Workers = workers;

            % Build GUI
            obj.buildGUI()

            % Populate tree
            obj.populateTree()
        end

        function delete(obj)
            % Destructor-like convenience to close figure if still open
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                close(obj.Fig);
            end
        end
    end

    methods (Access = ?TestConfigEditorGUI)

        function buildGUI(obj)
            % build GUI layout with uifigure

            % Create main uifigure
            obj.Fig = uifigure('Position',[300 100 745 650]);
            obj.updateWindowTitle()

            % Left panel (tree + search)
            leftX = 20; leftW = 360;        % Tree area rectangle in pixels
            
            % Create search label and field
            uilabel(obj.Fig,'Text','Search:', 'Position',[leftX 607 50 22], 'HorizontalAlignment','left');
            obj.SearchField = uieditfield(obj.Fig,'text','Position',[leftX+50 606 leftW-50 24], 'ValueChangingFcn',@(src,evt)obj.onSearchLive(evt), 'ValueChangedFcn',@(src,evt)obj.onSearchEnter(evt), 'Value','');
            
            % Prev/Next buttons
            obj.BtnSearchPrev = uibutton(obj.Fig,'Text','◀','Position',[leftX    572 40 24], 'ButtonPushedFcn',@(~,~)obj.searchPrev());
            obj.BtnSearchNext = uibutton(obj.Fig,'Text','▶','Position',[leftX+45 572 40 24], 'ButtonPushedFcn',@(~,~)obj.searchNext());

            % Search results counter
            obj.SearchResultsLabel = uilabel(obj.Fig,'Text','','Position',[leftX+95 572 80 24], 'HorizontalAlignment','left');

            % Info label for search state
            uilabel(obj.Fig,'Text','(supports *, ? and regex wildcards)','Position',[leftX+120 572 220 24], 'FontAngle','italic', 'HorizontalAlignment','left');

            % Tree (use uitree within uifigure)
            obj.Tree = uitree(obj.Fig, 'Position',[leftX 20 leftW 536], 'Multiselect','off', 'SelectionChangedFcn',@(src,evt)obj.nodeSelected(evt));

            % Right panel (Description and edit area)
            rpX = leftX + leftW + 20;
            rpW = 745 - rpX - 20;
            topY = 606 + 24;
            txtAreaH = 175;

            % Description box
            obj.DescArea = uitextarea(obj.Fig, 'Position',[rpX, topY - txtAreaH, rpW, txtAreaH], 'Editable','off');

            % Value label (10 px below textarea)
            valueLabelY = topY - txtAreaH - 10 - 22;
            obj.ValLabel = uilabel(obj.Fig,'Text','Value:', 'Position',[rpX valueLabelY 200 22], 'HorizontalAlignment','left');

            % Value edit field
            obj.ValField = uieditfield(obj.Fig,'text', 'Position',[rpX valueLabelY - 40 rpW 40], 'ValueChangedFcn',@(src,~)obj.updateLeafFromField());

            % Reset button
            btnY = 20; btnH = 30; btnW = 70; gap = 15;
            obj.ResetLeafBtn = uibutton(obj.Fig, 'Text','↺ Reset', 'Position',[rpX+rpW-btnW valueLabelY-83 btnW btnH], 'ButtonPushedFcn',@(~,~)obj.resetLeaf());

            % Bottom row buttons
            obj.BtnResetAll = uibutton(obj.Fig, 'Text','Reset All', 'Position',[rpX              btnY btnW btnH], 'ButtonPushedFcn',@(~,~)obj.resetAll());
            obj.BtnCancel   = uibutton(obj.Fig, 'Text','✗ Cancel',  'Position',[rpX+1*(btnW+gap) btnY btnW btnH], 'ButtonPushedFcn',@(~,~)close(obj.Fig));
            obj.BtnLoad     = uibutton(obj.Fig, 'Text','📂 Load',   'Position',[rpX+2*(btnW+gap) btnY btnW btnH], 'ButtonPushedFcn',@(~,~)obj.loadJSON());
            obj.BtnSave     = uibutton(obj.Fig, 'Text','💾 Save',   'Position',[rpX+3*(btnW+gap) btnY btnW btnH], 'ButtonPushedFcn',@(~,~)obj.saveJSON());
        end

        function populateTree(obj)
            % populate tree directly with top-level keys (no single "config" root)

            delete(obj.Tree.Children)

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
                    continue
                end
                node = uitreenode(obj.Tree,'Text',key,'NodeData',obj.Config.(key));
                obj.buildSubtree(node, obj.Config.(key))
                obj.RootNodes(end+1) = node;
            end

            % Clear search state
            obj.SearchMatches = {};
            obj.SearchIndex = 0;
            obj.SearchResultsLabel.Text = '';
        end

        function buildSubtree(obj, parentNode, value)
            % recursively add children to the tree up to leaves

            for nm = fieldnames(value)'
                child = value.(nm{1});
                node  = uitreenode(parentNode,'Text',nm{1},'NodeData',child);
                if ~obj.isLeaf(child)
                    obj.buildSubtree(node, child)
                end
            end
        end

        function refreshSubtree(obj, path)
            % Refresh the subtree in the tree corresponding to path (3 levels: worker/tree/subtree)

            subtreeNode = findNodeByPath(path);
            delete(subtreeNode.Children)

            newData = obj.Config;
            for p = path
                newData = newData.(p{1});
            end
            subtreeNode.NodeData = newData;
            obj.buildSubtree(subtreeNode, newData)

            obj.Tree.SelectedNodes = subtreeNode;
            obj.nodeSelected(struct('SelectedNodes', subtreeNode))

            function node = findNodeByPath(path)
                node = obj.Tree;
                for i = 1:numel(path)
                    idx  = find(strcmp({node.Children.Text}, path{i}), 1);
                    node = node.Children(idx);
                end
            end
        end

        function tf = isLeaf(obj, S)
            fields = fieldnames(S);
            tf = ismember('value', fields) && ismember('description', fields) && numel(fields) == 2;
        end

        function nodeSelected(obj, evt)
            % callback when a tree node is selected

            node = evt.SelectedNodes;
            if isempty(node)
                obj.DescArea.Value = '';
                obj.ValField.Value = '';
                obj.ValLabel.Text  = 'Value:';  % Reset to default
                return
            end

            % Update the value label to show the selected node's name
            obj.ValLabel.Text = [node.Text ':'];
            
            % Show description and the current value
            data = node.NodeData;
            if obj.isLeaf(data)
                if isstring(data.description)
                    obj.DescArea.Value = cellstr(data.description);
                elseif ischar(data.description)
                    obj.DescArea.Value = {data.description};
                else        % fallback: encode as JSON
                    obj.DescArea.Value = {jsonencode(data.description)};
                end
                obj.ValField.Value = obj.valueToStringForDisplay(data.value);
            else
                obj.DescArea.Value = {'(not editable)'};
                obj.ValField.Value = '';
            end
        end

        function s = valueToStringForDisplay(~, val)
            % Format various MATLAB types to a string representation suitable for editing

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

        function updateLeafFromField(obj)
            % Attempt to update current selected leaf value from the ValField contents, with qsm/r2s as a special case

            node = obj.Tree.SelectedNodes;
            if isempty(node)
                return
            end
            
            % Check if this leaf belongs to qsm or r2s subtree
            path = obj.nodePath(node);
            if numel(path) >= 3
                workerName  = path{1};  % Top-level key (e.g., 'QSMWorker')
                treeName    = path{2};  % Second-level key (e.g., 'QSM' or 'R2starmap')
                subtreeName = path{3};  % Third-level key (e.g., 'qsm' or 'r2s')
                if ischar(node.NodeData.value) && strcmp(workerName, 'QSMWorker') && ismember(subtreeName, {'unwrap','bfr','qsm'})
                    obj.openSepiaGUI(path)
                    return
                end
            end
            
            % Try robust parsing:
            % - If oldVal numeric: try JSON decode or str2num
            % - If oldVal logical: accept true/false/1/0
            % - If oldVal is char/string: accept as string (if user provided JSON string decode if quoted)
            % - For cell/struct/array: prefer jsondecode
            data     = node.NodeData;
            oldVal   = data.value;
            newVal   = [];
            txt      = strtrim(obj.ValField.Value);
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
                warndlg('Could not parse the value into the required type. Try JSON format for arrays/objects (e.g. [1,2,3] or {"a":1}).','Parse error')
                return
            end

            % Accept new value
            data.value = newVal;
            node.NodeData = data;

            % Update underlying obj.Config: find path and set there too
            obj.Config = obj.setValueInStruct(obj.Config, path, data);
        end

        function openSepiaGUI(obj, path)
            % Open SEPIA GUI to edit QSM or R2starmap (menu) parameters
            
            obj.Fig.Visible = 'off';   % Hide main GUI while SEPIA is open
            cleanup = onCleanup(@() set(obj.Fig, 'Visible', 'on'));  % Ensure main GUI is shown again on function exit
            try
                w = helpdlg({sprintf('Opening SEPIA GUI for configuring "%s.%s.%s" settings', path{1:3});'(please wait a few seconds)';'';'NB: This resets the current settings';''}, 'SEPIA Config Editor');
                pause(0.1)      % Give time to render dialog
                h = sepia();    % Opens the full SEPIA GUI
            catch ME
                errordlg(['Failed to open SEPIA GUI: ' ME.message], 'Editor Error')
            end
            
            % Show only the subtree tab
            eventdata.OldValue = h.TabGroup.SelectedTab;
            for tab = fieldnames(h.Tabs)'
                if ~( strcmp(tab, path{3}) || ...
                     (strcmp(tab,'phaseUnwrap') && strcmp(path{3}, 'unwrap')) || ...
                     (strcmp(tab,'bkgRemoval')  && strcmp(path{3}, 'bfr')))
                    h.Tabs.(char(tab)).Parent = [];
                    continue
                end
                eventdata.NewValue     = h.Tabs.(char(tab));
                h.TabGroup.SelectedTab = h.Tabs.(char(tab));
                h.TabGroup.SelectionChangedFcn(h.TabGroup, eventdata)
                % currentData = obj.Config.(path{1}).(path{2}).(path{3});
                % h.load_config(currentData)                % Too complex, use SEPIA defaults
                h.pushbutton_loadConfig.Visible = 'off';    % Too complex, use SEPIA defaults
                h.pushbutton_start.String       = 'Done';
                h.dataIO.edit.output.String     = tempname;
                h.StepsPanel.dataIO.Visible     = 'off';
            end

            % Wait for user to finish
            if isvalid(w), close(w), end
            uiwait(h.fig)
            disp('SEPIA configuration editing done')

            % Update the config with the new parameters
            if isfield(h.fig.UserData, 'algorParam') && ~isempty(h.fig.UserData.algorParam)
                obj.Config.(path{1}).(path{2}).(path{3}) = obj.make_leaves(h.fig.UserData.algorParam.(path{3}));
                obj.refreshSubtree(path(1:3))
                w = helpdlg(sprintf('%s.%s.%s configuration updated\n\nClosing SEPIA...', path{1:3}), 'SEPIA Config Editor');
                pause(0.1)      % Give time to render dialog
            end
            delete([h.dataIO.edit.output.String '*'])   % Cleanup SEPIA's temp configfiles
            if isvalid(h.fig), close(h.fig), end
            % if isvalid(w), close(w), end  % The helpdlg is closed prematurely (before the h.fig teardown is ready)
        end

        function param = make_leaves(obj, S)
            % Recursively convert a struct S into a struct with leaves having 'value' and 'description' fields
            param = struct();
            for key = fieldnames(S)'
                val = S.(char(key));
                if isstruct(val)
                    param.(char(key)) = obj.make_leaves(val);
                else
                    param.(char(key)) = struct('value', val, 'description', '');
                end
            end
        end

        function resetLeaf(obj)
            % Reset selected leaf to original value
            node = obj.Tree.SelectedNodes;
            if isempty(node), return; end
                
            origLeaf = obj.getOriginalLeaf(node);
            node.NodeData.value = origLeaf.value;
            % Update display
            obj.nodeSelected(struct('SelectedNodes',node))
            % Update main config too
            obj.Config = obj.setValueInStruct(obj.Config, obj.nodePath(node), node.NodeData);
        end

        function leaf = getOriginalLeaf(obj, node)
            % Get original leaf from OrigConfig by node path
            path = obj.nodePath(node);
            cur = obj.OrigConfig;
            for i = 1:numel(path)
                cur = cur.(path{i});
            end
            leaf = cur;
        end

        function resetAll(obj)
            % Reset all to original config
            obj.Config = obj.OrigConfig;
            obj.populateTree()
            obj.nodeSelected(struct('SelectedNodes',[]))
            obj.SearchField.Value = '';
            obj.SearchResultsLabel.Text = '';
        end

        function loadJSON(obj)
            % Load JSON from a new file selected via file dialog and repopulate the tree
            
            % Open file dialog to select JSON file
            if strcmp(obj.Fig.Visible, 'on')
                [f, p] = fileparts(obj.ConfigFile);
                [f, p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file to load', fullfile(f,p));
                if isequal(f, 0)
                    return
                end
                obj.ConfigFile = fullfile(p, f);
            end

            try
                % Read and parse the new JSON file
                obj.Config = jsondecode(fileread(obj.ConfigFile));
                
                % Update the application state and window title
                obj.OrigConfig = obj.Config;
                obj.updateWindowTitle()
                
                % Refresh the tree, search state and clear right panel
                obj.populateTree()
                obj.nodeSelected(struct('SelectedNodes',[]))
                obj.SearchField.Value = '';
                obj.SearchResultsLabel.Text = '';
            catch ME
                errordlg(['Unable to load/parse JSON: ' ME.message],'Load error')
            end
        end

        function saveJSON(obj)
            % Save current tree -> JSON file selected via file dialog

            % Open file dialog to select save location
            if strcmp(obj.Fig.Visible, 'on')
                [f, p] = uiputfile({'*.json','JSON Files (*.json)'}, 'Save configuration as...', obj.ConfigFile);
                if isequal(f, 0)
                    return
                end
                obj.ConfigFile = fullfile(p, f);
            end
            obj.updateWindowTitle()
            
            % Reconstruct config struct from tree and save it
            partial = obj.treeToStruct();
            obj.Config = obj.mergeIntoOriginal(obj.OrigConfig, partial);
            try
                txt = jsonencode(obj.Config, 'PrettyPrint', true);
                fid = fopen(obj.ConfigFile,'w');
                if fid < 0
                    error('QuIDBBIDS:ConfigEditor:IOError', 'Cannot open file for writing: %s', obj.ConfigFile)
                end
                fwrite(fid, txt, 'char');
                fclose(fid);
            catch ME
                errordlg(['Failed to save: ' ME.message],'Save error')
            end
        end

        function out = mergeIntoOriginal(obj, orig, partial)
            out = orig;
            fields = fieldnames(partial);
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(orig, f) && isstruct(partial.(f)) && isstruct(orig.(f))
                    % Recursive merge
                    out.(f) = obj.mergeIntoOriginal(orig.(f), partial.(f));
                else
                    % Overwrite or add
                    out.(f) = partial.(f);
                end
            end
        end

        function S = treeToStruct(obj)
            % Reconstruct struct from tree nodes
            S = struct();
            for i = 1:numel(obj.RootNodes)
                key = obj.RootNodes(i).Text;
                S.(key) = nodeToStruct(obj.RootNodes(i));
            end

            function s = nodeToStruct(node)
                children = node.Children;
                if isempty(children)
                    % leaf node's NodeData is itself a struct with fields value & description
                    s = node.NodeData;
                    return
                end
                s = struct();
                for j = 1:numel(children)
                    nm = children(j).Text;
                    s.(nm) = nodeToStruct(children(j));
                end
            end
        end

        function S = setValueInStruct(~, S, path, leafStruct)
            % Helper function to set value in nested struct given path cell array
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

        function path = nodePath(~, node)
            % Build path (cell array of keys) from a node up to top-level

            path = {};
            
            % Traverse up the tree until we hit the root tree object
            while ~isempty(node) && ~isa(node, 'matlab.ui.container.Tree')
                % Only add nodes that have Text property (uitreenode objects)
                if isprop(node, 'Text')
                    path = [{node.Text}, path]; %#ok<AGROW>
                end
                node = node.Parent;
            end
        end

        %% SEARCH: Find any node matching pattern
        function updateSearchMatches(obj, pattern)
            obj.SearchMatches = {};
            obj.SearchIndex = 0;            
            if isempty(pattern)
                return
            end
            
            % Convert search query to regex pattern with smart wildcard handling
            pattern = lower(strtrim(pattern));
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

        function onSearchLive(obj, evt)

            obj.updateSearchMatches(strtrim(evt.Value))

            if ~isempty(obj.SearchMatches)
                obj.SearchIndex = 1;
                obj.selectMatch(1);
            else
                obj.SearchIndex = 0;
                obj.updateSearchResultsLabel()
            end
        end

        function onSearchEnter(obj, evt)

            obj.updateSearchMatches(strtrim(evt.Value));

            if ~isempty(obj.SearchMatches)
                obj.SearchIndex = 1;
                obj.selectMatch(1)
            else
                uialert(obj.Fig,'No matches found','Search')
            end
        end

        function collectMatchingNodes(obj, node, pattern)
            % Check if this node's text matches the pattern
            if ~isempty(regexp(lower(node.Text), pattern, 'once'))
                obj.SearchMatches{end+1} = node; 
            end
            
            % Continue searching in all children
            for i = 1:numel(node.Children)
                obj.collectMatchingNodes(node.Children(i), pattern)
            end
        end

        function selectMatch(obj, idx)
            if isempty(obj.SearchMatches) || idx < 1 || idx > numel(obj.SearchMatches)
                return
            end
            node = obj.SearchMatches{idx};
            obj.expandParents(node)                         % Make node visible (expand parents)
            obj.Tree.SelectedNodes = node;                  % Select node
            obj.nodeSelected(struct('SelectedNodes',node))  % Update UI display manually
            obj.SearchIndex = idx;
            obj.updateSearchResultsLabel()                  % Update SearchIndex and results label
            drawnow                                         % Force UI update to ensure tree renders expanded state
        end

        function updateSearchResultsLabel(obj)
            % Simple search results counter
            if isempty(obj.SearchMatches)
                obj.SearchResultsLabel.Text = '';
            else
                obj.SearchResultsLabel.Text = sprintf('%d/%d', obj.SearchIndex, numel(obj.SearchMatches));
            end
        end

        function expandParents(obj, node)
            % Expand parents up to top to make the node visible
            cur = node.Parent;
            while ~isempty(cur) && ~isa(cur,'uitree')
                try
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
            obj.selectMatch(obj.SearchIndex)
        end

        function searchPrev(obj)
            if isempty(obj.SearchMatches)
                return
            end
            obj.SearchIndex = obj.SearchIndex - 1;
            if obj.SearchIndex < 1
                obj.SearchIndex = numel(obj.SearchMatches);     % Wrap around to last
            end
            obj.selectMatch(obj.SearchIndex)
        end

        function updateWindowTitle(obj)
            % Update window title with current config file path

            if isempty(obj.ConfigFile)
                windowTitle = 'QuIDBBIDS Config Editor - No file loaded';
            else
                pathParts = strsplit(obj.ConfigFile, filesep);
                if length(pathParts) > 5
                    displayPath = fullfile('...', pathParts{end-2:end});
                else
                    displayPath = obj.ConfigFile;
                end
                windowTitle = "QuIDBBIDS Config Editor - " + displayPath;
            end
            
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                obj.Fig.Name = windowTitle;
            end
        end

    end

end

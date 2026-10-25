classdef ConfigEditor < handle
% ConfigEditor is a GUI-based JSON config editor for QuIDBBIDS. It allows users
% to view and edit configuration parameters in a structured way, with support for
% searching, resetting, and saving configurations. The General.BIDS(.include)
% subtree is hidden to avoid issues (as editing it requires re-scanning of BIDS)
%
% Input:
%  CONFIGFILE - If empty or not provided, a file dialog is opened.
%  CONFIG     - If  is empty or not provided, a file dialog is opened.
%  WORKERS    - Optional cell array of top-level keys to show (empty => all)
%
% Usage:
%  app = qb.GUI.ConfigEditor(configfile, config, workers);
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

    % Search controls
    SearchField
    SearchMatches       % cell array of nodes that match
    SearchIndex = 0
end

methods
    
    function obj = ConfigEditor(configfile, config, workers)
        % CONFIGEDITORGUI Constructor to validate input and ask for file if needed
        %
        % See the QB.CONFIGEDITOR wrapper for usage

        % Get the configfile
        if nargin < 1 || isempty(configfile)
            [f,p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file');
            if isequal(f,0), return, end
            configfile = fullfile(p,f);
        end
        obj.ConfigFile = configfile;

        % Get the config
        if nargin < 2 || isempty(config) || isempty(fieldnames(config))
            try
                config = qb.utils.jsondecode(fileread(configfile));
            catch ME
                errordlg(['Unable to read/parse JSON: ' ME.message], 'File Error')
                return
            end
        end
        obj.Config     = config;
        obj.OrigConfig = config;

        % Set the workers that are to be edited
        if nargin < 3
            workers = {};
        end
        obj.Workers = cellstr(workers);

        % Build the GUI
        obj.buildGUI()
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
        % build GUI layout with uifigure and uigridlayout

        % Create main uifigure with grid layout
        obj.Fig = uifigure(Position=[300 200 900 500]);
        obj.updateWindowTitle()

        % Main 1x2 grid: left panel (tree+search) | right panel (editor)
        mainGrid = uigridlayout(obj.Fig, [1 2], ColumnWidth={230, '1x'});

        % === LEFT PANEL: Search + Tree ===
        leftPanel = uigridlayout(mainGrid, [3 1], RowHeight={20, 20, '1x'});
        % leftPanel.ColumnWidth = {'1x'};

        % Row 1: Search controls
        searchRow = uigridlayout(leftPanel, [1 2], ColumnWidth={50 '1x'}, ColumnSpacing=0, Padding=[0 0 0 0]);
        uilabel(searchRow, Text='Search:', HorizontalAlignment='left');
        obj.SearchField = uieditfield(searchRow, ValueChangingFcn=@(src,evt)obj.onSearchLive(evt), ...
            ValueChangedFcn=@(src,evt)obj.onSearchEnter(evt), Value='');

        % Row 2: Navigation + info
        navRow = uigridlayout(leftPanel, [1 3], ColumnWidth={40, 40, '1x'}, ColumnSpacing=5, Padding=[0 0 0 0]);
        uibutton(navRow, Text='◀', ButtonPushedFcn=@(~,~)obj.searchPrev());
        uibutton(navRow, Text='▶', ButtonPushedFcn=@(~,~)obj.searchNext());
        uilabel(navRow, Text='(supports wildcards)', FontAngle='italic', HorizontalAlignment='center');

        % Row 3: Tree
        obj.Tree = uitree(leftPanel, Multiselect='off', SelectionChangedFcn=@(src,evt)obj.nodeSelected(evt));

        % === RIGHT PANEL: Description, Value, Buttons ===
        rightPanel = uigridlayout(mainGrid, [2 1], RowHeight={'1x' 'fit'}, RowSpacing=10);
        rightPanel.ColumnWidth = {'1x'};
        rightPanel.Padding = [0 0 0 0];

        % Top section: Description, Value label, Value field + Reset
        topSection = uigridlayout(rightPanel, [3 1], RowHeight={'1x' 'fit' 'fit'}, RowSpacing=5);
        obj.DescArea = uitextarea(topSection, Editable='off');
        obj.ValLabel = uilabel(topSection, Text='Value:', HorizontalAlignment='left');

        valRow = uigridlayout(topSection, [1 2], ColumnWidth={'1x' 70}, Padding=[0 0 0 0]);
        obj.ValField = uieditfield(valRow, ValueChangedFcn=@(src,~)obj.updateLeafFromField());
        uibutton(valRow, Text='↺ Reset', ButtonPushedFcn=@(~,~)obj.resetLeaf());

        % Bottom section: Buttons row
        btnRow = uigridlayout(rightPanel, [1 4], ColumnWidth={70 70 70 70});
        uibutton(btnRow, Text='Reset All', ButtonPushedFcn=@(~,~)obj.resetAll());
        uibutton(btnRow, Text='✗ Cancel',  ButtonPushedFcn=@(~,~)close(obj.Fig));
        uibutton(btnRow, Text='📂 Load',   ButtonPushedFcn=@(~,~)obj.loadConfig());
        uibutton(btnRow, Text='💾 Save',   ButtonPushedFcn=@(~,~)obj.saveConfig());
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
            node = uitreenode(obj.Tree, Text=key, NodeData=obj.Config.(key));
            obj.buildSubtree(node, obj.Config.(key))
            obj.RootNodes(end+1) = node;
        end

        % Clear search state
        obj.updateSearchResultsLabel(true)
    end

    function buildSubtree(obj, parentNode, value)
        % recursively add children to the tree up to leaves, except General.BIDS(.include)

        for nm = fieldnames(value)'
            child = value.(nm{1});
            % Skip/don't built/show if a leaf is about BIDS (as that needs re-scanning)
            if strcmp(parentNode.Text, 'General') && strcmp(nm{1}, 'BIDS')
                continue
            end
            node = uitreenode(parentNode, Text=nm{1}, NodeData=child);
            if ~obj.isLeaf(child)
                obj.buildSubtree(node, child)
            end
        end
    end

    function refreshSubtree(obj, path)
        % Refresh the subtree in the tree corresponding to path (3 levels: worker/tree/subtree)

        subtreeNode = findNodeByPath(path);
        delete(subtreeNode.Children)

        % Get the new data for this subtree
        newData = obj.Config;
        for p = path
            newData = newData.(p{1});
        end
        subtreeNode.NodeData = newData;

        % Refresh and select the subtree
        obj.buildSubtree(subtreeNode, newData)
        obj.Tree.SelectedNodes = subtreeNode;
        obj.nodeSelected(struct(SelectedNodes = subtreeNode))
        obj.updateSearchResultsLabel(true)

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

    function tf = isSepiaMenu(obj, path)
        tf = false;
        if numel(path) >= 2
            node        = obj.Tree.SelectedNodes;
            workerName  = path{1};  % Top-level key (e.g., 'QSMWorker')
            treeName    = path{2};  % Second-level key (e.g., 'qsm' or 'r2s')
            if ischar(node.NodeData.value) && ismember(workerName, {'QSMWorker','R2starWorker'}) && ismember(treeName, {'unwrap','bfr','qsm','r2s'})
                tf = true;
            end
        end
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
        obj.ValLabel.Text = [node.Text ' value:'];
        
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
            obj.ValField.Editable = true;
        else
            obj.DescArea.Value = cellstr(qb.workers.help(node.Text));
            obj.ValField.Value = '(not applicable)';
            obj.ValField.Editable = false;
        end
    end

    function s = valueToStringForDisplay(~, val)
        % Format various MATLAB types to a string representation suitable for editing

        % Handle empty values - return empty string to display as empty field
        if isempty(val) || ((ischar(val) || isstring(val)) && strlength(strip(val)) == 0)
            s = '';
            return
        end

        if isnumeric(val) && isscalar(val)
            s = num2str(val);
        else
            try     % For arrays, objects, cells, use JSON representation for clarity
                s = jsonencode(val);
            catch   % fallback: use mat2str for numeric arrays
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
        
        % Check if this leaf is a SEPIA menu and use the SEPIA GUI to edit this leaf (which may change the whole subtree)
        path = obj.nodePath(node);
        if obj.isSepiaMenu(path)
            obj.openSepiaGUI(path)
            return
        end
        
        % Try robust parsing of the entered user data in the field
        % - If oldVal is empty: try JSON decode
        % - If oldVal numeric: try JSON decode or str2num
        % - If oldVal logical: accept true/false/1/0
        % - If oldVal is char/string: accept as string (if user provided JSON string decode if quoted)
        % - For cell/struct/array: prefer jsondecode
        data     = node.NodeData;
        oldVal   = data.value;
        newVal   = oldVal;
        parsedOK = false;
        try
            txt = strip(obj.ValField.Value);
            if isempty(txt)
                newVal   = "";
                parsedOK = true;
            elseif isempty(oldVal) || isequal(oldVal, "")
                newVal   = jsondecode(txt);
                parsedOK = true;
            elseif isnumeric(oldVal)
                % If user typed JSON array like [1,2,3], jsondecode will work
                if startsWith(txt,'[') && endsWith(txt,']') && contains(txt,',')
                    try
                        newVal   = jsondecode(txt);
                        parsedOK = isnumeric(newVal) || islogical(newVal);
                    catch                   % fallback to str2num
                        newVal   = str2num(txt); %#ok<ST2NM>
                        parsedOK = ~isempty(newVal);
                    end
                else
                    newVal   = str2num(txt); %#ok<ST2NM>
                    parsedOK = ~isempty(newVal);
                end

            elseif islogical(oldVal)
                if any(strcmpi(txt,{'true','1'}))
                    newVal   = true;
                    parsedOK = true;
                elseif any(strcmpi(txt,{'false','0'}))
                    newVal   = false;
                    parsedOK = true;
                else
                    try
                        newVal = jsondecode(txt);
                        if islogical(newVal)
                            parsedOK = true;
                        end
                    catch
                    end
                end

            elseif ischar(oldVal) || isstring(oldVal)
                try         % If user provided JSON string with quotes, decode it
                    decoded = jsondecode(txt);
                catch
                    decoded = [];
                end
                if ~isempty(decoded) && ischar(decoded)
                    newVal = string(decoded);
                else        % plain text: keep as string
                    newVal = string(txt);
                end
                parsedOK = true;

            else            % struct/cell/other: attempt jsondecode
                try
                    newVal   = jsondecode(txt);
                    parsedOK = true;
                catch       % as a last resort, attempt eval (risky) only for numeric arrays
                    try
                        newVal   = str2num(txt); %#ok<ST2NM>
                        parsedOK = ~isempty(newVal);
                    catch
                    end
                end
            end
        catch
            parsedOK = false;
        end

        if ~parsedOK
            warndlg('Could not parse the value into the required type. Try JSON format for arrays/objects (e.g. [1,2,3] or {"a":1}).','Parse error')
            newVal = oldVal;
        end

        % Convert column vectors to row vectors for consistency 
        if iscolumn(newVal)
            newVal = newVal';
        end

        % Accept new value
        data.value    = newVal;
        node.NodeData = data;

        % Update obj.Config
        obj.Config = obj.setValueInConfig(obj.Config, path, data);
    end

    function openSepiaGUI(obj, path)
        % Open SEPIA GUI to edit QSM or R2starmap (menu) parameters
        
        obj.Fig.Visible = 'off';                                    % Hide main GUI while SEPIA is open
        cleanup = onCleanup(@() set(obj.Fig, 'Visible', 'on'));     % Ensure main GUI is shown again on function exit
        try
            w = helpdlg({sprintf('Opening SEPIA GUI for configuring "%s.%s" settings', path{1:2});''; ...
                         'Initialization can be slow, please wait a few seconds...⌛';''; ... 
                         sprintf('NB: This overwrites all current "%s.%s" settings', path{1:2});''}, 'SEPIA Config Editor');
            pause(0.1)      % Give time to render the dialog
            h = sepia();    % Opens the full SEPIA GUI
        catch ME
            errordlg(['Failed to open SEPIA GUI: ' ME.message], 'Editor Error')
        end
        
        % Show only the subtree (path{2}) tab of the SEPIA GUI
        eventdata.OldValue = h.TabGroup.SelectedTab;
        for tab = fieldnames(h.Tabs)'
            if ~(strcmp(tab, path{2}) || ...                    % TODO: Check if a `qsm` line needs to be added here
                (strcmp(tab,'phaseUnwrap') && strcmp(path{2}, 'unwrap')) || ...
                (strcmp(tab,'bkgRemoval')  && strcmp(path{2}, 'bfr')) || ...
                (strcmp(tab,'r2star')      && strcmp(path{2}, 'r2s')))
                h.Tabs.(char(tab)).Parent = [];
                continue
            end
            eventdata.NewValue     = h.Tabs.(char(tab));
            h.TabGroup.SelectedTab = h.Tabs.(char(tab));
            h.TabGroup.SelectionChangedFcn(h.TabGroup, eventdata)
            % currentData = obj.Config.(path{1}).(path{2});     % Too complex, use SEPIA defaults
            % h.load_config(currentData)                        % Too complex, use SEPIA defaults
            h.pushbutton_loadConfig.Visible = 'off';            % Too complex, use SEPIA defaults
            h.pushbutton_start.String       = 'Done';
            h.dataIO.edit.output.String     = tempname;
            h.StepsPanel.dataIO.Visible     = 'off';
        end

        % Wait for user to finish
        if isvalid(w), close(w), end
        uiwait(h.fig)
        disp('🔧 SEPIA configuration editing done')

        % Update the config with the new parameters
        if isvalid(h.fig)
            if isfield(h.fig.UserData, 'algorParam') && ~isempty(h.fig.UserData.algorParam)
                obj.Config.(path{1}).(path{2}) = obj.make_leaves(h.fig.UserData.algorParam.(path{2}));
                obj.refreshSubtree(path(1:2))
            end
            delete([h.dataIO.edit.output.String '*'])   % Cleanup SEPIA's temp configfiles
            close(h.fig)
        else
            obj.resetLeaf()    % SEPIA GUI was closed without saving
        end
    end

    function param = make_leaves(obj, S)
        % Recursively convert a struct S into a struct with leaves having 'value' and 'description' fields
        param = struct();
        for key = fieldnames(S)'
            val = S.(char(key));
            if isstruct(val)
                param.(char(key)) = obj.make_leaves(val);
            else
                param.(char(key)) = struct(value=val, description='');
            end
        end
    end

    function resetLeaf(obj)
        % Reset selected leaf to original value
        
        node = obj.Tree.SelectedNodes;
        path = obj.nodePath(node);

        % Return if the data was not changed
        origData = obj.OrigConfig;
        for p = path
            origData = origData.(p{1});
        end
        if isequal(node.NodeData, origData)
            return
        end

        % For SEPIA menu, reset the parent subtree, else just the leaf
        if obj.isSepiaMenu(path)
            obj.Config = obj.setValueInConfig(obj.Config, path(1:2), obj.OrigConfig.(path{1}).(path{2}));
            obj.refreshSubtree(path(1:2))
        else
            leaf = obj.OrigConfig;
            for i = 1:numel(path)
                leaf = leaf.(path{i});
            end
            node.NodeData.value = leaf.value;

            % Update display and main config
            obj.nodeSelected(struct(SelectedNodes = node))
            obj.Config = obj.setValueInConfig(obj.Config, path, node.NodeData);
        end
    end

    function resetAll(obj)
        % Reset all to original config
        obj.Config = obj.OrigConfig;
        obj.populateTree()
        obj.nodeSelected(struct(SelectedNodes = []))
        obj.updateSearchResultsLabel(true)
    end

    function loadConfig(obj)
        % Load JSON from a new file selected via file dialog and repopulate the tree
        
        % Open file dialog to select JSON file
        [f, p] = uigetfile({'*.json','JSON Files (*.json)'}, 'Select configuration file to load', obj.ConfigFile);
        if isequal(f, 0), return, end
        obj.ConfigFile = fullfile(p, f);

        try
            % Read and parse the new JSON file
            obj.Config = qb.utils.jsondecode(fileread(obj.ConfigFile));
            
            % Update the application state, window title and tree
            obj.OrigConfig = obj.Config;
            obj.updateWindowTitle()
            obj.populateTree()
            obj.nodeSelected(struct(SelectedNodes = []))
        catch ME
            errordlg(['Unable to load/parse JSON: ' ME.message],'Load error')
        end
    end

    function saveConfig(obj)
        % Save current config to a JSON file selected via file dialog

        % Open file dialog to select save location
        if obj.Fig.Visible              % Allows silent save during tests
            [f, p] = uiputfile('*.json', 'Save configuration as...', obj.ConfigFile);
            if isequal(f,0), return, end
            obj.ConfigFile = fullfile(p,f);
        end

        try
            txt = jsonencode(obj.Config,'PrettyPrint',true);
            fid = fopen(obj.ConfigFile,'w');
            if fid < 0, error('Cannot open file'), end
            fprintf(fid,'%s',txt);
            fclose(fid);
        catch ME
            errordlg(['Failed to save: ' ME.message],'Save error');
            return
        end

        obj.updateWindowTitle();
    end

    function S = setValueInConfig(obj, S, path, val)
        %SETVALUEINCONFIG Sets a value in a nested Config struct using a path cell array
        %
        % S = obj.setValueInConfig(S, {'a','b','c'}, val)
        %
        % Example:
        %   path = {'MCR_GPUWorker','fixed_params','x_i'}
        %   S.MCR_GPUWorker.fixed_params.x_i = val

        if isscalar(path)
            S.(path{1}) = val;
        else
            S.(path{1}) = obj.setValueInConfig(S.(path{1}), path(2:end), val);
        end
    end

    function path = nodePath(~, node)
        % Build path (cell array of keys) from a node up to top-level

        path = {};
        while ~isempty(node) && ~isa(node, 'matlab.ui.container.Tree')      % Traverse up the tree until we hit the root tree object
            if isprop(node, 'Text')                                         % Only add nodes that have Text property (uitreenode objects)
                path = [{node.Text}, path]; %#ok<AGROW>
            end
            node = node.Parent;
        end
    end

    %% SEARCH: Find any node matching pattern
    function updateSearchMatches(obj, pattern)
        % Collect all nodes whose Text matches the (wildcard) pattern.
        % Wildcards: * = any number of characters, ? = any single character.
        % All other characters are matched literally. Matching is case-insensitive
        % and anchored to the whole node name.

        obj.SearchMatches = {};
        obj.SearchIndex   = 0;
        pattern = lower(strip(string(pattern)));
        if strlength(pattern) == 0
            return
        end

        % Escape regex special characters first, then translate the wildcards
        pattern = char(pattern);
        pattern = regexprep(pattern, '([\\^$|+()\[\]{}])', '\\$1');     % Escape regex specials, except * ? and . (keys are struct fieldnames so can't contain dots)
        pattern = regexprep(pattern, '\*', '.*');                       % * => any number of characters
        pattern = regexprep(pattern, '\?', '.');                        % ? => any single character (a typed . does the same)
        pattern = ['^' pattern '$'];

        % Search across all nodes in tree
        for r = 1:numel(obj.RootNodes)
            obj.collectMatchingNodes(obj.RootNodes(r), pattern);
        end

        % If matches found, point to the first one
        if ~isempty(obj.SearchMatches)
            obj.SearchIndex = 1;
        end
    end

    function onSearchLive(obj, evt)
        % Live search while typing (never touches the contents of the search field)

        obj.updateSearchMatches(evt.Value)

        if ~isempty(obj.SearchMatches)
            obj.selectMatch(1);
        end
    end

    function onSearchEnter(obj, evt)
        % Search when pressing enter / leaving the search field

        obj.updateSearchMatches(evt.Value)

        if ~isempty(obj.SearchMatches)
            obj.selectMatch(1)
        elseif ~isempty(strip(evt.Value))
            uialert(obj.Fig,'No matches found','Search', Icon='warning');
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
        % Select the idx-th match and show only the branch leading to it

        if isempty(obj.SearchMatches) || idx < 1 || idx > numel(obj.SearchMatches)
            return
        end
        node = obj.SearchMatches{idx};
        collapse(obj.Tree)                              % Close everything that was opened before
        obj.expandParents(node)                         % Open only the path to the match
        obj.Tree.SelectedNodes = node;                  % Select node
        obj.nodeSelected(struct(SelectedNodes = node))  % Update UI display manually
        obj.SearchIndex = idx;
        drawnow                                         % Force UI update to ensure tree renders expanded state
    end

    function updateSearchResultsLabel(obj, reset)
        % Reset the search state (clear search bar and matches)
        
        if nargin > 1 && reset
            obj.SearchField.Value   = '';
            obj.SearchMatches       = {};
            obj.SearchIndex         = 0;
        end
    end

    function expandParents(~, node)
        % Expand only the ancestors of node (and not the tree itself), so that node becomes visible

        cur = node.Parent;
        while ~isempty(cur) && isa(cur, 'matlab.ui.container.TreeNode')
            expand(cur)                                     % Expand this node only (no 'all' option)
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
            pathParts = split(obj.ConfigFile, filesep);
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

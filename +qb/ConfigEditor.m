classdef ConfigEditor < handle
% CONFIGEDITOR - A standalone MATLAB App (App Designer style) implemented as a class
% Option C: Full JSON Editor
% Features:
%  - Tree view of JSON structure (uitree / uitreenode)
%  - Inline editing via dialogs
%  - Add/Delete nodes
%  - Reorder array items (Move Up / Move Down)
%  - Undo/Redo stack
%  - Load / Save JSON
%  - Basic JSON validation and pretty printing
%
% Usage:
%   app = ConfigEditor();
%   app.show();
%
% Note: This is a programmatic UI (not an .mlapp). It works in MATLAB R2018b+

properties (Access = public)
    UIFigure            matlab.ui.Figure
    Tree                matlab.ui.container.Tree
    LoadButton          matlab.ui.control.Button
    SaveButton          matlab.ui.control.Button
    AddButton           matlab.ui.control.Button
    DeleteButton        matlab.ui.control.Button
    MoveUpButton        matlab.ui.control.Button
    MoveDownButton      matlab.ui.control.Button
    EditButton          matlab.ui.control.Button
    PrettyButton        matlab.ui.control.Button
    ValidateButton      matlab.ui.control.Button
    SearchField         matlab.ui.control.EditField
    StatusLabel         matlab.ui.control.Label

    % Editor fields
    KeyField            matlab.ui.control.EditField
    ValueField          matlab.ui.control.EditField
    TypeDropDown        matlab.ui.control.DropDown
    ApplyButton         matlab.ui.control.Button

    % Internal data
    data                % MATLAB representation of JSON (struct / cell)
    filepath            % current file path
    CurrentNode         % currently selected uitreenode

    % Undo/Redo
    UndoStack = {}
    RedoStack = {}
    MaxHistory = 100
end

methods
    function app = ConfigEditor()
        app.buildUI();
        app.updateStatus('Ready');
    end

    function show(app)
        app.UIFigure.Visible = 'on';
    end

    function buildUI(app)
        % Create UIFigure
        app.UIFigure = uifigure('Name','JSON Editor','Position',[100 100 1000 600]);

        % Left panel: tree
        app.Tree = uitree(app.UIFigure, 'Position',[20 80 520 500]);
        app.Tree.Multiselect = 'off';
        app.Tree.SelectionChangedFcn = @(src,event)app.onTreeSelectionChanged(event);
        app.Tree.NodeExpandedFcn = @(src,event)app.onTreeNodeExpanded(event);

        % Top buttons
        app.LoadButton = uibutton(app.UIFigure, 'push', 'Text','Load JSON', 'Position',[20 20 80 40], 'ButtonPushedFcn', @(s,e)app.onLoad());
        app.SaveButton = uibutton(app.UIFigure, 'push', 'Text','Save JSON', 'Position',[110 20 80 40], 'ButtonPushedFcn', @(s,e)app.onSave());
        app.PrettyButton = uibutton(app.UIFigure, 'push', 'Text','Pretty Print', 'Position',[200 20 90 40], 'ButtonPushedFcn', @(s,e)app.onPrettyPrint());
        app.ValidateButton = uibutton(app.UIFigure, 'push', 'Text','Validate', 'Position',[300 20 80 40], 'ButtonPushedFcn', @(s,e)app.onValidate());

        app.AddButton = uibutton(app.UIFigure, 'push', 'Text','Add', 'Position',[400 20 60 40], 'ButtonPushedFcn', @(s,e)app.onAdd());
        app.DeleteButton = uibutton(app.UIFigure, 'push', 'Text','Delete', 'Position',[470 20 60 40], 'ButtonPushedFcn', @(s,e)app.onDelete());
        app.MoveUpButton = uibutton(app.UIFigure, 'push', 'Text','Move Up', 'Position',[540 20 70 40], 'ButtonPushedFcn', @(s,e)app.onMoveUp());
        app.MoveDownButton = uibutton(app.UIFigure, 'push', 'Text','Move Down', 'Position',[620 20 70 40], 'ButtonPushedFcn', @(s,e)app.onMoveDown());
        app.EditButton = uibutton(app.UIFigure, 'push', 'Text','Edit', 'Position',[700 20 60 40], 'ButtonPushedFcn', @(s,e)app.onEdit());

        % Search
        uilabel(app.UIFigure, 'Text','Search:', 'Position',[780 40 50 20]);
        app.SearchField = uieditfield(app.UIFigure, 'text', 'Position',[830 40 140 25], 'ValueChangedFcn', @(s,e)app.onSearch());

        % Right panel: editor
        uilabel(app.UIFigure, 'Text','Key', 'Position',[560 540 30 20]);
        app.KeyField = uieditfield(app.UIFigure, 'text', 'Position',[610 540 290 25]);

        uilabel(app.UIFigure, 'Text','Value', 'Position',[560 500 40 20]);
        app.ValueField = uieditfield(app.UIFigure, 'text', 'Position',[610 500 290 25]);

        uilabel(app.UIFigure, 'Text','Type', 'Position',[560 460 40 20]);
        app.TypeDropDown = uidropdown(app.UIFigure, 'Items',{'auto','string','number','logical','object','array','null'}, 'Position',[610 456 150 25], 'Value', 'auto');

        app.ApplyButton = uibutton(app.UIFigure, 'push', 'Text','Apply', 'Position',[780 456 120 30], 'ButtonPushedFcn', @(s,e)app.onApply());

        % Status label
        app.StatusLabel = uilabel(app.UIFigure, 'Text','', 'Position',[20 580 960 20], 'HorizontalAlignment','left');

        % Context menu for tree (right-click)
        cm = uicontextmenu(app.UIFigure);
        uimenu(cm, 'Text', 'Add child', 'MenuSelectedFcn', @(s,e)app.onAdd());
        uimenu(cm, 'Text', 'Delete', 'MenuSelectedFcn', @(s,e)app.onDelete());
        uimenu(cm, 'Text', 'Edit', 'MenuSelectedFcn', @(s,e)app.onEdit());
        app.Tree.ContextMenu = cm;

        % Initialize empty root
        root = uitreenode(app.Tree, 'Text', 'root');
        root.NodeData = struct('key','root','value',struct());
        app.data = struct();
    end

    function updateStatus(app, msg)
        app.StatusLabel.Text = sprintf('[%s] %s', datestr(now, 'HH:MM:SS'), msg);
        drawnow;
    end

    %% Callbacks
    function onLoad(app)
        [file, path] = uigetfile({'*.json;*.txt','JSON files (*.json, *.txt)'; '*.*','All Files'}, 'Select JSON file');
        if isequal(file,0), return; end
        fullpath = fullfile(path,file);
        try
            txt = fileread(fullpath);
            parsed = jsondecode(txt);
            app.pushUndo();
            app.data = parsed;
            app.filepath = fullpath;
            app.rebuildTree();
            app.updateStatus(['Loaded: ' fullpath]);
        catch ME
            uialert(app.UIFigure, ['Failed to load JSON: ' ME.message], 'Load error');
            app.updateStatus('Load failed');
        end
    end

    function onSave(app)
        if isempty(app.filepath)
            [file,path] = uiputfile('config.json','Save JSON as');
            if isequal(file,0), return; end
            app.filepath = fullfile(path,file);
        end
        try
            % Validate before saving
            app.onValidate();
            txt = jsonencode(app.data);
            % try to pretty print
            try
                pretty = app.prettyJSON(txt);
                fid = fopen(app.filepath,'w'); fwrite(fid, pretty); fclose(fid);
            catch
                fid = fopen(app.filepath,'w'); fwrite(fid, txt); fclose(fid);
            end
            app.updateStatus(['Saved: ' app.filepath]);
        catch ME
            uialert(app.UIFigure, ['Failed to save JSON: ' ME.message], 'Save error');
            app.updateStatus('Save failed');
        end
    end

    function onPrettyPrint(app)
        try
            txt = jsonencode(app.data);
            pretty = app.prettyJSON(txt);
            % show in modal dialog with option to copy
            d = dialog('Name','Pretty JSON','Position',[300 200 600 500]);
            ta = uitextarea(d,'Value',pretty,'Position',[10 10 580 480],'Editable','on');
            btn = uicontrol(d,'Style','pushbutton','String','Copy to clipboard','Position',[480 10 100 30],'Callback',@(s,e)clipboard('copy',ta.Value));
        catch ME
            uialert(app.UIFigure, ['Pretty print failed: ' ME.message], 'Error');
        end
    end

    function onValidate(app)
        % Try to encode and decode to ensure valid JSON structure
        try
            txt = jsonencode(app.data);
            jsondecode(txt);
            app.updateStatus('JSON validation: OK');
        catch ME
            uialert(app.UIFigure, ['JSON validation failed: ' ME.message], 'Validation error');
            error('Invalid JSON');
        end
    end

    function onAdd(app)
        % Add a child to current node (or to root if none selected)
        node = app.getSelectedOrRoot();
        prompt = {'New key (or index for arrays):','Value (text)'};
        dlg = inputdlg(prompt, 'Add node', [1 60]);
        if isempty(dlg), return; end
        newKey = strtrim(dlg{1});
        newValRaw = dlg{2};
        newVal = app.interpretValueString(newValRaw);

        app.pushUndo();
        % If parent represents an array (node text like [1]) then append
        if app.isNodeArray(node)
            % append cell
            if ~isfield(node.NodeData,'value') || isempty(node.NodeData.value)
                node.NodeData.value = {newVal};
            else
                node.NodeData.value{end+1} = newVal;
            end
            child = uitreenode(node, 'Text', app.nodeLabel(newKey,newVal));
            child.NodeData = struct('key',newKey,'value',newVal);
        else
            child = uitreenode(node, 'Text', app.nodeLabel(newKey,newVal));
            child.NodeData = struct('key',newKey,'value',newVal);
        end
        app.rebuildStructFromRoot();
        app.updateStatus(['Added node: ' newKey]);
    end

    function onDelete(app)
        node = app.Tree.SelectedNodes;
        if isempty(node), return; end
        node = node(1);
        if strcmp(node.Text,'root')
            uialert(app.UIFigure,'Cannot delete root node','Invalid operation');
            return;
        end
        resp = questdlg(['Delete node ' node.Text ' ?'],'Confirm Delete','Yes','No','No');
        if ~strcmp(resp,'Yes'), return; end
        app.pushUndo();
        parent = node.Parent;
        delete(node);
        % update parent NodeData if needed
        app.rebuildStructFromRoot();
        app.updateStatus('Node deleted');
    end

    function onMoveUp(app)
        node = app.Tree.SelectedNodes;
        if isempty(node), return; end
        node = node(1);
        parent = node.Parent;
        if isempty(parent) || strcmp(node.Text,'root'), return; end
        siblings = parent.Children;
        idx = find(siblings==node);
        if idx>1
            app.pushUndo();
            siblings(idx) = []; siblings = [siblings(1:idx-2); node; siblings(idx:end)];
            parent.Children = siblings; % reorder
            app.rebuildStructFromRoot();
            app.updateStatus('Moved up');
        end
    end

    function onMoveDown(app)
        node = app.Tree.SelectedNodes;
        if isempty(node), return; end
        node = node(1);
        parent = node.Parent;
        if isempty(parent) || strcmp(node.Text,'root'), return; end
        siblings = parent.Children;
        idx = find(siblings==node);
        if idx < numel(siblings)
            app.pushUndo();
            siblings(idx) = []; siblings = [siblings(1:idx-1); siblings(idx); siblings(idx+1:end)];
            parent.Children = siblings; % reorder
            app.rebuildStructFromRoot();
            app.updateStatus('Moved down');
        end
    end

    function onEdit(app)
        node = app.Tree.SelectedNodes;
        if isempty(node), return; end
        node = node(1);
        if strcmp(node.Text,'root')
            uialert(app.UIFigure,'Cannot edit root node','Invalid operation');
            return;
        end
        nd = node.NodeData;
        % If node is primitive, open small dialog
        if app.isPrimitive(nd.value)
            prompt = {'Key:','Value:'};
            dlg = inputdlg(prompt, 'Edit node', [1 60], {nd.key, app.valueToString(nd.value)});
            if isempty(dlg), return; end
            newKey = dlg{1}; newVal = app.interpretValueString(dlg{2});
            app.pushUndo();
            nd.key = newKey; nd.value = newVal; node.NodeData = nd;
            node.Text = app.nodeLabel(newKey,newVal);
            app.rebuildStructFromRoot();
            app.updateStatus('Node edited');
        else
            % For objects/arrays, allow renaming the key only
            prompt = {'Key:'};
            dlg = inputdlg(prompt,'Edit node', [1 40], {nd.key});
            if isempty(dlg), return; end
            newKey = dlg{1};
            app.pushUndo();
            nd.key = newKey; node.NodeData = nd;
            node.Text = app.nodeLabel(newKey, nd.value);
            app.rebuildStructFromRoot();
            app.updateStatus('Node key renamed');
        end
    end

    function onTreeSelectionChanged(app, event)
        node = event.SelectedNode;
        if isempty(node), return; end
        app.CurrentNode = node;
        nd = node.NodeData;
        app.KeyField.Value = string(nd.key);
        if app.isPrimitive(nd.value)
            app.ValueField.Enable = 'on';
            app.ValueField.Value = app.valueToString(nd.value);
            % select type
            if ischar(nd.value) || isstring(nd.value)
                app.TypeDropDown.Value = 'string';
            elseif isnumeric(nd.value)
                app.TypeDropDown.Value = 'number';
            elseif islogical(nd.value)
                app.TypeDropDown.Value = 'logical';
            else
                app.TypeDropDown.Value = 'auto';
            end
        else
            app.ValueField.Enable = 'off';
            if isstruct(nd.value)
                app.ValueField.Value = '<object>';
                app.TypeDropDown.Value = 'object';
            elseif iscell(nd.value)
                app.ValueField.Value = '<array>';
                app.TypeDropDown.Value = 'array';
            else
                app.ValueField.Value = '<non-primitive>';
                app.TypeDropDown.Value = 'auto';
            end
        end
    end

    function onTreeNodeExpanded(app, event)
        % placeholder if lazy loading is desired
    end

    function onSearch(app)
        s = strtrim(app.SearchField.Value);
        if isempty(s)
            app.clearHighlights();
            app.updateStatus('Search cleared');
            return;
        end
        nodes = app.Tree.findall('-depth',inf);
        % simple highlight: change node text to include [match]
        for n = nodes'
            if contains(n.Text,s,'IgnoreCase',true)
                n.FontAngle = 'normal';
                n.FontWeight = 'bold';
            else
                n.FontWeight = 'normal';
            end
        end
        app.updateStatus(['Search: ' s]);
    end

    function onApply(app)
        node = app.CurrentNode;
        if isempty(node), uialert(app.UIFigure,'No node selected','Apply'); return; end
        newKey = char(app.KeyField.Value);
        newValStr = char(app.ValueField.Value);
        typ = app.TypeDropDown.Value;
        app.pushUndo();
        if strcmp(typ,'object') || strcmp(typ,'array')
            % Only allow renaming key
            nd = node.NodeData; nd.key = newKey; node.NodeData = nd; node.Text = app.nodeLabel(newKey, nd.value);
            app.rebuildStructFromRoot();
            app.updateStatus('Renamed complex node');
            return;
        end
        newVal = app.interpretValueString(newValStr);
        nd = node.NodeData;
        nd.key = newKey; nd.value = newVal; node.NodeData = nd;
        node.Text = app.nodeLabel(newKey,newVal);
        app.rebuildStructFromRoot();
        app.updateStatus('Applied changes');
    end

    %% Utility functions
    function rebuildTree(app)
        % Clear and rebuild the tree from app.data
        delete(app.Tree.Children);
        root = uitreenode(app.Tree, 'Text', 'root');
        root.NodeData = struct('key','root','value',app.data);
        app.buildTreeNodes(root, app.data);
        app.Tree.SelectedNodes = root;
    end

    function buildTreeNodes(app, parentNode, data)
        if isstruct(data)
            names = fieldnames(data);
            for i=1:numel(names)
                key = names{i};
                val = data.(key);
                child = uitreenode(parentNode, 'Text', app.nodeLabel(key,val));
                child.NodeData = struct('key',key,'value',val);
                if isstruct(val) || iscell(val)
                    app.buildTreeNodes(child, val);
                end
            end
        elseif iscell(data)
            for i=1:numel(data)
                key = sprintf('[%d]', i);
                val = data{i};
                child = uitreenode(parentNode, 'Text', app.nodeLabel(key,val));
                child.NodeData = struct('key', key, 'value', val);
                if isstruct(val) || iscell(val)
                    app.buildTreeNodes(child, val);
                end
            end
        else
            % primitives should not usually call here for root
        end
    end

    function s = nodeLabel(app, key, value)
        if isstruct(value)
            s = sprintf('%s: <object>', key);
        elseif iscell(value)
            s = sprintf('%s: <array[%d]>', key, numel(value));
        elseif ischar(value) || isstring(value)
            v = char(value);
            if numel(v)>40
                v = [v(1:37) '...'];
            end
            s = sprintf('%s: "%s"', key, v);
        elseif isnumeric(value)
            s = sprintf('%s: %s', key, mat2str(value));
        elseif islogical(value)
            s = sprintf('%s: %s', key, mat2str(value));
        elseif isempty(value)
            s = sprintf('%s: null', key);
        else
            s = sprintf('%s: <%s>', key, class(value));
        end
    end

    function tf = isPrimitive(app, val)
        tf = ischar(val) || isstring(val) || isnumeric(val) || islogical(val) || isempty(val);
    end

    function tf = isNodeArray(app, node)
        nd = node.NodeData;
        tf = iscell(nd.value) || startsWith(node.Text, '[');
    end

    function str = valueToString(app, val)
        if ischar(val)
            str = val;
        elseif isstring(val)
            str = char(val);
        elseif isnumeric(val)
            str = mat2str(val);
        elseif islogical(val)
            str = mat2str(val);
        elseif isempty(val)
            str = '';
        else
            str = '<complex>';
        end
    end

    function val = interpretValueString(app, s)
        s = strtrim(s);
        if isempty(s)
            val = '';
            return;
        end
        % Try common patterns: true/false, null, numeric, array like [1 2]
        if strcmpi(s,'null')
            val = [];
            return;
        end
        if strcmpi(s,'true') || strcmpi(s,'false')
            val = strcmpi(s,'true');
            return;
        end
        % numeric? try str2num
        n = str2num(s); %#ok<ST2NM>
        if ~isempty(n) && isfinite(n)
            val = n;
            return;
        end
        % JSON array/object attempt
        try
            parsed = jsondecode(s);
            val = parsed;
            return;
        catch
            % treat as string
            val = s;
            return;
        end
    end

    function rebuildStructFromRoot(app)
        nodes = app.Tree.Children;
        if isempty(nodes), return; end
        root = nodes(1);
        app.data = app.nodeToValue(root);
    end

    function val = nodeToValue(app, node)
        nd = node.NodeData;
        if isstruct(nd.value)
            % build struct from children
            val = struct();
            children = node.Children;
            for c = 1:numel(children)
                child = children(c);
                key = child.NodeData.key;
                v = app.nodeToValue(child);
                % avoid invalid fieldnames
                safeKey = matlab.lang.makeValidName(key);
                val.(safeKey) = v;
            end
        elseif iscell(nd.value)
            children = node.Children;
            val = cell(1,numel(children));
            for c = 1:numel(children)
                val{c} = app.nodeToValue(children(c));
            end
        else
            % primitive: return actual stored value
            val = nd.value;
        end
    end

    function pushUndo(app)
        if numel(app.UndoStack) >= app.MaxHistory
            app.UndoStack(1) = []; % drop oldest
        end
        app.UndoStack{end+1} = app.deepcopyData(app.data);
        app.RedoStack = {}; % clear redo
    end

    function undo(app)
        if isempty(app.UndoStack), return; end
        app.RedoStack{end+1} = app.deepcopyData(app.data);
        app.data = app.UndoStack{end};
        app.UndoStack(end) = [];
        app.rebuildTree();
        app.updateStatus('Undo');
    end

    function redo(app)
        if isempty(app.RedoStack), return; end
        app.UndoStack{end+1} = app.deepcopyData(app.data);
        app.data = app.RedoStack{end};
        app.RedoStack(end) = [];
        app.rebuildTree();
        app.updateStatus('Redo');
    end

    function d = deepcopyData(app, d)
        % crude deepcopy via json encode/decode
        try
            j = jsonencode(d);
            d = jsondecode(j);
        catch
            % fallback
        end
    end

    function s = prettyJSON(app, jsonText)
        % Simple pretty printer for JSON produced by jsonencode
        % Adds indentation and line breaks.
        indent = 0; s = '';
        i = 1; n = numel(jsonText);
        while i<=n
            ch = jsonText(i);
            if ch=='{' || ch=='['
                s = [s newline repmat('  ',1,indent) ch]; %#ok<AGROW>
                indent = indent + 1;
                s = [s newline repmat('  ',1,indent)]; %#ok<AGROW>
            elseif ch=='}' || ch==']'
                indent = max(indent-1,0);
                s = [s newline repmat('  ',1,indent) ch]; %#ok<AGROW>
            elseif ch==','
                s = [s ch newline repmat('  ',1,indent)]; %#ok<AGROW>
            elseif ch==':'
                s = [s ch ' ']; %#ok<AGROW>
            else
                s = [s ch]; %#ok<AGROW>
            end
            i = i+1;
        end
        % tidy: remove leading empty line
        if startsWith(s,newline)
            s = s(2:end);
        end
    end

    function clearHighlights(app)
        nodes = app.Tree.findall('-depth',inf);
        for n = nodes'
            n.FontWeight = 'normal';
        end
    end
end

end

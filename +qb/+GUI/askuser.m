function chosen = askuser(workers, workitem)
    %ASKUSER GUI for selecting one worker from several candidates.
    %
    % chosen = askuser(workers, workitem)
    % 
    % Inputs: 
    %   workers  - Array of worker structs (as used in create_team)
    %   workitem - String, the product the user is selecting a worker for
    % 
    % Output:
    %   chosen   - Index into the workers array

    % Load glossary
    glossary  = struct();
    glossfile = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+workers','glossary.json');
    if isfile(glossfile)
        glossary = jsondecode(fileread(glossfile));
    end

    % Layout parameters
    figWidth  = 900;
    figHeight = 600;            % Fixed height, will adjust tables within
    margin    = 20;
    spacing   = 20;
    rbWidth   = 200;
    btnHeight = 30;
    
    % Sizing parameters
    minTableHeight = 50;        % Minimum table height (empty table)
    rowHeight      = 24*0.972;  % Height per row (empirical value that works best)
    headerHeight   = 28;        % Table header height
    maxTableHeight = 250;       % Maximum table height

    % Create figure
    fig = uifigure('Name', "Choose the Worker that should make your """ + workitem + """", 'Position', [100 100 figWidth figHeight], 'Visible', 'off');

    % --- Worker radiobutton group (left)
    rbHeight = figHeight - 2*margin - 2*spacing - 2*btnHeight;
    bg = uibuttongroup(fig, 'Position', [margin, margin + 2*btnHeight + 2*spacing, rbWidth, rbHeight], ...
                       'SelectionChangedFcn', @(src,event) updateInfo(event.NewValue.Text));

    % --- Add radio buttons
    names = arrayfun(@(w) strrep(char(w.handle),'qb.workers.',''), workers, 'UniformOutput', false);
    yPos = rbHeight - 30;       % start from top
    for idx = 1:numel(workers)
        uiradiobutton(bg, 'Text', names{idx}, 'Position', [10, yPos, rbWidth-20, 25]);
        yPos = yPos - 20;       % spacing between radio buttons
    end

    % --- Add Cancel and Done buttons
    uibutton(fig, 'push', 'Text', '✗ Cancel', 'FontWeight', 'bold', 'Position', [margin, margin + btnHeight + spacing/2, rbWidth, btnHeight], ...
             'ButtonPushedFcn', @(src,event) doCancel());
    uibutton(fig, 'push', 'Text', '✓ Done', 'FontWeight', 'bold', 'Position', [margin, margin, rbWidth, btnHeight], ...
             'ButtonPushedFcn', @(src,event) doSelect());

    % --- Add resume box (right) - start with placeholder height = 100
    infoWidth = figWidth - 2*margin - rbWidth - spacing;
    info = uitextarea(fig, 'Position', [margin + rbWidth + spacing, figHeight - margin - 100, infoWidth, 100], 'Editable', 'off');

    % --- Add required Workitems table - start with minimal height
    tblNeeds = uitable(fig, 'ColumnName', {'Required items',''}, 'RowName', [], 'ColumnWidth', {120, 'auto'}, ...
                    'Position', [margin + rbWidth + spacing, margin + minTableHeight + spacing, infoWidth, minTableHeight]);

    % --- Add produced Workitems table - start with minimal height
    tblMakes = uitable(fig, 'ColumnName', {'Produced items',''}, 'RowName', [], 'ColumnWidth', {120, 'auto'}, ...
                    'Position', [margin + rbWidth + spacing, margin, infoWidth, minTableHeight]);

    % Select first worker by default
    chosen = [];
    bg.SelectedObject = bg.Children(end);  % MATLAB stacks children from bottom to top
    updateInfo(bg.SelectedObject.Text)

    % Wait for user
    uiwait(helpdlg({"There are multiple workers that can produce: " + workitem, "Please select the one you want to use"}, "Create team"))
    fig.Visible = 'on';
    uiwait(fig)

    % -----------------------
    % Nested helper functions
    % -----------------------

    function updateInfo(workerName)
        w = workers(strcmp(workerName, names));

        % Info box content
        info.Value = splitlines(sprintf('Name: %s\nPreferred: %d\nUses GPU: %d\n\nDescription:\n%s', ...
                                w.name, w.preferred, w.usesGPU, join(w.description, newline)));

        % Tables data
        tblNeeds.Data = makeTableData(w.needs);
        tblMakes.Data = makeTableData(w.makes());

        % Recalculate infoWidth based on current figure width
        infoWidth = fig.Position(3) - 2*margin - rbWidth - spacing;

        % Calculate table heights (header + rows * height)
        neededHeight = max(min(headerHeight + size(tblNeeds.Data, 1) * rowHeight, maxTableHeight), minTableHeight);
        makesHeight  = max(min(headerHeight + size(tblMakes.Data, 1) * rowHeight, maxTableHeight), minTableHeight);
        
        % Position tables from bottom up
        tblMakes.Position = [margin + rbWidth + spacing, margin,                         infoWidth, makesHeight];
        tblNeeds.Position = [margin + rbWidth + spacing, margin + makesHeight + spacing, infoWidth, neededHeight];
        
        % Calculate remaining space for info box using CURRENT figure height
        tablesTop  = tblNeeds.Position(2) + tblNeeds.Position(4);
        infoHeight = max(fig.Position(4) - margin - (tablesTop + spacing), 100);    % Ensure info box has minimum height = 100
        
        % Position info box
        info.Position = [margin + rbWidth + spacing, fig.Position(4) - margin - infoHeight, infoWidth, infoHeight];
    end

    function T = makeTableData(items)
        T = strings(numel(items), 2);
        for k = 1:numel(items)
            T(k, 1) = items(k);
            if isfield(glossary, items(k))
                T(k, 2) = glossary.(items(k));
            end
        end
    end

    function doCancel()
        delete(fig)
    end

    function doSelect()
        chosen = find(strcmp(bg.SelectedObject.Text, names));
        delete(fig)
    end
end

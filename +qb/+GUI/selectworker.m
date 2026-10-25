function chosen = selectworker(workers, workitem)
    %SELECTWORKER GUI for selecting one worker from several candidates.
    %
    % chosen = selectworker(workers, workitem)
    % 
    % Inputs: 
    %   workers  - Array of worker structs (as used in create_team)
    %   workitem - String, the product the user is selecting a worker for
    % 
    % Output:
    %   chosen   - Index into the workers array (empty if cancelled)

    % Load glossary
    glossary  = struct();
    glossfile = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+workers','glossary.json');
    if isfile(glossfile)
        glossary = jsondecode(fileread(glossfile));
    end

    % Layout parameters
    spacing        = 20;        % Spacing between elements
    rbWidth        = 150;       % Width of the radio button group
    rbRowH         = 22;        % Height of (and distance between) radio buttons
    minTableHeight = 50;        % Minimum table height (empty table)
    rowHeight      = 24*0.972;  % Height per row (empirical value that works best)
    headerHeight   = 28;        % Table header height
    maxTableHeight = 250;       % Maximum table height

    % Create figure
    fig = uifigure(Name="Choose the Worker that should make your """ + workitem + """", Position=[100 100 900 700]);
    uialert(fig, ["There are multiple workers that can produce:", "", workitem, "", "Please select the worker you want to use"], "Create team")

    % Main 1x2 grid: left (selection + buttons) | right (info + tables)
    mainGrid = uigridlayout(fig, [1 2], ColumnWidth={rbWidth, '1x'}, Padding=20*ones(1,4), ColumnSpacing=spacing);

    % === LEFT: radio button group, spacer, push buttons ===
    % Rows: radio group (just tall enough for its buttons) | spacer ('1x') | Cancel | Done
    groupHeight = numel(workers) * rbRowH + 20;
    leftGrid = uigridlayout(mainGrid, [4 1], RowHeight={groupHeight, '1x', 25, 25}, Padding=[0 0 0 0], RowSpacing=spacing/2);

    % Radio buttons (a button group is not a grid, so they are positioned by hand, from the top)
    bg = uibuttongroup(leftGrid, SelectionChangedFcn=@(src,event) updateInfo(event.NewValue.Text));
    bg.Layout.Row = 1;
    names = arrayfun(@(w) replace(char(w.handle),'qb.workers.',''), workers, UniformOutput=false);
    rbs   = gobjects(1, numel(workers));
    for idx = 1:numel(workers)
        rbs(idx) = uiradiobutton(bg, Text=names{idx}, Position=[10, groupHeight - 10 - idx*rbRowH, rbWidth-20, rbRowH]);
    end

    % Push buttons
    btnCancel = uibutton(leftGrid, 'push', Text='✗ Cancel', FontWeight='bold', ButtonPushedFcn=@(~,~) close(fig));
    btnCancel.Layout.Row = 3;
    btnDone   = uibutton(leftGrid, 'push', Text='✓ Done',   FontWeight='bold', ButtonPushedFcn=@(~,~) doSelect());
    btnDone.Layout.Row = 4;

    % === RIGHT: info box, Needs table, Makes table ===
    rightGrid = uigridlayout(mainGrid, [3 1], RowHeight={'1x', minTableHeight, minTableHeight}, Padding=[0 0 0 0], RowSpacing=spacing);
    info      = uitextarea(rightGrid, Editable='off');
    tblNeeds  = uitable(rightGrid, ColumnName=["Needs",""], RowName=[], ColumnWidth={120, 'auto'});
    tblMakes  = uitable(rightGrid, ColumnName=["Makes",""], RowName=[], ColumnWidth={120, 'auto'});

    % Select first worker by default
    chosen = [];
    bg.SelectedObject = rbs(1);
    updateInfo(rbs(1).Text)

    % Wait for user
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

        % Set the table heights (header + rows * height), the info box takes the remaining space ('1x')
        neededHeight = max(min(headerHeight + size(tblNeeds.Data, 1) * rowHeight, maxTableHeight), minTableHeight);
        makesHeight  = max(min(headerHeight + size(tblMakes.Data, 1) * rowHeight, maxTableHeight), minTableHeight);
        rightGrid.RowHeight = {'1x', neededHeight, makesHeight};
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

    function doSelect()
        chosen = find(strcmp(bg.SelectedObject.Text, names));
        close(fig)
    end
end

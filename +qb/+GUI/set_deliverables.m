function deliverables = set_deliverables(items, descriptions, deliverables)
    %SET_DELIVERABLES launches a GUI for selecting workitems from ITEMS to be returned as DELIVERABLES
    % 
    % See also: qb.workers.Coordinator.catalog

    if isempty(items)
        warndlg('No deliverables available for this dataset', 'Set Deliverables')
        return
    end

    % Build data with checkbox column
    data = table(ismember(items, deliverables)', items', descriptions', VariableNames=["Selected", "Items", "Descriptions"]);

    % Create the GUI
    H = uifigure(Name='Select your deliverables', Position=[200 100 1000 650], WindowStyle='modal');

    % Main grid: table | buttons
    grid = uigridlayout(H, [2 1], RowHeight={'1x' 'fit'}, Padding=20, RowSpacing=15);

    % Row 1: Table
    T = uitable(grid, Data=data, ColumnWidth={25, 160, 'auto'}, SelectionType='row', ...
                ColumnEditable=[true false false], ColumnName=["", "Deliverable", "Description"]);

    % Row 2: Buttons
    btnGrid = uigridlayout(grid, [1 3], ColumnWidth={90 90 90}, Padding=[0 0 0 0]);
    uibutton(btnGrid, Text='✓ Done',   FontWeight='bold', ButtonPushedFcn=@(~,~) uiresume(H));
    uibutton(btnGrid, Text='↺ Reset',  FontWeight='bold', ButtonPushedFcn=@(~,~) reset_callback(T, deliverables));
    uibutton(btnGrid, Text='✗ Cancel', FontWeight='bold', ButtonPushedFcn=@(~,~) close(H));

    % Wait for user
    uiwait(H)

    % Get result and close the GUI
    if isvalid(H)
        deliverables = T.Data.Items(T.Data.Selected);
        close(H)
    end
end

function reset_callback(T, deliverables)
    T.Data.Selected = ismember(T.Data.Items, deliverables);
end

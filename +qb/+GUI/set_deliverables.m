function deliverables = set_deliverables(items, descriptions, deliverables)
    %SET_DELIVERABLES launches a GUI for selecting workitems from ITEMS to be returned as DELIVERABLES
    % 
    % See also: qb.workers.Coordinator.catalog

    if isempty(items)
        return
    end

    % Build data with checkbox column
    data = table(ismember(items, deliverables)', items', descriptions', VariableNames=["Selected", "Items", "Descriptions"]);

    % Create figure
    H = uifigure(Name='Select your deliverables', Position=[200 200 900 450], WindowStyle='modal');

    % Create table with checkboxes
    T = uitable(H, Data=data, Position=[20 50 860 380], ColumnWidth={40, 200, 'auto'}, SelectionType='row', ...
                ColumnEditable=[true false false], ColumnName=["", "Deliverable", "Description"]);

    % Create buttons
    uibutton(H, Position=[20 15 90 22],  Text='✓ Done',   FontWeight='bold', ButtonPushedFcn=@(~,~) uiresume(H));
    uibutton(H, Position=[120 15 90 22], Text='↺ Reset',  FontWeight='bold', ButtonPushedFcn=@(~,~) reset_callback(T, deliverables));
    uibutton(H, Position=[220 15 90 22], Text='✗ Cancel', FontWeight='bold', ButtonPushedFcn=@(~,~) close(H));

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

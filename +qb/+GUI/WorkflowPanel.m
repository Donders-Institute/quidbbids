classdef WorkflowPanel < handle
% WORKFLOWPANEL - Main GUI for setting up and running a workflow


properties
    Fig
    coord
    manager
end

methods
    
    function obj = WorkflowPanel(coord)
        % Constructor for building the workflow control panel
        arguments
            coord    qb.workers.Coordinator
        end
        
        obj.coord = coord;

        % Close all old QuIDBBIDS figures
        for H = findall(groot, Tag='workflow_axes')'
            close(ancestor(H, 'Figure'))
        end

        % Create a GUI figure
        obj.Fig = uifigure(Name=['Workflow Control Panel - ' coord.BIDS.pth], Position=[200 200 800 500]);

        % Main grid
        mainGrid               = uigridlayout(obj.Fig, [2 2]);
        mainGrid.RowHeight     = {'1x', 'fit'};
        mainGrid.ColumnWidth   = {100, '1x'};
        mainGrid.ColumnSpacing = 20;
        mainGrid.Padding       = [20 20 20 10];   % [left bottom right top]

        % Config buttons
        buttonGrid = uigridlayout(mainGrid, [4 1], RowHeight = {'fit', 'fit', 'fit', 'fit'});
        uibutton(buttonGrid, Text='📂 Open',    Enable='on',  ButtonPushedFcn=@(~,~) obj.onOpen(),         Tooltip='Open a BIDS dataset');
        uibutton(buttonGrid, Text='🛒 Catalog', Enable='on',  ButtonPushedFcn=@(~,~) obj.onDeliverables(), Tooltip='Select deliverables from the workitems catalog');
        uibutton(buttonGrid, Text='🔧 Edit',    Enable='off', ButtonPushedFcn=@(~,~) coord.edit_config(),  Tooltip='Edit worker configurations');
        uibutton(buttonGrid, Text='↺ Reset',    Enable='off', ButtonPushedFcn=@(~,~) obj.reset_config(),   Tooltip='Reset everything');

        % Workflow
        uiaxes(mainGrid, Tag='workflow_axes', XTick=[], YTick=[], Box='on');

        % Control buttons
        buttonGrid = uigridlayout(mainGrid, [2 1], RowHeight = {'fit', 'fit'});
        uibutton(buttonGrid, Text='📂 Load',    Enable='off', ButtonPushedFcn=@(~,~) coord.load_properties(), Tooltip='Load previously saved workflow settings');
        uibutton(buttonGrid, Text='💾 Save',    Enable='off', ButtonPushedFcn=@(~,~) coord.save_properties(), Tooltip='Save your workflow settings');
        uibutton(buttonGrid, Text='▶ Start',    Enable='off', ButtonPushedFcn=@(~,~) obj.start_workflow(),    Tooltip='Start the workflow execution');

        % Redraw the full workflow in the GUI
        coord.get_resumes();

        % Check if we are ready to go
        if ~isempty(coord.deliverables)
            obj.manager = qb.workers.Manager(coord);
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end

    end

    function onOpen(obj)
        % Callback for Open button
        uialert(obj.Fig, '[Open] function is not yet implemented', 'WIP')
    end

    function onDeliverables(obj)
        % Callback for Catalog button
        obj.coord.set_deliverables()
        obj.manager = qb.workers.Manager(obj.coord);
        if ~isempty(obj.coord.deliverables)
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end
    end

    function reset_config(obj)
        % Callback for Reset button
        uialert(obj.Fig, '[Reset] function is not yet implemented', 'WIP')
    end
    
    function start_workflow(obj)
        % Callback for Start button
        
        % Disable user interaction
        set(findobj(obj.Fig, Type='uibutton', Enable='on'), Enable='off')
        cleanup = onCleanup(@() set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on'));
        dlg = helpdlg('Starting the workflow', 'Please wait');

        % Start the workflow
        obj.manager.start_workflow()
        if isvalid(dlg), close(dlg), end
        uialert(obj.Fig, 'The workflow has completed', 'QuIDBBIDS info', Icon='info')
    end
    
end

end

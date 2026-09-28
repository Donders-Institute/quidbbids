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

        % Create figure
        obj.Fig = uifigure(Name=['Workflow Control Panel - ' coord.BIDS.pth], Position=[200 200 800 500]);

        % Main grid
        mainGrid               = uigridlayout(obj.Fig, [2 2]);
        mainGrid.RowHeight     = {'1x', 'fit'};
        mainGrid.ColumnWidth   = {100, '1x'};
        mainGrid.ColumnSpacing = 20;
        mainGrid.Padding       = [20 20 20 10];   % [left bottom right top]

        % Config buttons
        buttonGrid = uigridlayout(mainGrid, [4 1], RowHeight = {'fit', 'fit', 'fit', 'fit'});
        uibutton(buttonGrid, Text='📂 Open',    Enable='on',  ButtonPushedFcn=@(~,~) coord.load_properties());
        uibutton(buttonGrid, Text='🛒 Catalog', Enable='on',  ButtonPushedFcn=@(~,~) obj.onDeliverables());
        uibutton(buttonGrid, Text='🔧 Edit',    Enable='off', ButtonPushedFcn=@(~,~) coord.edit_config());
        uibutton(buttonGrid, Text='↺ Reset',    Enable='off', ButtonPushedFcn=@(~,~) obj.reset_config());

        % Workflow
        uiaxes(mainGrid, Tag='workflow_axes', XTick=[], YTick=[], Box='on');

        % Control buttons
        buttonGrid = uigridlayout(mainGrid, [2 1], RowHeight = {'fit', 'fit'});
        uibutton(buttonGrid, Text='💾 Save',    Enable='off', ButtonPushedFcn=@(~,~) coord.save_properties());
        uibutton(buttonGrid, Text='▶ Start',    Enable='off', ButtonPushedFcn=@(~,~) obj.start_workflow());

        % Check if we are ready to go
        if ~isempty(coord.deliverables)
            obj.manager = qb.workers.Manager(coord);
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end

    end

    function onDeliverables(obj)
        obj.coord.set_deliverables()
        obj.manager = qb.workers.Manager(obj.coord);
        if ~isempty(obj.coord.deliverables)
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end
    end

    function reset_config(obj)
        % Callback for Reset button
    end
    
    function start_workflow(obj)
        % Callback for Start button
        obj.manager.start_workflow()
    end
    
end

end

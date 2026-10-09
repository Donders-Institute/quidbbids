classdef WorkflowPanel < handle
% WORKFLOWPANEL - Main GUI for setting up and running a workflow


properties
    Fig
    coord
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
        buttonGrid = uigridlayout(mainGrid, [6 1], RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'});
        uibutton(buttonGrid, Text='🔍 Inclusion', Enable='on',  ButtonPushedFcn=@(~,~) coord.edit_inclusion(), Tooltip='Edit the raw BIDS inclusion filter');
        uibutton(buttonGrid, Text='🛒 Catalog',   Enable='on',  ButtonPushedFcn=@(~,~) obj.set_deliverables(), Tooltip='Select deliverables from the workitems catalog');
        uibutton(buttonGrid, Text='🔧 Config',    Enable='off', ButtonPushedFcn=@(~,~) coord.edit_config(),    Tooltip='Edit worker configurations');
        uibutton(buttonGrid, Text='📂 Outputdir', Enable='off', ButtonPushedFcn=@(~,~) obj.outputdir(),        Tooltip='Set the directory where output data will be saved');
        uibutton(buttonGrid, Text='📂 Workdir',   Enable='off', ButtonPushedFcn=@(~,~) obj.workdir(),          Tooltip='Set the directory where working data will be saved');
        uibutton(buttonGrid, Text='↺ Reset',      Enable='off', ButtonPushedFcn=@(~,~) obj.reset_config(),     Tooltip='Clear all deliverables and reset the workflow graph');

        % Workflow
        uiaxes(mainGrid, Tag='workflow_axes', XTick=[], YTick=[], Box='on');

        % Control buttons
        buttonGrid = uigridlayout(mainGrid, [2 1], RowHeight = {'fit', 'fit'});
        uibutton(buttonGrid, Text='📂 Load', Enable='off', ButtonPushedFcn=@(~,~) obj.load_workflow(),  Tooltip='Load previously saved workflow settings');
        uibutton(buttonGrid, Text='💾 Save', Enable='off', ButtonPushedFcn=@(~,~) obj.save_workflow(),  Tooltip='Save your workflow settings');
        uibutton(buttonGrid, Text='▶ Start', Enable='off', ButtonPushedFcn=@(~,~) obj.start_workflow(), Tooltip='Save and start the workflow');

        % Redraw the full workflow in the GUI
        coord.get_resumes();

        % Check if we are ready to go
        if ~isempty(coord.deliverables)
            if isempty(obj.coord.manager)
                obj.coord.get_manager()
            end
            obj.coord.manager = qb.workers.Manager(coord);
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end

    end

    function set_deliverables(obj)
        % Callback for Catalog button
        
        % Get new deliverables
        olddeliverables = obj.coord.deliverables;
        obj.coord.set_deliverables()
        newdeliverables = obj.coord.deliverables;
        if isequal(olddeliverables, newdeliverables)
            return
        end

        % Update the workflow manager and enable the GUI buttons
        obj.coord.get_manager()     % Initializing a new manager will draw a new workflow in the GUI
        if isempty(newdeliverables)
            obj.reset_config()
        else
            set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on')
        end
    end

    function outputdir(obj)
        % Callback for Outputdir button
        
        % Get the new output directory
        olddir = obj.coord.outputdir;
        newdir = uigetdir(olddir, 'Select output directory');
        if isequal(olddir, newdir) || isempty(newdir)
            return
        end
        obj.coord.outputdir = string(newdir);

        % Rename or initialize the output directory
        if isempty(dir(fullfile(olddir, 'sub-*'))) && isempty(dir(fullfile(olddir, 'logs')))
            rename(olddir, newdir)
        elseif ~isfile(fullfile(newdir, 'dataset_description.json'))
            bids.init(newdir, 'is_derivative', true)
            copyfile(fullfile(olddir, 'dataset_description.json'), newdir)
            copyfile(fullfile(olddir, 'code'), newdir)
        end
    end

    function workdir(obj)
        % Callback for Workdir button
        
        % Get the new work directory
        olddir = obj.coord.workdir;
        newdir = uigetdir(olddir, 'Select work directory');
        if isequal(olddir, newdir) || isempty(newdir)
            return
        end
        obj.coord.workdir = string(newdir);

        % Rename or initialize the work directory
        if isempty(dir(fullfile(olddir, 'sub-*')))
            rename(olddir, newdir)
        elseif ~isfile(fullfile(newdir, 'dataset_description.json'))
            bids.init(newdir, 'is_derivative', true)
            copyfile(fullfile(olddir, 'dataset_description.json'), newdir)
        end
    end

    function reset_config(obj)
        % Callback for Reset button
        set(findobj(obj.Fig, Type='uibutton', Enable='on'        ), Enable='off')
        set(findobj(obj.Fig, Type='uibutton', Text='🔍 Inclusion'), Enable='on')
        set(findobj(obj.Fig, Type='uibutton', Text='🛒 Catalog'  ), Enable='on')
        obj.coord.deliverables = [];
        obj.coord.manager      = [];
        obj.coord.config       = obj.coord.get_config();
        obj.coord.resumes      = obj.coord.get_resumes();
    end
    
    function load_workflow(obj)
        % Callback for Load button
        obj.coord.load_properties()
        obj.coord.manager.load_properties()
    end
    
    function save_workflow(obj)
        % Callback for Save button
        obj.coord.save_properties()
        obj.coord.manager.save_properties()
    end

    function start_workflow(obj)
        % Callback for Start button
        
        % Disable user interaction
        set(findobj(obj.Fig, Type='uibutton', Enable='on'), Enable='off')
        cleanup = onCleanup(@() set(findobj(obj.Fig, Type='uibutton', Enable='off'), Enable='on'));
        dlg = helpdlg('Starting the workflow', 'Please wait');

        % Start the workflow
        obj.coord.manager.start_workflow()
        if isvalid(dlg), close(dlg), end
        uialert(obj.Fig, 'The workflow has completed', 'QuIDBBIDS info', Icon='info')
    end
    
end

end

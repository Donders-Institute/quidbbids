classdef Manager < handle
    %MANAGER Manages the entire workflow to make the end products that the user wants
    % 
    % This class defines the common interface and base functionality for interacting with the user,
    % composing workflows, setting config parameters, creating a team of workers from the pool, and
    % putting the team to work.
    %
    % Interactive workflow:
    %   0. User initializes the workflow and calls Manager
    %   1. Manager loads an existing workflow from the output directory (if present) and asks user
    %      what products to make
    %   2. Manager assembles a team that can make the products (and asks the user for help if needed)
    %   3. Manager lets the user tweak the config parameters and saves it all back in the output folder
    %   4. Manager puts the team to work (subject by subject or in parallel):
    %       a. For each end product, the manager asks the responsible team worker to produce it
    %       b. If this worker needs a workitem to get the work done, he/she will ask another
    %          team worker to produce it. In turn, that worker can ask other team workers to
    %          produce their workitems -- all the way up until only raw BIDS data items are needed
    %   5. Manager monitors the progress of the workers and informs the user until all work is done
    %   6. Manager fetches the end products and copies them to the output directory
    %
    % Batch workflow:
    %
    % Usage:
    %
    % Limitation:
    %   In the workflow, each workitem is always made by the same worker, i.e. it is not possible to
    %   have a certain workitem produced by one worker in one part of the workflow, but in another part
    %   have that same workitem produced by another worker. The alternative would be to specify the
    %   complete workflow (i.e. all nodes in the graph), which is a much more complicated thing to do
    %
    % See also: qb.QuIDBBIDS (for overview)


    properties
        products    % The end productcs (workitems) requested by the user
        team        % The resumes of the workers that will produce the products: team.(workitem) -> worker resume
        coord       % The coordinator that help the manager with administrative tasks
        force       % Force workers to start working, even if the subject is locked or existing results exist
    end


    methods

        function obj = Manager(coord, products)
            %MANAGER Constructor for the Manager class

            arguments
                coord     qb.workers.Coordinator    % The coordinator that help the manager with administrative tasks
                products  {mustBeText} = ""         % The end productcs (workitems) requested by the user
            end

            obj.coord    = coord;                   % The coordinator that help the manager with administrative tasks
            obj.team     = struct();                % The resumes of the workers that will produce the products: team.(workitem) -> worker resume
            obj.products = products;                % The end productcs (workitems) requested by the user
            obj.force    = false;
            obj.create_team()
        end

        function set.products(obj, val)
            % Force anything assigned to be stored as string
            obj.products = string(val);
        end

        function create_team(obj)
            %CREATE_TEAM Selects workers from the pool that together are capable of making the PRODUCTS (workitems)
            %
            % Asks the user for help if needed. The assembled team is stored in the TEAM property

            arguments
                obj
            end

            % Find and select one capable worker per workitem
            for workitem = obj.products
                for worker = obj.coord.resumes
                    if ismember(workitem, worker.makes)     % Add to the team if the worker is capable
                        if isfield(obj.team, workitem)
                            if ~ismember(func2str(worker.handle), cellfun(@func2str, {obj.team.(workitem).handle}, 'UniformOutput', false))
                                obj.team.(workitem)(end+1) = worker;
                            end
                        else
                            obj.team.(workitem) = worker;
                        end
                    end
                end
                if isfield(obj.team, workitem)
                    if length(obj.team.(workitem)) > 1      % We found multiple capable workers for one workitem
                        selectworker(workitem);             % Keep the preferred worker only
                    end
                    % Recursively add upstream workers to the team
                    if ~isempty(obj.team.(workitem).needs)
                        obj.create_team(obj.team.(workitem).needs)
                    end
                elseif strlength(workitem)
                    error("Could not find a worker that can make: " + workitem)
                end
            end
        end

        function choose_products(obj)
            obj.products = qb.ChooseProducts(obj.coord.resumes);
        end

        function load_workflow(obj)
        end

        function save_workflow(obj)
            %SAVE_WORKFLOW Saves the PRODUCT and TEAM properties to the output directory
        end

        function start_workflow(obj, subjects)
            %START_WORKFLOW For each end product, asks the responsible team worker to fetch it

            arguments
                obj
                subjects struct = obj.coord.BIDS.subjects;
            end

            % Block the start button in the GUI (if any) and initialize the workers
            for product = obj.products      % TODO: sort such that PreprocWorker products (if any) are fetched first
                worker = obj.team.(product).handle;
                for subject = subjects
                    args = {obj.coord.BIDS, subject, obj.coord.config, obj.coord.workdir, obj.coord.outputdir, obj.team};
                    if obj.coord.config.useHPC
                        qsubfeval(worker, args{:}, product, obj.coord.config.qsubfeval.(product){:});
                    else
                        worker(args{:}).fetch(product, obj.force);     % TODO: Catch the work done (at some point)
                    end
                end

                if obj.coord.config.useHPC
                    obj.monitor_progress(product)
                end
            end
            % Unblock the start button in the GUI (if any)
        end

        function monitor_progress(obj, workitem)
            %MONITOR_PROGRESS Watches over the progress of the workers until all work is done

            % Launch a dashboard
            logdir    = fullfile(obj.coord.outputdir, 'logs', class(obj));   % TODO: FIXME
            dashboard = qb.workers.Dashboard(obj.coord.BIDS, logdir, workitem);

            % Wait until all work is done
            while ~all([dashboard.jobs.finished])
                pause(5)
                dashboard.update()
            end

            % Report any errors or warnings
            dashboard.has_warnings(verbose)
            dashboard.has_errors(verbose)

            % Close the dashboard
            dashboard.close()
        end

    end


    methods (Access = private)

        function selectworker(obj, workitem)
            % Select a worker for this workitem and make him/her the "preferred worker"

            % Check if any of the workers is preferred
            preferred = [obj.team.(workitem).preferred];
            if ~any(preferred)
                % TODO: implement GUI to select the worker
                preferred = askuser();
            end

            % Keep the preferred worker only
            obj.team.(workitem)           = obj.team.(workitem)(preferred);
            obj.team.(workitem).preferred = True;
        end

    end

end

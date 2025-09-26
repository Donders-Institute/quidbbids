classdef Manager < handle
    %MANAGER Manages the entire QuIDBBIDS workflow to make the end products that the user wants
    % 
    % This class defines the common interface and base functionality for interacting with the user,
    % composing pipelines, setting config parameters, creating a team of workers from the pool, and
    % putting the team to work.
    %
    % Interactive workflow:
    %   0. User initializes QuIDBBIDS and calls Manager
    %   1. Manager loads an existing workflow from the output directory (if present) and asks user
    %      what products to make
    %   2. Manager assembles a team that can make the products (and asks the user for help if needed)
    %   3. Manager lets the user tweak the config parameters and saves it all back in the output folder
    %   4. Manager puts the team to work (subject by subject or in parallel):
    %       a. For each end product, the manager asks the responsible team worker to produce it
    %       b. If this worker needs a workitem to get the work done, he/she will ask another
    %          team worker to produce it. In turn, that worker can ask other team workers to
    %          produce their workitems -- all the way up untill only raw BIDS data items are needed
    %   5. Manager monitors the progress of the workers and informs the user untill all work is done
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
        team        % The team that will produce the products: team.(workitem) -> worker properties
        quidb
    end


    methods

        function obj = Manager(quidb, products)
            %MANAGER Constructor for the Manager class

            arguments
                quidb     qb.QuIDBBIDS
                products  {mustBeText}      % The end productcs (workitems) requested by the user
            end

            obj.quidb = quidb;
            obj.team  = struct();

            if isempty(products)
                obj.products = obj.ask4products();
            else
                obj.products = products;
            end

        end

        function create_team(obj, workitems)
            %CREATE_TEAM Selects workers from the pool that together are capable of making the WORKITEMS (end products)
            %
            % Asks the user for help if needed. The assembled team is stored in the TEAM property

            arguments
                obj
                workitems {mustBeText}
            end

            % Find and select one capable worker per workitem
            workers = obj.workers_pool();
            for workitem = workitems
                for worker = workers
                    if ismember(workitem, worker.makes)     % Add to the team if the worker is capable
                        if isfield(obj.team, workitem)
                            if ~ismember(worker.handle, [obj.team.(workitem).handle])
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
                    obj.create_team(obj.team.(workitem).needs)
                else
                    error("Could not find a worker that can make: " + workitem)
                end
            end
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
                subjects struct = obj.quidb.BIDS.subjects;
            end

            % Block the GUI (if any) and initialize the workers
            for product = obj.products      % TODO: sort such that PreprocWorker products (if any) are fetched first
                worker = obj.team.(product).handle;
                for subject = subjects
                    if obj.quidb.config.useHPC
                        qsubfeval(worker, obj, subject, product, obj.quidb.config.qsubfeval.(product){:})
                    else
                        worker(obj, subject).fetch(product)
                    end
                end
                if obj.quidb.config.useHPC
                    obj.monitor_progress(product)
                end
            end
        end

        function monitor_progress(obj, workitem)
            %MONITOR_PROGRESS Watches over the progress of the workers untill all work is done

            % Lauch a dashboard (if needed)
        end

    end


    methods (Static)

        function workers = workers_pool()
            %WORKERS_POOL Queries the whole pool of workers that live in qb.workers
            %
            % Output:
            %   WORKERS.HANDLE      - Their function handles
            %          .NAME        - Their personal names
            %          .DESCRIPTION - The descriptions of what they do
            %          .MAKES       - The workitems they can make
            %          .NEEDS       - The workitems they need for work
            %          .PREFERRED   - True if the worker was selected by the user
            %
            % NB: Assumes the qb.workers adhere to a "PrefixWorker.m" naming scheme

            workers = [];
            for mfile = dir(fullfile(fileparts(mfilename("fullpath")), "*Worker.m"))'
                if ~strcmp(mfile.name, 'Worker.m')   % Exclude the abstract Worker class
                    worker = qb.workers.(erase(mfile.name, '.m'))(struct('name','','session',''), qb.QuIDBBIDS('|'), struct());
                    workers(1+end).name        = worker.name;
                    workers(  end).handle      = str2func(class(worker));
                    workers(  end).description = worker.description;
                    workers(  end).makes       = worker.makes;
                    workers(  end).needs       = worker.needs;
                    workers(  end).preferred   = false;
                end
            end
        end

    end


    methods (Private)

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

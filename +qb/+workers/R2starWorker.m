classdef (Sealed) R2starWorker < qb.workers.Worker
%R2STARWORKER Runs R2-star workflow
%
% See also: qb.workers.Worker (for base interface), qb.workers.QSMWorker, qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["R2* relaxometry worker using the SEPIA toolbox."
                   ""
                   "R2starWorker computes R2* (transverse relaxation rate) maps from multi-echo gradient-recalled"
                   "echo (GRE) magnitude data. R2* mapping is a quantitative MRI technique that provides information"
                   "about tissue microstructure and iron content."
                   ""
                   "The worker leverages the SEPIA toolbox (Susceptibility and Phase Imaging Application) to process"
                   "the multi-echo GRE data and generate quantitative R2* maps."
                   ""
                   ".. note::"
                   ""
                   "   SEPIA has its own working directory structure. QSMWorker temporarily switches to the"
                   "   SEPIA directory for processing and renames output files to ensure BIDS compatibility."
                   "   The SEPIA toolbox must be installed and configured."] % Description should be in ReStructuredText format
    needs       = ["ME4Dmag", "brainmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % SEPIA should have a directory of its own (we cannot control it's output very well)
        obj.workdir = replace(obj.workdir, "QuIDBBIDS", "SEPIA");
        if ~isempty(obj.workdir) && ~isfile(fullfile(obj.workdir, 'dataset_description.json'))
            bids.init(char(obj.workdir), 'is_derivative', true)
        end

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.R2starmap = struct(modality = 'anat', ...
                                          echo     = [], ...
                                          suffix   = 'R2starmap');
        obj.bidsfilter.T2starmap = setfields(obj.bidsfilter.R2starmap, suffix='T2starmap');
        obj.bidsfilter.S0map     = setfields(obj.bidsfilter.R2starmap, suffix='S0map');

        % Set the custom "Parent" config key set and replace the QSMWorker config with my own config
        obj.config.Parent    = 'R2starWorker';
        obj.config.QSMWorker = obj.config.R2starWorker;
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get the workitem directly from the QSMWorker using my own config
        QSMworker = qb.workers.QSMWorker(obj.BIDS, obj.subject, obj.config, obj.workdir, obj.outputdir, obj.team);
        QSMworker.get_work_done(workitem)
    end

end

end

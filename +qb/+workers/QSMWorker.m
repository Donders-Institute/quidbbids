classdef (Sealed) QSMWorker < qb.workers.Worker
%QSMWORKER Runs QSM and R2-star workflows
%
% See also: qb.workers.Worker (for base interface), qb.workers.R1R2starWorker, qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["Quantitative Susceptibility Mapping (QSM) and R2* relaxometry worker using the SEPIA toolbox."
                   ""
                   "QSMWorker performs QSM reconstruction and R2* mapping from multi-echo GRE magnitude and phase data."
                   "QSM is a post-processing technique that converts MRI phase data into quantitative susceptibility maps,"
                   "enabling the study of tissue magnetic properties such as iron content, calcium, and myelin."
                   ""
                   "The SEPIA toolbox (Susceptibility and Phase Imaging Application) provides a comprehensive pipeline"
                   "for QSM reconstruction, including phase unwrapping, background field removal, and susceptibility inversion."
                   ""
                   "Processing Steps:"
                   "-----------------"
                   ""
                   "1. Phase Unwrapping: Resolves phase wraps in the multi-echo phase data"
                   "2. Background Field Removal: Separates local tissue phase from background field contributions"
                   "3. Susceptibility Inversion: Converts local field maps to susceptibility maps"
                   ""
                   ".. note::"
                   ""
                   "   SEPIA has its own working directory structure. QSMWorker temporarily switches to the"
                   "   SEPIA directory for processing and renames output files to ensure BIDS compatibility."
                   "   The SEPIA toolbox must be installed and configured."] % Description should be in ReStructuredText format
    needs       = ["ME4Dmag", "ME4Dphase", "brainmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns
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
        obj.bidsfilter.Chimap     = struct(modality = 'anat', ...
                                           echo     = [], ...
                                           part     = '', ...          % SEPIA outputs images with an appended "part-phase" substring
                                           suffix   = 'Chimap');
        obj.bidsfilter.fieldmap   = setfields(obj.bidsfilter.Chimap,                     suffix='fieldmap');
        obj.bidsfilter.unwrapped  = setfields(obj.bidsfilter.Chimap, part='phase',       suffix='unwrapped');
        obj.bidsfilter.localfmask = setfields(obj.bidsfilter.Chimap, label='localfield', suffix='mask');

        % Set the custom "Parent" config key set to "QSMWorker"
        obj.config.Parent = 'QSMWorker';
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed
        %
        % NB: This worker is a wrapper around the SEPIA toolbox and is therefore also leveraged by the
        %     R2starWorker to perform the actual work. The R2starWorker passes its own configuration to
        %     the QSMWorker with the custom "Parent" key set to "R2starWorker".

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Check if the parent is QSMWorker -> needs phase data, otherwise R2starWorker -> only needs magnitude data
        getQSM = strcmp(obj.config.Parent, 'QSMWorker');

        % Get preprocessed workitems from a colleague
        obj.workdir = replace(obj.workdir, "SEPIA", "QuIDBBIDS");       % SEPIA has it's own directory, temporarily put it back to what it was
        mask        = obj.ask_team('brainmask');
        magfiles    = obj.ask_team('ME4Dmag');
        if getQSM
            phasefiles = obj.ask_team('ME4Dphase');
        else
            phasefiles = repmat({''}, size(magfiles));
        end
        obj.workdir = replace(obj.workdir, "QuIDBBIDS", "SEPIA");

        % Check the received workitems
        if length(magfiles) ~= length(phasefiles)
            obj.logger.exception('%s got %d magnitude vs %d phase files', obj.name, length(magfiles), length(phasefiles))
        end
        if length(mask) ~= 1
            obj.logger.warning('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', mask{:}))
            entmag = bids.File(magfiles{1}).entities;
            for mask_ = mask
                entmask = bids.File(char(mask_)).entities;
                if  ( isfield(entmag, 'space') &&  isfield(entmask, 'space') && entmag.space == entmask.space) || ...
                    (~isfield(entmag, 'space') && ~isfield(entmask, 'space'))
                    obj.logger.verbose("Selecting mask: " + mask_)
                    mask = mask_;
                    break
                end
            end
        end

        % Process all acquisition protocols, runs and flip angles independently
        for n = 1:length(magfiles)

            % Make sure the magnitude and phase images belong together
            if getQSM && ~strcmp(magfiles{n}, replace(phasefiles{n}, '_part-phase_','_part-mag_'))
                obj.logger.exception("Magnitude and phase images do not match:\n%s\n%s", magfiles{n}, phasefiles{n})
            end

            % Create a SEPIA header file
            clear('input')
            input.nifti      = magfiles{n};                                         % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
            input.TEFileList = {spm_file(spm_file(magfiles{n}, 'ext',''), 'ext','.json')};   % If given, then SEPIA requires non-BIDS "ConversionSoftware" field from dcm2niix
            bfile            = obj.bfile_set(magfiles{n}, setfield(obj.bidsfilter.Chimap, suffix=''));  % Output basename; SEPIA adds suffixes of its own
            output           = extractBefore(bfile.path, bfile.extension);          % Output path. N.B: SEPIA will interpret the last part of the path as a file-prefix
            save_sepia_header(input, struct(TE=bfile.metadata.EchoTime), output)    % Override SEPIA's TE values with what the bfile says (-> added by file_merge)

            % Run the SEPIA workflow
            clear('input')
            input(1).name = phasefiles{n};  % For input().name see SEPIA GUI
            input(2).name = magfiles{n};
            input(3).name = '';
            input(4).name = [output '_header.mat'];
            obj.logger.info("--> Running SEPIA %s workflow for %s/%s", workitem, obj.subject.name, obj.subject.session)
            sepiaIO(input, output, char(mask), obj.config.QSMWorker)

            % Bluntly rename mask files to make them BIDS valid (bids-matlab fails on the original files)
            for srcfile = dir([erase(output, regexpPattern('_desc-.*')) '*_mask_*'])'           % SEPIA eats `desc-val` -> erase(output, ..)
                bname  = extractBefore(srcfile.name, '.');
                ext    = extractAfter(srcfile.name, bname);
                source = fullfile(srcfile.folder, srcfile.name);
                target = fullfile(srcfile.folder, [replace(bname, '_mask_', '_label-') '_mask' ext]);
                obj.logger.verbose('-> Renaming %s -> %s', source, target)
                movefile(source, target)
            end

            % Do the same for the ME4DUnwrapped files (SEPIA outputs them without a suffix, which is not BIDS valid)
            for srcfile = dir([erase(output, regexpPattern('_desc-.*')) '*-ME4DUnwrapped*'])'   % SEPIA eats `desc-val` -> erase(output, ..)
                source = fullfile(srcfile.folder, srcfile.name);
                target = fullfile(srcfile.folder, [replace(srcfile.name, 'Unwrapped', '_unwrapped')]);
                obj.logger.verbose('-> Renaming %s -> %s', source, target)
                movefile(source, target)
            end

        end
    end

end

end

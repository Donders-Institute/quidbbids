classdef QSMWorker < qb.workers.Worker
%QSMWORKER Runs QSM and R2-star workflows
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (GetAccess = public, SetAccess = protected)
    description = ["I am your SEPIA expert that can make shiny QSM and R2-star images for you"] % Description of the work that is done
    needs       = ["echos4Dmag", "echos4Dphase", "brainmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This method allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        % SEPIA should have a directory of its own (we cannot control it's output very well)
        obj.workdir = replace(obj.workdir, "QuIDBBIDS", "SEPIA");
        if ~isempty(obj.workdir) && ~isfolder(obj.workdir)
            bids.init(char(obj.workdir), 'is_derivative', true)
        end

        % Construct the bidsfilters
        obj.bidsfilter.R2starmap  = struct('modality', 'anat', ...
                                           'echo', [], ...
                                           'part', '', ...          % SEPIA outputs images with an appended "part-phase" substring
                                           'suffix', 'R2starmap');
        obj.bidsfilter.T2starmap  = setfield(obj.bidsfilter.R2starmap, 'suffix','T2starmap');
        obj.bidsfilter.S0map      = setfield(obj.bidsfilter.R2starmap, 'suffix','S0map');
        obj.bidsfilter.Chimap     = setfield(obj.bidsfilter.R2starmap, 'suffix','Chimap');
        obj.bidsfilter.fieldmap   = setfield(obj.bidsfilter.R2starmap, 'suffix','fieldmap');
        obj.bidsfilter.unwrapped  = setfield(setfield(obj.bidsfilter.R2starmap, 'part','phase'), 'suffix','unwrapped');
        obj.bidsfilter.localfmask = setfield(setfield(obj.bidsfilter.R2starmap, 'label','localfield'), 'suffix','mask');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get preprocessed workitems from a colleague
        obj.workdir = replace(obj.workdir, "SEPIA", "QuIDBBIDS");       % SEPIA has it's own directory, temporarily put it back to what it was
        magfiles    = obj.ask_team('echos4Dmag');
        phasefiles  = obj.ask_team('echos4Dphase');
        mask        = obj.ask_team('brainmask');
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
                    obj.logger.info("Selecting mask: " + mask_)
                    mask = mask_;
                    break
                end
            end
        end

        % Process all acquisition protocols, runs and flip angles independently
        for n = 1:length(magfiles)

            % Make sure the magnitude and phase images belong together
            if ~strcmp(magfiles{n}, replace(phasefiles{n}, '_part-phase_','_part-mag_'))
                obj.logger.exception("Magnitude and phase images do not match:\n%s\n%s", magfiles{n}, phasefiles{n})
            end

            % Create a SEPIA header file
            clear input
            input.nifti      = magfiles{n};                                         % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
            input.TEFileList = {spm_file(spm_file(magfiles{n}, 'ext',''), 'ext','.json')};                   % Could just be left empty??
            bfile            = obj.bfile_set(magfiles{n}, setfield(obj.bidsfilter.R2starmap, 'suffix',''));  % Output basename; SEPIA adds suffixes of its own
            output           = extractBefore(bfile.path, bfile.extension);          % Output path. N.B: SEPIA will interpret the last part of the path as a file-prefix
            save_sepia_header(input, struct('TE', bfile.metadata.EchoTime), output) % Override SEPIA's TE values with what the bfile says (-> added by spm_file_merge_gz)

            % Get the SEPIA parameters
            switch workitem
                case fieldnames(obj.config.QSMWorker)
                    param = obj.config.QSMWorker.(workitem);
                case {"T2starmap", "S0map"}
                    param = obj.config.QSMWorker.R2starmap;
                case {"Chimap", "unwrapped", "localfmask"}
                    param = obj.config.QSMWorker.QSM;
                otherwise
                    obj.logger.exception("%s cannot find the SEPIA parameters for: %s", obj.name, workitem)
            end

            % Run the SEPIA workflow
            clear input
            input(1).name = phasefiles{n};  % For input().name see SEPIA GUI
            input(2).name = magfiles{n};
            input(3).name = '';
            input(4).name = [output '_header.mat'];
            obj.logger.info("--> Running SEPIA %s workflow for %s/%s", workitem, obj.subject.name, obj.subject.session)
            sepiaIO(input, output, char(mask), param)

            % Bluntly rename mask files to make them BIDS valid (bids-matlab fails on the original files)
            for srcmask = dir([output '*_mask_*'])'
                bname  = extractBefore(srcmask.name, bfile.extension);
                source = fullfile(srcmask.folder, srcmask.name);
                target = fullfile(srcmask.folder, [replace(bname, '_mask_', '_label-') '_mask' bfile.extension]);
                obj.logger.verbose('Renaming %s -> %s', source, target)
                movefile(source, target)
            end

            % Add a JSON sidecar file for the S0map
            bids.util.jsonencode([output '_S0map.json'], bfile.metadata)

        end
    end

end

end

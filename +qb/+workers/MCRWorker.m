classdef MCRWorker < qb.workers.Worker
%MCRWORKER Runs MCR workflow

    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of MCRWorker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end

    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', setfield(bidsfilter.(workitem), 'run',1))`
    end
    
    
    methods

        function obj = MCRWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            %MCRWORKER Constructor for this concrete Worker class

            arguments
                BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
                subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
                config    (1,1) struct = struct()   % Configuration struct loaded from the config TOML file
                workdir   {mustBeTextScalar} = ''
                outputdir {mustBeTextScalar} = ''
                team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
                workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
            end

            % Call the abstract parent constructor
            obj@qb.workers.Worker(BIDS, subject, config, workdir, outputdir, team, workitems);

            % Make the abstract properties concrete
            obj.name        = "Jose";
            obj.description = ["If you don't want to stay single, I am sure I can fit you a Multi-Compartment Model";
                               "";
                               "Methods:"
                               "- "];
            obj.version     = "0.1.0";
            obj.needs       = ["echos4Dmag", "unwrapped", "FAmap_angle", "fieldmap", "localfmask"];
            obj.bidsfilter.MWFmap       = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', '', ...
                                                 'desc', 'gacelle', ...
                                                 'suffix', 'MWFmap');
            obj.bidsfilter.MW_M0map     = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', '', ...
                                                 'desc', 'gacelle', ...
                                                 'label', 'myelinwater', ...
                                                 'suffix', 'M0Map');
            obj.bidsfilter.MW_R2starmap = setfield(obj.bidsfilter.MW_M0map, 'suffix','R2starmap');
            obj.bidsfilter.FW_M0map     = setfield(obj.bidsfilter.MW_M0map, 'label','freewater');
            obj.bidsfilter.FW_T1map     = setfield(obj.bidsfilter.MW_M0map, 'suffix','T1map');
            obj.bidsfilter.FW_R2starmap = setfield(obj.bidsfilter.FW_M0map, 'suffix','R2starmap');
            obj.bidsfilter.FW_R1map     = setfield(obj.bidsfilter.FW_M0map, 'suffix','R1map');
            obj.bidsfilter.FMW_exrate   = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', '', ...
                                                 'desc', 'gacelle', ...
                                                 'label', 'free2myelinwater', ...
                                                 'suffix', 'ExchRate');
            obj.bidsfilter.FitMask      = struct('modality', 'anat', ...
                                                 'echo', [], ...
                                                 'part', '', ...
                                                 'desc', 'gacelle', ...
                                                 'label', 'fitted', ...
                                                 'suffix', 'mask');

            % Make the workitems (if requested)
            if strlength(workitems)                             % isempty(string('')) -> false
                for workitem = string(workitems)
                    obj.fetch(workitem);
                end
            end
        end

        function get_work_done(obj, workitem)
            %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

            arguments (Input)
                obj
                workitem {mustBeTextScalar, mustBeNonempty}
            end
            
            import qb.utils.spm_write_vol_gz

            % Check the input
            if ~ismember("fmap", fieldnames(obj.subject))
                return
            end

            % Get the workitems we need from a colleague
            echos4Dmag  = obj.ask_team('echos4Dmag');       % Multiple FA-images per run
            unwrapped   = obj.ask_team('unwrapped');        % Multiple FA-images per run
            fieldmap    = obj.ask_team('fieldmap');         % Multiple FA-images per run
            localfmask  = obj.ask_team('localfmask');       % Multiple FA-images per run
            FAmap_angle = obj.ask_team('FAmap_angle');      % Single image per run

            % Check the number of items we got: TODO: FIXME: multi-run acquisitions
            if numel(unique([length(echos4Dmag), length(unwrapped), length(fieldmap)])) > 1
                obj.logger.exception(sprintf('%s received an ambiguous number of echos4Dmag, unwrapped or fieldmaps:%s', obj.name, ...
                                     sprintf('\n%s', echos4Dmag{:}, unwrapped{:}, fieldmap{:})))
            end
            if length(echos4Dmag) < 2
                obj.logger.exception(sprintf('%s received data for only %d flip angles', obj.name, length(echos4Dmag)))
            end
            if length(FAmap_angle) ~= 1         % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
                obj.logger.exception(sprintf('%s expected only one FAmap file but got: %s', obj.name, sprintf('%s ', FAmap_angle{:})))
            end
            if length(localfmask) ~= length(echos4Dmag)
                obj.logger.exception('%s expected %d brainmasks but got:%s', obj.name, length(echos4Dmag), sprintf(' %s', localfmask{:}))
            end
            
            % Load the data + metadata
            V              = spm_vol(echos4Dmag{1});                    % For reading the 3D image dimensions
            dims           = [V(1).dim length(V) length(echos4Dmag)];
            img            = NaN(dims);
            unwrappedPhase = NaN(dims);
            totalField     = NaN(dims([1:3 5]));
            mask           = true;
            for n = 1:dims(5)
                bfile                     = bids.File(echos4Dmag{n});   % For reading metadata, parsing entities, etc
                img(:,:,:,:,n)            = spm_read_vols(spm_vol(echos4Dmag{n}));
                unwrappedPhase(:,:,:,:,n) = spm_read_vols(spm_vol(unwrapped{n}));
                totalField(:,:,:,n)       = spm_read_vols(spm_vol(fieldmap{n}));
                mask                      = spm_read_vols(spm_vol(localfmask{n})) & mask;
                FA(n)                     = bfile.metadata.FlipAngle;
            end
            B1 = spm_read_vols(spm_vol(char(FAmap_angle))) / obj.config.RelB1mapWorker.B1ScaleFactor;     % TODO: Replace with a worker that computes a relative B1-map
            TR = bfile.metadata.RepetitionTime;
            TE = bfile.metadata.EchoTime;

            % Obtain the initial estimation of the initial B1 phase
            img  = img .* exp(1i*unwrappedPhase);
            mask = mask & all(~isnan(img), [4 5]);
            pini = squeeze(unwrappedPhase(:,:,:,1,:)) - 2*pi*totalField .* TE(1);
            pini = polyfit3D_NthOrder(mean(pini(:,:,:,1:(end-1)), 4), mask, 6);

            % Estimate the MCR model
            extraData         = [];
            extraData.freqBKG = single(totalField / (obj.config.gyro * obj.config.MCRWorker.fixed_params.B0));  % in ppm
            extraData.pini    = single(pini);
            extraData.b1      = single(B1);
            objGPU            = gpuMCRMWI(TE, TR, FA, obj.config.MCRWorker.fixed_params);
            askadam_mcr       = objGPU.estimate(img, mask, extraData, obj.config.MCRWorker.fitting.GPU);  % TODO: Is single() really needed/desired?

            % Extract and save the output data
            V(1).dim = dims(1:3);
            spm_write_vol_gz(V(1), askadam_mcr.final.MWF * 100,	                      obj.bfile_set(bfile, obj.bidsfilter.MWFmap      ).path);
            spm_write_vol_gz(V(1), askadam_mcr.final.MWF .* askadam_mcr.final.S0,     obj.bfile_set(bfile, obj.bidsfilter.MW_M0map    ).path);
            spm_write_vol_gz(V(1), (1-askadam_mcr.final.MWF) .* askadam_mcr.final.S0, obj.bfile_set(bfile, obj.bidsfilter.FW_M0map    ).path);
            spm_write_vol_gz(V(1), askadam_mcr.final.R2sMW,                           obj.bfile_set(bfile, obj.bidsfilter.MW_R2starmap).path);
            spm_write_vol_gz(V(1), askadam_mcr.final.R2sIW,                           obj.bfile_set(bfile, obj.bidsfilter.FW_R2starmap).path);
            spm_write_vol_gz(V(1), 1 ./ askadam_mcr.final.R1IEW,                      obj.bfile_set(bfile, obj.bidsfilter.FW_T1map    ).path);
            spm_write_vol_gz(V(1), askadam_mcr.final.R1IEW,                           obj.bfile_set(bfile, obj.bidsfilter.FW_R1map    ).path);
            spm_write_vol_gz(V(1), askadam_mcr.final.kIEWM,                           obj.bfile_set(bfile, obj.bidsfilter.FMW_exrate  ).path);
            spm_write_vol_gz(V(1), mask,                                              obj.bfile_set(bfile, obj.bidsfilter.FitMask     ).path); % Check if this is correct
            % spm_write_vol_gz(V(1), extraData.pini + askadam_mcr.final.dpini,          obj.bfile_set(bfile, obj.bidsfilter.MW_M0map    ).path); '_Initialphase.nii.gz'])); TODO: Ask Jose if needed
        end

    end

end

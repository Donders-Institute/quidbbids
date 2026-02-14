classdef MCR_GPUWorker < qb.workers.Worker
%MCRWORKER Runs MCR workflow on the GPU
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (GetAccess = public, SetAccess = protected)
    description = ["If you don't want to stay single, I am sure I can fit you a Multi-Compartment Model";
                    "";
                   "Methods:"
                   "- Gacelle et al., MRM 2020 for R2-star mapping from multi-echo GRE data"]
    needs       = ["echos4Dmag", "unwrapped", "TB1map_GRE", "fieldmap", "localfmask"]           % List of workitems the worker needs. Workitems can contain regexp patterns
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This method allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % We can use the GPU
        obj.usesGPU = true;

        % Construct the bidsfilters
        obj.bidsfilter.FMW_exrate    = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'part', '', ...
                                              'desc', 'gacelle', ...
                                              'label', 'free2myelinwater', ...
                                              'suffix', 'ExchRate');
        obj.bidsfilter.FitMask       = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'part', '', ...
                                              'desc', 'gacelle', ...
                                              'label', 'fitted', ...
                                              'suffix', 'mask');
        obj.bidsfilter.MWFmap        = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'part', '', ...
                                              'desc', 'gacelle', ...
                                              'suffix', 'MWFmap');
        obj.bidsfilter.MW_M0map      = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'part', '', ...
                                              'desc', 'gacelle', ...
                                              'label', 'myelinwater', ...
                                              'suffix', 'M0Map');
        obj.bidsfilter.MW_R2starmap  = setfield(obj.bidsfilter.MW_M0map, 'suffix','R2starmap');
        obj.bidsfilter.FW_M0map      = setfield(obj.bidsfilter.MW_M0map, 'label','freewater');
        obj.bidsfilter.FW_T1map      = setfield(obj.bidsfilter.MW_M0map, 'suffix','T1map');
        obj.bidsfilter.FW_R1map      = setfield(obj.bidsfilter.FW_M0map, 'suffix','R1map');
        obj.bidsfilter.IAW_R2starmap = setfields(obj.bidsfilter.FW_M0map, 'label','axonalwater', 'suffix','R2starmap');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        import qb.utils.spm_write_vol_gz
        import qb.utils.spm_vol

        % Check the input
        if ~ismember("fmap", fieldnames(obj.subject))
            return
        end

        % Get the workitems we need from a colleague
        echos4Dmag = obj.ask_team('echos4Dmag');    % Multiple FA-images per run
        unwrapped  = obj.ask_team('unwrapped');     % Multiple FA-images per run
        fieldmap   = obj.ask_team('fieldmap');      % Multiple FA-images per run
        localfmask = obj.ask_team('localfmask');    % Multiple FA-images per run
        TB1map_GRE = obj.ask_team('TB1map_GRE');    % Single image per run

        % Check the number of items we got: TODO: FIXME: multi-run acquisitions
        if numel(unique([length(unwrapped), length(fieldmap)])) > 1
            obj.logger.exception('%s received an ambiguous number of echos4Dmag, unwrapped or fieldmaps:%s', obj.name, ...
                                    sprintf('\n%s', unwrapped{:}, fieldmap{:}))
        end
        if length(echos4Dmag) < 2
            obj.logger.exception('%s received data for only %d flip angles', obj.name, length(echos4Dmag))
        end
        if length(TB1map_GRE) ~= 1         % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
            obj.logger.exception('%s expected only one B1map file but got: %s', obj.name, sprintf('%s ', TB1map_GRE{:}))
        end
        if length(localfmask) ~= length(echos4Dmag)
            obj.logger.exception('%s expected %d brainmasks but got:%s', obj.name, length(echos4Dmag), sprintf(' %s', localfmask{:}))
        end

        % Load the data + metadata
        V              = spm_vol(echos4Dmag{1});                    % For reading the 3D image dimensions
        dims           = [V(1).dim length(V) length(echos4Dmag)];   % Dimensions: [x,y,z,TE,FA]
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
            FA(n)                     = bfile.metadata.FlipAngle;   %#ok<AGROW>
        end
        B1 = spm_read_vols(spm_vol(char(TB1map_GRE)));
        TR = bfile.metadata.RepetitionTime;
        TE = bfile.metadata.EchoTime;

        % Obtain the initial estimation of the initial B1 phase
        img  = img .* exp(1i*unwrappedPhase);
        mask = mask & all(~isnan(img), [4 5]);
        pini = squeeze(unwrappedPhase(:,:,:,1,:)) - 2*pi*totalField .* TE(1);
        pini = polyfit3D_NthOrder(mean(pini(:,:,:,1:(end-1)), 4), mask, 6);

        % Construct the fixed parameters and extra data for the MCR model
        fixed_params        = obj.config.MCR_GPUWorker.fixed_params;
        fixed_params.x_i    = obj.config.General.x_i;
        fixed_params.x_a    = obj.config.General.x_a;
        fixed_params.E      = obj.config.General.E;
        fixed_params.rho_mw = obj.config.General.kappa_mw / obj.config.General.kappa_iew;
        fixed_params.t1_mw  = obj.config.General.t1_mw;
        fixed_params.B0dir  = obj.config.General.B0dir;
        fixed_params.b0     = bfile.metadata.MagneticFieldStrength;
        extraData           = [];
        extraData.freqBKG   = single(totalField / (obj.config.General.gyro * fixed_params.B0));  % in ppm. TODO: Is single() really needed/desired?
        extraData.pini      = single(pini);
        extraData.b1        = single(B1);

        % Estimate the MCR model
        objGPU      = gpuMCRMWI(TE, TR, FA, fixed_params);
        askadam_mcr = objGPU.estimate(img, mask, extraData, obj.config.MCR_GPUWorker.fitting);

        % Extract and save the output data
        V(1).dim = dims(1:3);
        spm_write_vol_gz(V(1), askadam_mcr.final.MWF * 100,                       obj.bfile_set(bfile, obj.bidsfilter.MWFmap       ).path);  % TODO: Ask Jose: Multiply by 100 to get percentage?
        spm_write_vol_gz(V(1), askadam_mcr.final.MWF .* askadam_mcr.final.S0,     obj.bfile_set(bfile, obj.bidsfilter.MW_M0map     ).path);
        spm_write_vol_gz(V(1), (1-askadam_mcr.final.MWF) .* askadam_mcr.final.S0, obj.bfile_set(bfile, obj.bidsfilter.FW_M0map     ).path);
        spm_write_vol_gz(V(1), askadam_mcr.final.R2sMW,                           obj.bfile_set(bfile, obj.bidsfilter.MW_R2starmap ).path);
        spm_write_vol_gz(V(1), askadam_mcr.final.R2sIW,                           obj.bfile_set(bfile, obj.bidsfilter.IAW_R2starmap).path);
        spm_write_vol_gz(V(1), 1 ./ askadam_mcr.final.R1IEW,                      obj.bfile_set(bfile, obj.bidsfilter.FW_T1map     ).path);
        spm_write_vol_gz(V(1), askadam_mcr.final.R1IEW,                           obj.bfile_set(bfile, obj.bidsfilter.FW_R1map     ).path);
        spm_write_vol_gz(V(1), askadam_mcr.final.kIEWM,                           obj.bfile_set(bfile, obj.bidsfilter.FMW_exrate   ).path);
        spm_write_vol_gz(V(1), mask,                                              obj.bfile_set(bfile, obj.bidsfilter.FitMask      ).path); % Check if this is correct
    end

end

end

classdef (Sealed) MCR_GPUWorker < qb.workers.Worker
%MCRWORKER Runs MCR workflow on the GPU
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["GPU-accelerated Multi-Compartment Relaxometry (MCR) worker for efficient myelin"
                   "water imaging (MWI) analysis."
                   ""
                   "MCR_GPUWorker implements the MCR framework on GPU hardware, combining complex"
                   "multi-echo GRE data (VFA or MPM) with coregistered B1 transmit field maps to estimate"
                   "myelin water fraction (MWF) and other quantitative microstructural parameters."
                   "Protocols with a variable TR and/or a variable number of echoes across flip angles"
                   "are fitted with gpuMCRMWI_VFAVTR (https://github.com/samuelmelke/vTR-qMRI)."
                   ""
                   "Theoretical Framework:"
                   "----------------------"
                   ""
                   "The MCR model is based on the quantitative framework described in:"
                   "Chan et al., NeuroImage, 2020, https://doi.org/10.1016/j.neuroimage.2020.117159"
                   ""
                   "GPU implementation is provided by the Gacelle toolbox:"
                   "https://gacelle.readthedocs.io/en/latest/supported_models/MCRMWI.html"
                   ""
                   "Reference:"
                   "----------"
                   "Gacelle et al., Imaging Neuroscience 2026 (under review), https://arxiv.org/abs/2511.22094"
                   ""
                   ".. note::"
                   ""
                   "   MCR_GPUWorker provides significant speed improvements over MCRWorker,"
                   "   particularly for high-resolution datasets or when processing multiple subjects."
                   "   Requires GPU hardware with CUDA support."
                   ""
                   "   MCR_GPUWorker supports both standard MCR-MWI and DI-MWI variants. When diffusion priors"
                   "   (DWItheta, DWIicvf, DWIff) are available from DWIprepWorker, the DI-MWI model incorporates"
                   "   fiber orientation and compartment fraction information to improve parameter estimation"
                   "   specificity."]   % Description should be in ReStructuredText format
    needs       = ["ME4Dmag", "unwrapped", "TB1map_GRE", "fieldmap", "localfmask", "DWItheta", "DWIicvf", "DWIff"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = true
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.MWFmap        = struct(modality = 'anat', ...
                                              echo     = [], ...
                                              flip     = [], ...
                                              part     = '', ...
                                              desc     = 'gacelle', ...
                                              suffix   = 'MWFmap');
        obj.bidsfilter.FMW_exrate    = setfields(obj.bidsfilter.MWFmap,       label='free2myelinwater', suffix='ExchRate');
        obj.bidsfilter.FitMask       = setfields(obj.bidsfilter.MWFmap,       label='fitted',           suffix='mask');
        obj.bidsfilter.MW_M0map      = setfields(obj.bidsfilter.MWFmap,       label='myelinwater',      suffix='M0Map');
        obj.bidsfilter.MW_R2starmap  = setfields(obj.bidsfilter.MW_M0map,                               suffix='R2starmap');
        obj.bidsfilter.FW_M0map      = setfields(obj.bidsfilter.MW_M0map,     label='freewater');
        obj.bidsfilter.FW_T1map      = setfields(obj.bidsfilter.FW_M0map,                               suffix='T1map');
        obj.bidsfilter.FW_R1map      = setfields(obj.bidsfilter.FW_M0map,                               suffix='R1map');
        obj.bidsfilter.IAW_R2starmap = setfields(obj.bidsfilter.MW_R2starmap, label='axonalwater');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        import qb.utils.write_vol
        import qb.utils.spm_vol

        % Check the input
        if ~ismember("fmap", fieldnames(obj.subject))
            return
        end

        % Get the workitems we need from a colleague. TODO: FIXME: multi-run acquisitions
        ME4Dmag    = obj.ask_team('ME4Dmag', -2);           % Must have at least 2 FA-images per run
        unwrapped  = obj.ask_team('unwrapped', numel(ME4Dmag));
        fieldmap   = obj.ask_team('fieldmap', numel(ME4Dmag));
        localfmask = obj.ask_team('localfmask', numel(ME4Dmag));
        TB1map_GRE = obj.ask_team('TB1map_GRE', 1);         % Single image per run. TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
        DWItheta   = obj.ask_team('DWItheta', []);          % Optional, may be empty if no diffusion data is available
        DWIicvf    = obj.ask_team('DWIicvf', []);           % Optional, may be empty if no diffusion data is available
        DWIff      = obj.ask_team('DWIff', []);             % Optional, may be empty if no diffusion data is available

        % Read the protocol of each acquisition. This is done before allocating because acquisitions may differ in TR and in the number of echoes
        for n = 1:length(ME4Dmag)
            bfile = bids.File(ME4Dmag{n});                  % For reading metadata, parsing entities, etc
            FA(n) = bfile.metadata.FlipAngle;               %#ok<AGROW>
            TR(n) = bfile.metadata.RepetitionTime;          %#ok<AGROW>
            TE{n} = bfile.metadata.EchoTime(:);             %#ok<AGROW>
        end
        nTE     = cellfun(@numel, TE);
        TErange = [cumsum(nTE(:)) - nTE(:) + 1, cumsum(nTE(:))];    % First/last index of each acquisition along the echo dimension
        isVTR   = ~all(abs(TR - TR(1)) < 1e-6*TR(1)) || ...         % Different repetition times
                  ~all(nTE == nTE(1))                || ...         % Different numbers of echoes
                  ~all(cellfun(@(t) isequal(t, TE{1}), TE));        % Different echo times

        % Load the data + metadata
        V              = spm_vol(ME4Dmag{1});                       % For reading the 3D image dimensions
        dims           = [V(1).dim sum(nTE)];                       % Dimensions: [x,y,z,echo], all acquisitions concatenated
        img            = single(NaN(dims));
        unwrappedPhase = single(NaN(dims));
        totalField     = single(NaN([dims(1:3) length(ME4Dmag)]));  % Dimensions: [x,y,z,FA]
        mask           = true;
        for n = 1:length(ME4Dmag)
            idx                       = TErange(n,1):TErange(n,2);
            img(:,:,:,idx)            = spm_read_vols(spm_vol(ME4Dmag{n}));
            unwrappedPhase(:,:,:,idx) = spm_read_vols(spm_vol(unwrapped{n}));
            totalField(:,:,:,n)       = spm_read_vols(spm_vol(fieldmap{n}));
            mask                      = spm_read_vols(spm_vol(localfmask{n})) & mask;
        end
        B1 = spm_read_vols(spm_vol(char(TB1map_GRE)));

        % Obtain the initial estimation of the initial B1 phase (NB: img is still 4D here, i.e. with all acquisitions concatenated)
        img  = img .* exp(1i*unwrappedPhase);
        mask = mask & all(~isnan(img), 4);
        TE1  = reshape(cellfun(@(te) te(1), TE), 1, 1, 1, []);                  % First echo time of each acquisition
        pini = unwrappedPhase(:,:,:,TErange(:,1)) - 2*pi*totalField .* TE1;     % Dimensions: [x,y,z,FA]
        pini = polyfit3D_NthOrder(double(mean(pini(:,:,:,1:end-1), 4)), mask, 6);

        % Construct the fixed parameters and extra data for the MCR model
        fixed_params      = obj.config.MCR_GPUWorker.fixed_params;
        fixed_params.B0   = bfile.metadata.MagneticFieldStrength;
        extraData         = [];
        extraData.freqBKG = totalField / (42.57747892 * fixed_params.B0);       % 42.57747892 -> Gyromagnetic ratio in ppm
        extraData.pini    = pini;
        extraData.b1      = B1;

        % Setup the MCR model object for GPU fitting
        fitting = obj.config.MCR_GPUWorker.fitting;
        if isVTR                    % Variable-TR protocols need the echo index ranges and cannot use the EPG-X networks
            if fitting.isEPG        % We need to override isEPG for VTR (and not leak a mutated obj.config)
                obj.logger.warning('%s: the EPG-X networks assume a single TR for all flip angles, using the Bloch-McConnell solution instead', obj.name)
                fitting.isEPG = false;
            end
            obj.logger.info('%s detected a variable protocol (TR = [%s] ms), using gpuMCRMWI_VFAVTR', obj.name, num2str(TR*1e3, ' %.1f'))
            extraData.te_indexrange = TErange;
            objGPU = gpuMCRMWI_VFAVTR(TE, TR, FA, fixed_params);
        else
            img    = reshape(img, [dims(1:3) nTE(1) length(ME4Dmag)]);  % Back to [x,y,z,TE,FA] for gpuMCRMWI
            dims   = size(img);
            objGPU = gpuMCRMWI(TE{1}, TR(1), FA, fixed_params);
        end

        % Add the diffusion priors for the DI-MWI model if available. NB: unlike MCRWorker (mwi toolbox), where algoPara.DIMWI.* = true means
        % "use the DWI prior", gacelle uses the opposite polarity: fitting.DIMWI.isFit* = true means the parameter is fitted (prior NOT used)
        if isempty(DWItheta) || isempty(DWIicvf) || isempty(DWIff)
            obj.logger.info('%s: estimating the MCR model without diffusion priors', obj.name)
            fitting.DIMWI.isFitIWF    = true;      % Fit the parameters instead of using the DWI-derived maps (extraData) as priors
            fitting.DIMWI.isFitFreqMW = true;
            fitting.DIMWI.isFitFreqIW = true;
            fitting.DIMWI.isFitR2sEW  = true;
        else
            obj.logger.info('%s: estimating the DI-MWI-MCR model', obj.name)
            extraData.theta = spm_read_vols(spm_vol(DWItheta{1}));
            extraData.IWF   = spm_read_vols(spm_vol(DWIicvf{1}));
            extraData.ff    = spm_read_vols(spm_vol(DWIff{1}));
        end

        % Estimate the MCR model (variable-TR protocols need the vTR-qMRI implementation)
        askadam_mcr = objGPU.estimate(img, mask, extraData, fitting);

        % Extract and save the output data
        V(1).dim = dims(1:3);
        write_vol(V(1), askadam_mcr.final.MWF,                             obj.bfile_set(bfile, obj.bidsfilter.MWFmap       ));
        write_vol(V(1), askadam_mcr.final.MWF .* askadam_mcr.final.S0,     obj.bfile_set(bfile, obj.bidsfilter.MW_M0map     ));
        write_vol(V(1), (1-askadam_mcr.final.MWF) .* askadam_mcr.final.S0, obj.bfile_set(bfile, obj.bidsfilter.FW_M0map     ));
        write_vol(V(1), askadam_mcr.final.R2sMW,                           obj.bfile_set(bfile, obj.bidsfilter.MW_R2starmap ));
        write_vol(V(1), askadam_mcr.final.R2sIW,                           obj.bfile_set(bfile, obj.bidsfilter.IAW_R2starmap));
        write_vol(V(1), 1 ./ askadam_mcr.final.R1IEW,                      obj.bfile_set(bfile, obj.bidsfilter.FW_T1map     ));
        write_vol(V(1), askadam_mcr.final.R1IEW,                           obj.bfile_set(bfile, obj.bidsfilter.FW_R1map     ));
        write_vol(V(1), askadam_mcr.final.kIEWM,                           obj.bfile_set(bfile, obj.bidsfilter.FMW_exrate   ));
        write_vol(V(1), askadam_mcr.mask,                                  obj.bfile_set(bfile, obj.bidsfilter.FitMask      ));
    end

end

end

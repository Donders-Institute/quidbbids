classdef (Sealed) SCRWorker < qb.workers.Worker
%SCRWORKER Runs SCR workflow
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["Single Compartment Relaxometry (SCR) worker for combined relaxometry and susceptibility analysis."
                   ""
                   "SCRWorker jointly estimates R1, R2* and M0 from multi-echo variable flip angle (VFA) GRE data, and"
                   "combines separately computed Quantitative Susceptibility Mapping (QSM) outputs into a single"
                   "susceptibility map. SCR assumes a single tissue compartment, suitable for applications where"
                   "multi-compartment modeling is not required or when computational efficiency is prioritized."
                   ""
                   "Methods:"
                   "--------"
                   ""
                   "1. Joint R1, R2* and M0 Mapping:"
                   "   Fits the spoiled GRE signal equation to all echoes of all flip angles simultaneously, using a"
                   "   Pade approximation of the T1 recovery term to obtain a closed-form estimate, followed by"
                   "   Gauss-Newton refinement on the exact signal equation. Transmit field (B1+) inhomogeneity is"
                   "   accounted for. The fit runs on the CPU and supports variable flip angles as well as variable"
                   "   repetition and echo times."
                   ""
                   "2. Chi Map Averaging:"
                   "   Computes the weighted mean of the susceptibility (Chi) maps across flip angles. The weighting"
                   "   uses S0^2 to emphasize voxels with higher signal intensity."
                   ""
                   ".. note::"
                   ""
                   "   The SCR model is appropriate for tissues with relatively homogeneous microstructure or when"
                   "   the primary goal is to obtain average parameter values rather than compartment-specific estimates."
                   "   For myelin water imaging, consider using MCRWorker or MCR_GPUWorker instead."]   % Description should be in ReStructuredText format
    needs       = ["ME4Dmag", "TB1map_GRE", "brainmask", "S0map", "Chimap", "localfmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.R2starmap_SCR = struct(modality = 'anat', ...
                                              echo     = [], ...
                                              flip     = [], ...      % The fit combines all flip angles
                                              part     = '', ...
                                              desc     = 'SCR', ...
                                              suffix   = 'R2starmap');
        obj.bidsfilter.R1map_SCR     = setfield(obj.bidsfilter.R2starmap_SCR, suffix='R1map');
        obj.bidsfilter.M0map_SCR     = setfield(obj.bidsfilter.R2starmap_SCR, suffix='M0map');
        obj.bidsfilter.meanChimap    = setfield(obj.bidsfilter.R2starmap_SCR, suffix='Chimap');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        switch workitem
            case {'R1map_SCR', 'M0map_SCR', 'R2starmap_SCR'}
                obj.fit_relaxometry()
            case 'meanChimap'
                obj.average_chimap()
            otherwise
                obj.logger.exception('%s does not know how to make a %s workitem', obj.name, workitem)
        end
    end

end


methods (Access = private)

    function fit_relaxometry(obj)
        %FIT_RELAXOMETRY Jointly estimates R1, R2* and M0 from the multi-echo VFA data

        import qb.utils.write_vol
        import qb.utils.spm_vol

        % Check the input (we need a B1map to correct the flip angles)
        if ~ismember("fmap", fieldnames(obj.subject))
            return
        end

        % Get the workitems we need from a colleague
        ME4Dmag    = obj.ask_team('ME4Dmag');       % One multi-echo 4D file per flip angle
        TB1map_GRE = obj.ask_team('TB1map_GRE');    % Single image per run
        brainmask  = obj.ask_team('brainmask');     % Single image per run

        % Check the number of items we got. TODO: FIXME: multi-run acquisitions
        if length(ME4Dmag) < 2
            obj.logger.exception('%s received data for only %d flip angle(s)', obj.name, length(ME4Dmag))
        end
        if length(TB1map_GRE) ~= 1      % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
            obj.logger.exception('%s expected only one B1map file but got:%s', obj.name, sprintf(' %s', TB1map_GRE{:}))
        end
        if length(brainmask) ~= 1       % TODO: FIXME
            obj.logger.exception('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', brainmask{:}))
        end

        % Load the data + the protocol of each acquisition (= flip angle). NB: The echo trains are
        % concatenated along the 4th dimension, so the TE/TR do not have to be the same for each acquisition
        V   = spm_vol(ME4Dmag{1});
        img = [];
        TE  = cell(1, length(ME4Dmag));
        TR  = NaN(1, length(ME4Dmag));
        FA  = NaN(1, length(ME4Dmag));
        for n = 1:length(ME4Dmag)
            bfile = bids.File(ME4Dmag{n});              % For reading metadata, parsing entities, etc
            TE{n} = bfile.metadata.EchoTime(:)';        % [s]
            TR(n) = bfile.metadata.RepetitionTime;      % [s]
            FA(n) = bfile.metadata.FlipAngle;           % [deg]
            img   = cat(4, img, single(spm_read_vols(spm_vol(ME4Dmag{n}))));
        end
        mask = spm_read_vols(spm_vol(char(brainmask))) > 0 & all(isfinite(img), 4);
        B1   = spm_read_vols(spm_vol(char(TB1map_GRE)));

        % Jointly estimate R1, R2* and M0 from all echoes of all flip angles at once
        solver         = padeJointR1R2starMapping(TE, TR, FA);
        solver.nNewton = obj.config.SCRWorker.nNewton;
        fit            = solver.estimate(img, mask, B1);

        % Set the non-fitted (NaN) voxels to 0
        for map = ["R1" "R2star" "M0"]
            fit.(map)(~isfinite(fit.(map))) = 0;
        end

        % Save the SCR output maps
        write_vol(V(1), fit.R1,     obj.bfile_set(ME4Dmag{1}, obj.bidsfilter.R1map_SCR    ));
        write_vol(V(1), fit.M0,     obj.bfile_set(ME4Dmag{1}, obj.bidsfilter.M0map_SCR    ));
        write_vol(V(1), fit.R2star, obj.bfile_set(ME4Dmag{1}, obj.bidsfilter.R2starmap_SCR));
    end


    function average_chimap(obj)
        %AVERAGE_CHIMAP Computes the S0^2-weighted mean of the QSM Chi-maps over the flip angles

        import qb.utils.write_vol
        import qb.utils.spm_vol

        % Get the QSM workitems we need from a colleague (instead of just getting the files, use the filters to get the right runs ourselves)
        [~, S0filter]   = obj.ask_team('S0map');
        [~, Chifilter]  = obj.ask_team('Chimap');
        [~, maskfilter] = obj.ask_team('localfmask');

        % Index the (special) SEPIA workdir layout (only for obj.subject)
        BIDSWS = obj.BIDS_ses(replace(obj.workdir, "QuIDBBIDS", "SEPIA"));

        % Process all runs independently
        for run = obj.query_ses(BIDSWS, 'runs', S0filter)     % NB: Assumes all workitems have the same number of runs

            S0data   = obj.query_ses(BIDSWS, 'data', S0filter,   run=char(run));
            Chidata  = obj.query_ses(BIDSWS, 'data', Chifilter,  run=char(run));
            maskdata = obj.query_ses(BIDSWS, 'data', maskfilter, run=char(run));

            % Check the queried workitems
            if numel(unique([length(S0data), length(Chidata), length(maskdata)])) > 1
                obj.logger.exception('%s received an ambiguous number of S0maps, Chimaps or localfmasks:%s', obj.name, ...
                                        sprintf('\n%s', S0data{:}, Chidata{:}, maskdata{:}))
            end
            if length(S0data) < 2
                obj.logger.exception('%s received data for only %d flip angle(s)', obj.name, length(S0data))
            end

            % Read the QSM images (4th dimension = flip angle)
            V    = spm_vol(S0data{1});                  % Get generic metadata (from any QSM output image)
            S0   = NaN([V.dim(1:3) length(S0data)]);
            Chi  = S0;
            mask = true;
            for n = 1:length(S0data)
                S0(:,:,:,n)  = spm_read_vols(spm_vol(S0data{n}));
                Chi(:,:,:,n) = spm_read_vols(spm_vol(Chidata{n}));          % NB: Assumes the order of Chidata is the same as for S0data
                mask         = spm_read_vols(spm_vol(maskdata{n})) & mask;  % Idem
            end

            % Compute and save the weighted mean of the Chi maps
            Chimean = sum(S0.^2 .* Chi, 4) ./ sum(S0.^2, 4);
            write_vol(V, Chimean.*mask, obj.bfile_set(S0data{1}, obj.bidsfilter.meanChimap));

        end
    end

end

end

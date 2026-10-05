classdef (Sealed) meanQSMWorker < qb.workers.Worker
%meanQSMWorker Runs SCR workflow
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["mean QSM worker ."
                   ""
                   "meanQSMWorker combines separately computed Quantitative Susceptibility Mapping (QSM) outputs into a single"
                   "susceptibility maptaking account the SNR of each acquisition."
                   ""
                   "Methods:"
                   "--------"
                   ""
                   "Chi Map Averaging:"
                   "   Computes the weighted mean of the susceptibility (Chi) maps across flip angles. The weighting"
                   "   uses S0^2 to emphasize voxels with higher signal intensity."
                   ""
                   ".. note::"
                   ""
                   "   The SCR model is appropriate for tissues with relatively homogeneous microstructure or when"
                   "   the primary goal is to obtain average parameter values rather than compartment-specific estimates."
                   "   For myelin water imaging, consider using MCRWorker or MCR_GPUWorker instead."]   % Description should be in ReStructuredText format
    needs       = ["S0map", "Chimap", "localfmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.meanChimap = struct(modality = 'anat', ...
                                           echo     = [], ...
                                           flip     = [], ...      % The fit combines all flip angles
                                           part     = '', ...
                                           desc     = 'SCR', ...
                                           suffix   = 'Chimap');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        obj.average_chimap()
    end

end


methods (Access = private)

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

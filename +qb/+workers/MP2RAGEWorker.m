classdef MP2RAGEWorker < qb.workers.Worker
%MP2RAGEWorker Performs preprocessing to produce workitems that can be used by other workers
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["I'm an MP2RAGE worker and create M0 and R1 maps, but only if you have MP2RAGE and B1 map data!";
                   "Computations are based on a dictionary matching approach described in the supplemental material";
                   "of the paper Chan et al, Imaging Neuroscience, 2025 https://doi.org/10.1162/imag_a_00456.";
                   "";
                   "This method, when compared to the original implementation described by Marques et al, PLOSone, 2013";
                   "https://doi.org/10.1371/journal.pone.0069294 has significantly better performance for long T1 values";
                   "";
                   "Considerations:";
                   "- Be careful at defining the configuration parameters `NumberShots` and (to a smaller extent) `EchoSpacing`";
                   "";
                   "The code is based on: https://github.com/JosePMarques/MP2RAGE-related-scripts/"]
    needs       = ["TB1map_anat", "TB1map_angle"]   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.rawUNIT1    = setfields(obj.config.General.BIDS.include, modality='anat', suffix='UNIT1');
        obj.bidsfilter.rawINV1     = setfields(obj.bidsfilter.rawUNIT1, inv=1, suffix='MP2RAGE');
        obj.bidsfilter.rawINV2     = setfields(obj.bidsfilter.rawINV1,  inv=2);
        obj.bidsfilter.R1map       = struct(modality = 'anat', ...
                                            part     = '', ...
                                            space    = 'MP2RAGE', ...
                                            desc     = 'UNIT1corrected', ...
                                            suffix   = 'R1map');
        obj.bidsfilter.M0map       = setfield(obj.bidsfilter.R1map, suffix='M0map');
        obj.bidsfilter.MP2RAGE_T1w = setfield(obj.bidsfilter.R1map, suffix='T1w');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        import qb.utils.write_vol
        import qb.utils.spm_vol

        % Get the B1 images from the team
        B1famp = obj.ask_team('TB1map_angle');
        B1anat = obj.ask_team('TB1map_anat');
        if length(B1famp) > 1 || length(B1anat) > 1
            obj.logger.error("Expected one TB1map_angle and one TB1map_anat file, but got %d and %d files", length(B1famp), length(B1anat))
        end

        % Process all runs independently. TODO: think about multi-echo?
        for run = obj.query_ses(obj.BIDS, 'runs', obj.bidsfilter.rawUNIT1)

            % Load the raw MP2RAGE headers & data (https://bids-specification.readthedocs.io/en/stable/appendices/qmri.html#unit1-images)
            UNIT1 = obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawUNIT1, run=char(run));      % bids-matlab doesn't understand this: part='(mag)?'
            INV1  = obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawINV1,  run=char(run));      % idem
            INV2  = obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawINV2,  run=char(run));      % idem
            if length(UNIT1) ~= 1 || length(INV1) ~= 1 || length(INV2) ~= 1
                obj.logger.error("Expected one UNIT1, INV1 and INV2 file for run %s, but got %d, %d and %d files", char(run), length(UNIT1), length(INV1), length(INV2))
            end
            UNIhdr  = spm_vol(char(UNIT1));
            INV1hdr = spm_vol(char(INV1));
            INV2hdr = spm_vol(char(INV2));
            UNIimg  = spm_read_vols(UNIhdr);
            INV2img = spm_read_vols(INV2hdr);

            % Construct the (legacy) MP2RAGE metadata struct
            MP2RAGE = obj.getMP2RAGE(INV1, INV2, obj.config.MP2RAGEWorker);

            % Realign & reslice the B1 reference image to the INV2 image
            VB1a  = spm_vol(char(B1anat));
            x     = spm_coreg(INV2hdr, VB1a, struct(cost_fun='nmi'));
            VB1f  = spm_vol(char(B1famp));
            T     = VB1f.mat \ spm_matrix(x) * INV2hdr.mat;     % T = Mapping from voxels in INV2Ref to voxel coordinates in B1famp
            B1img = NaN(INV2hdr.dim);
            for z = 1:INV2hdr.dim(3)                           % Reslice the B1famp volume at the coordinates of each coregistered transverse slice of INV2Ref
                B1img(:,:,z) = spm_slice_vol(VB1f, T * spm_matrix([0 0 z]), INV2hdr.dim(1:2), 1);   % Using trilinear interpolation
            end
            B1img(isnan(B1img)) = 0;                           % Set voxels outside the FOV to zero

            % Estimate the UNIT1 image correction and the M0- and R1-maps
            if obj.config.MP2RAGEWorker.Fingerprint == false

                % Compute the M0- and R1-map
                [~, UNIcorr]      = qb.MP2RAGE.correctT1B1_TFL(B1img, UNIimg, [], MP2RAGE);
                [~, M0map, R1map] = qb.MP2RAGE.estimateT1M0(UNIcorr, INV2img, MP2RAGE);

            else

                INV1img               = qb.MP2RAGE.correctINV1INV2(spm_read_vols(INV1hdr), INV2img, UNIimg, 0);
                [~, M0map, R1map]     = qb.MP2RAGE.dictmatching(MP2RAGE, single(real(INV1img)), single(real(INV2img)), single(real(B1img)), [0.002, 0.005], 1, B1img ~= 0);
                [Intensity, T1vector] = qb.MP2RAGE.lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NumberShots, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
                UNIcorr = reshape(interp1(T1vector, Intensity, 1./R1map(:)), size(R1map));
                UNIcorr(isnan(UNIcorr)) = -0.5;
                UNIcorr = qb.MP2RAGE.unscaleUNI(UNIcorr);      % unscale UNIT1 back to 0-4095 range

            end

            % Perform the unbiased B1-map estimation
            if obj.config.MP2RAGEWorker.B1correctM0 ~= 0
                M0map = M0map ./ flip(B1img, obj.config.MP2RAGEWorker.B1correctM0);
            end

            % Data is only valid where B1 was mapped
            R1map(B1img == 0) = 0;
            M0map(B1img == 0) = 0;

            % Save the R1-map
            bfile                              = obj.bfile_set(UNIT1, obj.bidsfilter.R1map);
            bfile.metadata.Sources             = {['bids::' bfile.bids_path '/' bfile.filename]};
            bfile.metadata.InversionEfficiency = MP2RAGE.InvEff;
            bfile.metadata.NumberShots         = MP2RAGE.NumberShots;
            bfile.metadata.EchoSpacing         = MP2RAGE.EchoSpacing;
            write_vol(UNIhdr, R1map, bfile);

            % Save the M0-map
            bfile = obj.bfile_set(bfile, obj.bidsfilter.M0map);
            write_vol(UNIhdr, M0map, bfile);

            % Save the corrected UNIT1
            bfile = obj.bfile_set(bfile, obj.bidsfilter.MP2RAGE_T1w);
            write_vol(UNIhdr, UNIcorr, bfile);

        end
    end

end

methods (Access = private)

    function MP2RAGE = getMP2RAGE(obj, INV1, INV2, config)
        %GETMP2RAGE Extracts the MP2RAGE parameters from the INV1 and INV2 metadata and constructs the (legacy) MP2RAGE metadata struct
        %
        % inv1               - The INV1 image
        % inv2               - The INV2 image
        % config.InvEff      - Inversion efficiency of the adiabatic inversion pulse
        % config.EchoSpacing - The RepetitionTimeExcitation value in secs that typically is not given on the json file. Default: twice the echo time
        % config.NumberShots - The number of shots (slices) in the inner loop (inversion segment), the json file doesn't usually accommodate this
        
        % Extract the relevant MP2RAGE parameters from the BIDS metadata
        inv1                = bids.File(char(INV1)).metadata;
        inv2                = bids.File(char(INV2)).metadata;
        MP2RAGE.TR          = inv1.RepetitionTime;                          % MP2RAGE TR in seconds
        MP2RAGE.TIs         = [inv1.InversionTime inv2.InversionTime];      % Inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
        MP2RAGE.FlipDegrees = [inv1.FlipAngle     inv2.FlipAngle];          % Flip angle of the two readouts in degrees
        MP2RAGE.InvEff      = config.InvEff;                                % Inversion efficiency of the adiabatic inversion pulse
        MP2RAGE.NumberShots = config.NumberShots;
        if isempty(config.EchoSpacing)
            if isfield(inv1, 'RepetitionTimeExcitation')
                config.EchoSpacing = inv1.RepetitionTimeExcitation;         % TR of the GRE readout in seconds
            else
                config.EchoSpacing = 2 * inv1.EchoTime;                     % 2*EchoTime can be used as a surrogate
            end
            obj.logger.verbose(['Extracted EchoSpacing: ' num2str(config.EchoSpacing)])
        end
        MP2RAGE.EchoSpacing = config.EchoSpacing;
    end

end

end

classdef MP2RAGEWorker < qb.workers.Worker
    %MP2RAGEWorker Performs preprocessing to produce workitems that can be used by other workers
    %
    % See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


    properties (GetAccess = public, SetAccess = protected)
        name        % Name of the worker
        description % Description of the work that is done
        version     % The version of MP2RAGEWorker
        needs       % List of workitems the worker needs. Workitems can contain regexp patterns
    end


    properties
        bidsfilter  % BIDS modality filters that can be used for querying the produced workitems, e.g. `obj.query_ses(layout, 'data', bidsfilter.(workitem), 'run',1)`
    end


    methods

        function obj = MP2RAGEWorker(BIDS, subject, config, workdir, outputdir, team, workitems)
            % Constructor for this concrete Worker class

            arguments
                BIDS      (1,1) struct = struct()   % BIDS layout from bids-matlab (raw input data only)
                subject   (1,1) struct = struct()   % A subject struct (as produced by bids.layout().subjects) for which the workitem needs to be fetched
                config    (1,1) struct = struct()   % Configuration struct loaded from the config file
                workdir   {mustBeTextScalar} = ''
                outputdir {mustBeTextScalar} = ''
                team      struct = struct()         % A workitem struct with co-workers that can produce the needed workitems: team.(workitem) -> worker classname
                workitems {mustBeText} = ''         % The workitems that need to be made (useful if the workitem is the end product). Default = ''
            end

            % Call the abstract parent constructor
            obj@qb.workers.Worker(BIDS, subject, config, workdir, outputdir, team, workitems);

            % Make the abstract properties concrete
            obj.name        = "Anakin";
            obj.description = ["I am a working class hero that will happily do the following pre-processing work for you:"];
            obj.version     = "0.1.0";
            obj.needs       = ["TB1map_anat", "TB1map_angle"];        % TODO: Think about using a worker or filter to fetch the raw BIDS (anat and fmap) input data
            obj.bidsfilter.R1map       = struct('modality', 'anat', ...
                                                'part', '', ...
                                                'space', 'MP2RAGE', ...
                                                'desc', 'UNIT1corrected', ...
                                                'suffix', 'R1map');
            obj.bidsfilter.M0map       = setfield(obj.bidsfilter.R1map, 'suffix', 'M0map');
            obj.bidsfilter.MP2RAGE_T1w = setfield(obj.bidsfilter.R1map, 'suffix', 'T1w');

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
            import qb.utils.spm_vol

            % Get the B1 images from the team
            B1famp = obj.ask_team('TB1map_angle');
            B1anat = obj.ask_team('TB1map_anat');
            if length(B1famp) > 1 || length(B1anat) > 1
                obj.logger.error("Expected one TB1map_angle and one TB1map_anat file, but got %d and %d files", length(B1famp), length(B1anat))
            end

            % Process all runs independently
            anat = {'modality','anat'};
            for run = obj.query_ses(obj.BIDS, 'runs', anat{:}, 'part','mag', 'echo',1:999)

                % Load the raw MP2RAGE headers & data
                UNIT1 = obj.query_ses(obj.BIDS, 'data', anat{:}, 'suffix','UNIT1', 'run',char(run));    % TODO: Filter out part-phase images if present
                INV1  = obj.query_ses(obj.BIDS, 'data', anat{:}, 'inv','1', 'suffix','MP2RAGE', 'run',char(run));
                INV2  = obj.query_ses(obj.BIDS, 'data', anat{:}, 'inv','2', 'suffix','MP2RAGE', 'run',char(run));
                if length(UNIT1) ~= 1 || length(INV1) ~= 1 || length(INV2) ~= 1
                    obj.logger.error("Expected one UNIT1, INV1 and INV2 file for run %s, but got %d, %d and %d files", char(run), length(UNIT1), length(INV1), length(INV2))
                end
                UNIhdr  = spm_vol(char(UNIT1));
                INV1hdr = spm_vol(char(INV1));
                INV2hdr = spm_vol(char(INV2));
                UNIimg  = spm_read_vols(UNIhdr);
                INV2img = spm_read_vols(INV2hdr);

                % Construct the (legacy) MP2RAGE metadata struct
                MP2RAGE = obj.getMP2RAGE(INV1, INV2, obj.config.MP2RAGEWorker.InvEff, obj.config.MP2RAGEWorker.EchoSpacing, obj.config.MP2RAGEWorker.NZslices);

                % Realign & reslice the B1 reference image to the INV2 image
                Vin   = spm_vol(char(B1anat));
                x     = spm_coreg(INV2hdr, Vin, struct('cost_fun', 'nmi'));
                B1_   = spm_vol(char(B1famp));
                T     = B1_.mat \ spm_matrix(x) * INV2hdr.mat;     % T = Mapping from voxels in INV2Ref to voxels in B1famp
                B1img = NaN(INV2hdr.dim);
                for z = 1:INV2hdr.dim(3)                           % Reslice the B1famp volume at the coordinates of each coregistered transverse slice of INV2Ref
                    B1img(:,:,z) = spm_slice_vol(B1_, T * spm_matrix([0 0 z]), INV2hdr.dim(1:2), 1);     % Using trilinear interpolation
                end
                B1img(isnan(B1img)) = 0;                           % Set voxels outside the FOV to zero

                % Estimate the UNIT1 image correction and the M0- and R1-maps
                if obj.config.MP2RAGEWorker.Fingerprint == false

                    % Compute the M0- and R1-map
                    [~, UNIcorr]      = qb.MP2RAGE.correctT1B1_TFL(B1img, UNIimg, [], MP2RAGE);
                    [~, M0map, R1map] = qb.MP2RAGE.estimateT1M0(UNIcorr, INV2img, MP2RAGE);

                else

                    INV1img               = spm_read_vols(INV1hdr);
                    INV1img               = qb.MP2RAGE.correctINV1INV2(INV1img, INV2img, UNIimg, 0);
                    [~, M0map, R1map]     = qb.MP2RAGE.dictmatching(MP2RAGE, INV1img, INV2img, B1img, [0.002, 0.005], 1, B1img ~= 0);
                    [Intensity, T1vector] = qb.MP2RAGE.lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
                    UNIcorr = reshape(interp1(T1vector, Intensity, 1./R1map(:)), size(R1map));
                    UNIcorr(isnan(UNIcorr)) = -0.5;
                    UNIcorr = qb.MP2RAGE.unscaleUNI(UNIcorr);      % unscale UNIT1 back to 0-4095 range

                end

                % Perform the unbiased B1-map estimation
                if obj.config.MP2RAGEWorker.B1correctM0 ~= 0
                    M0map = M0map ./ flipdim(B1img, obj.config.MP2RAGEWorker.B1correctM0);
                end

                % Data is only valid where B1 was mapped
                R1map(B1img == 0) = 0;
                M0map(B1img == 0) = 0;

                % Save the R1-map
                bfile                              = obj.bfile_set(char(UNIT1), obj.bidsfilter.R1map);
                bfile.metadata.Sources             = {['bids:raw:' bfile.bids_path]};       % TODO: FIXME + add a JSON sidecar file
                bfile.metadata.InversionEfficiency = MP2RAGE.InvEff;
                bfile.metadata.NZslices            = MP2RAGE.NZslices;
                bfile.metadata.EchoSpacing         = MP2RAGE.EchoSpacing;
                spm_write_vol_gz(UNIhdr, R1map, bfile.path);

                % Save the M0-map
                bfile = obj.bfile_set(bfile, obj.bidsfilter.M0map);
                spm_write_vol_gz(UNIhdr, M0map);                                            % TODO: add a JSON sidecar file

                % Save the corrected UNIT1
                bfile = obj.bfile_set(bfile, obj.bidsfilter.MP2RAGE_T1w);
                spm_write_vol_gz(UNIhdr, UNIcorr, bfile.path);                              % TODO: add a JSON sidecar file

            end
        end

    end

    methods (Access = private)

        function MP2RAGE = getMP2RAGE(obj, INV1, INV2, InvEff, EchoSpacing, NZslices)
            %GETMP2RAGE Extracts the MP2RAGE parameters from the INV1 and INV2 metadata and constructs the (legacy) MP2RAGE metadata struct
            %
            % inv1        - The INV1 image
            % inv2        - The INV2 image
            % InvEff      - Inversion efficiency of the adiabatic inversion pulse
            % EchoSpacing - The RepetitionTimeExcitation value in secs that typically is not given on the json file. Default: twice the echo time
            % NZslices    - The number of shots (slices) in the inner loop (inversion segment), the json file doesn't usually accommodate this

            % Extract the relevant MP2RAGE parameters from the BIDS metadata
            inv1                = bids.File(char(INV1)).metadata;
            inv2                = bids.File(char(INV2)).metadata;
            MP2RAGE.TR          = inv1.RepetitionTime;                          % MP2RAGE TR in seconds
            MP2RAGE.TIs         = [inv1.InversionTime inv2.InversionTime];      % Inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
            MP2RAGE.FlipDegrees = [inv1.FlipAngle     inv2.FlipAngle];          % Flip angle of the two readouts in degrees
            MP2RAGE.InvEff      = InvEff;                                       % Inversion efficiency of the adiabatic inversion pulse
            MP2RAGE.NZslices    = NZslices;
            if isempty(EchoSpacing)
                if isfield(inv1, 'RepetitionTimeExcitation')
                    EchoSpacing = inv1.RepetitionTimeExcitation;                % TR of the GRE readout in seconds
                else
                    EchoSpacing = 2 * inv1.EchoTime;                            % 2*EchoTime can be used as a surrogate
                end
                obj.logger.verbose(['Extracted EchoSpacing: ' num2str(EchoSpacing)])
            end
            MP2RAGE.EchoSpacing = EchoSpacing;
        end

    end

end

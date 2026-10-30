classdef (Sealed) MEGREprepWorker < qb.workers.Worker
%MEGREPREPWORKER Performs preprocessing on raw MEGRE data to produce workitems that can be used by other workers
%
% Preprocessing steps:
%
% 1. Create a brain mask using the echo-1_mag image (for SEPIA)
% 2. Merge all echoes into a 4D file (for running the QSM workflows)
% 3. Denoise the merged 4D file (optional)
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["Performs preprocessing on raw Multi-Echo Gradient Recalled Echo (MEGRE) data for QSM"
                   "and relaxometry workflows."
                   ""
                   "MEGREprepWorker prepares MEGRE acquisitions by performing essential preprocessing"
                   "steps required for subsequent Quantitative Susceptibility Mapping (QSM) and relaxometry"
                   "analysis. MEGRE is a GRE sequence with multiple echo times that allows for both"
                   "magnitude and phase contrast optimization."
                   ""
                   "Processing Steps:"
                   "-----------------"
                   ""
                   "1. Brain Mask Generation:"
                   "   Creates a brain mask for each MEGRE acquisition using the echo-1 magnitude image as"
                   "   input to mri_synthstrip (FreeSurfer), HD-BET, or BET (FSL). Individual masks are"
                   "   combined to produce a minimal output mask suitable for QSM processing."
                   ""
                   "2. Multi-Echo Merging:"
                   "   Merges all echo images (magnitude and phase) for each acquisition into 4D NIfTI"
                   "   files. This format is required by downstream QSM workflows (e.g., SEPIA) that"
                   "   process multi-echo data."
                   ""
                   "3. Denoising (Optional):"
                   "   Applies (Tensor) MPPCA denoising to the merged 4D files to improve"
                   "   signal-to-noise ratio. Configurable via denoising.method ('MPPCA' or 'tMPPCA')"
                   "   and denoising.kernel parameters."
                   ""
                   ".. note::"
                   ""
                   "   * If the brain mask generation uses ``mri_synthstrip``, then FreeSurfer needs to be"
                   "     installed and configured. The same applies if ``HD-BET`` is used. If neither is"
                   "     available, then ``BET`` can be used as a fallback, as this is already included in"
                   "     the MEDI toolbox."
                   "   * Denoising is applied in-place to the merged 4D files when enabled."] % Description should be in ReStructuredText format
    needs       = "raw_MEGRE";   % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        obj.bidsfilter.raw_MEGRE = struct(modality = 'anat', ...
                                          echo     = 1:999, ...
                                          suffix   = 'MEGRE');
        obj.bidsfilter.brainmask = struct(modality = 'anat', ...
                                          echo     = [], ...
                                          part     = '', ...
                                          flip     = [], ...
                                          desc     = 'minimal', ...
                                          label    = 'brain', ...
                                          suffix   = 'mask');
        obj.bidsfilter.ME4Dmag   = struct(modality = 'anat', ...
                                          echo     = [], ...
                                          part     = {{'mag',''}}, ...  % When there is only a magnitude image, the part entity MAY be omitted. But see: https://github.com/bids-standard/bids-matlab/issues/827
                                          desc     = 'ME4D');

        % NB: ME4Dphase data depends on rawMEGRE phase data being present, but is not strictly required for QSM/R2star workflows.
        obj.bidsfilter.ME4Dphase = setfield(obj.bidsfilter.ME4Dmag, part='phase');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get the work done
        if ~isempty(obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.raw_MEGRE))
            qb.workers.MEGREprepWorker.create_brainmask(obj, obj.BIDS, obj.bidsfilter.raw_MEGRE) % Processing step 1
            obj.merge_MEVFAfiles(obj, obj.bidsfilter.raw_MEGRE, obj.BIDS, false)                 % Processing step 2
            qb.workers.MEGREprepWorker.denoise_MPPCA(obj)                                        % Processing step 3
        else
            obj.logger.verbose("No raw MEGRE data found for: " + obj.subject.name)
        end
    end

end


methods (Static)
    % NB: All static methods below are actually instance methods that are shared with VFAprepWorker

    function merge_MEVFAfiles(obj, bfilter, BIDS, cleanup)
        %MERGE_MEVFAFILES merges the 3D echos files for each acq/run/flip angle into 4D files

        arguments
            obj
            bfilter struct
            BIDS    struct
            cleanup logical = true
        end

        import qb.utils.file_merge

        % Process all acq/runs/flips independently and merge the (temp3D) echos files into 4D files
        for acq = obj.query_ses(BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(BIDS, 'runs', bfilter))
                bfilter.run = run;
                for flip = str2double(obj.query_ses(BIDS, 'flips', bfilter))
                    bfilter.flip = flip;
                    for part = string(obj.query_ses(BIDS, 'parts', bfilter))

                        % Get the mag/phase echo images for this flip angle & run
                        [dfiles, bfiles] = obj.query_ses(BIDS, 'data',  bfilter, part=char(part));

                        % Sort the mag/phase files by their echo index
                        [~, idx] = sort(cellfun(@(bf) bf.metadata.EchoNumber, bfiles));

                        % Create the 4D mag/phase QSM/MCR input data
                        bfile = obj.bfile_set(dfiles{1}, setfield(obj.bidsfilter.ME4Dmag, part=part));
                        obj.logger.info("-> Merging echo-1..%d %s images -> %s", length(dfiles), part, bfile.filename)
                        file_merge(dfiles(idx), bfile.path, {'EchoNumber', 'EchoTime'}, cleanup);
                    end
                end
            end
        end
    end

    function create_brainmask(obj, BIDS, bfilter)
        %CREATE_BRAINMASK Implements processing step 1
        %
        % Create brain masks for the BFILTER images in BIDS. Combine flip-masks
        % to produce a combined minimal output mask (for QSM processing)
        %
        % NB: This method is shared with VFAprepWorker

        import qb.utils.spm_vol

        conf = obj.config.(obj.name).brainmask;
        
        % Process all acq/runs independently
        for acq = obj.query_ses(BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(BIDS, 'runs', bfilter))

                obj.logger.info("--> Creating brain mask for run: %d", run)

                % Combine all (echo-1) masks to create a minimal brain mask (using mri_synthstrip or BET)
                mask = true;
                for echo1 = obj.query_ses(BIDS, 'data', bfilter, echo=1, run=run, part={'mag',''})                  % This will loop over flips (NB: and possibly more)
                    bfile = bids.File(char(echo1));
                    specs = setfield(obj.bidsfilter.brainmask, desc=sprintf('VFA%02d', bfile.metadata.FlipAngle));  % Add desc -> (flip)mask is a temporary file
                    bfile = obj.bfile_set(bfile, specs);
                    [~,~] = mkdir(fileparts(bfile.path));   % Ensure the output directory exists
                    switch lower(conf.method)
                        case 'mri_synthstrip'
                            obj.run_command(sprintf('mri_synthstrip -i "%s" -m "%s" %s', char(echo1), bfile.path, conf.options));    % [status,out] = system('echo $CUDA_VISIBLE_DEVICES') does not detect if pytorch was compiled with CUDA support
                            mask = spm_read_vols(spm_vol(bfile.path)) & mask;
                            delete(bfile.path)              % Delete the temporary mask file
                        case 'hd-bet'
                            output = [erase(bfile.path,'.gz') '.gz'];               % HD-BET hardcodes the extension to .nii.gz
                            obj.run_command(sprintf('hd-bet -i "%s" -o "%s" --save_bet_mask --no_bet_image %s', char(echo1), output, conf.options));
                            output = replace(output, '_bet.nii.gz', '.nii.gz');     % HD-BET adds a _bet suffix to the output name for the mask name
                            mask   = spm_read_vols(spm_vol(output)) & mask;
                            delete(output)                  % Delete the temporary mask file
                        case 'bet'
                            Hdr = spm_vol(char(echo1));
                            Par = spm_imatrix(Hdr.mat);
                            if isnumeric(conf.options)      % conf.options is a (jsondecoded) char with the fractional_threshold, gradient_threshold, and radiusarg, e.g. '0.5 0.1 30' or [0.5, 0.1, 30]
                                opts = num2cell(conf.options);
                            else
                                opts = num2cell(str2num(conf.options, Evaluation='restricted'));    %#ok<ST2NM>
                            end
                            mask = BET(spm_read_vols(Hdr), Hdr.dim, abs(Par(7:9)), opts{:}) & mask;
                        otherwise
                            obj.logger.exception("Unknown brainmask.method: " + conf.method + ". Must be one of: mri_synthstrip, HD-BET, BET")
                    end
                end

                % Save the combined mask
                bfile = obj.bfile_set(echo1, obj.bidsfilter.brainmask);
                obj.logger.info("-> Saving: %s", bfile.filename)
                qb.utils.write_vol(spm_vol(char(echo1)), mask, bfile);
            end
        end
    end

    function denoise_MPPCA(obj)
        %DENOISE_MPPCA uses MPPCA or tMPPCA to denoise acq/run 4D (echo) or 5D (echo,flip) images in-place.

        import qb.utils.spm_vol

        denoising = obj.config.(obj.name).denoising;
        if ~strlength(denoising.method)
            return
        end

        BIDSW   = obj.BIDS_ses();
        bfilter = obj.bidsfilter.ME4Dmag;
        for acq = obj.query_ses(BIDSW, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(BIDSW, 'runs', bfilter))
                bfilter.run = run;

                % Get the 4D mag/phase echo images for this acq, run & flip angle and combine them into complex values
                flips = sort(str2double(obj.query_ses(BIDSW, 'flips', bfilter)));
                for n = size(flips,2):-1:1
                    if numel(flips)
                        bfilter.flip = flips(n);
                    end
                    magfile        = char(obj.query_ses(BIDSW, 'data', bfilter));
                    phasefile      = char(obj.query_ses(BIDSW, 'data', bfilter, part='phase'));
                    V_m{n}         = spm_vol(magfile);
                    V_p{n}         = spm_vol(phasefile);
                    img(:,:,:,:,n) = single(spm_read_vols(V_m{n}));
                    if phasefile
                        img(:,:,:,:,n) = img(:,:,:,:,n) .* exp(1i * qb.utils.read_vols_phase(V_p{n})); % Read phase data in radians
                    end
                end

                % Get the mask
                mask = obj.query_ses(BIDSW, 'data', obj.bidsfilter.brainmask);
                mask = logical(spm_read_vols(spm_vol(char(mask))));
                mask = mask & ~any(img, [4 5]);  % Ensures that voxels that have zero intensity at any time point are excluded from the mask. TODO: Check with Jose's unmerged patch-2 branch

                obj.logger.info('--> %s denoising: %s [..]', denoising.method, spm_file(magfile,'filename'))
                switch denoising.method
                    case 'MPPCA'
                        dim = num2cell(size(img));             % Dimensions: [x,y,z,TE,FA]
                        img = reshape(denoise(reshape(img,dim{1:3},[]), denoising.kernel, mask), dim{:});   % The denoise() tool takes maximally 4D data
                    case 'tMPPCA'
                        img = denoise_recursive_tensor(img, denoising.kernel, mask=mask);
                    otherwise
                        obj.logger.exception("Unknown denoising method: " + denoising.method)
                end

                % Save the denoised data (in-place)
                for n = 1:size(flips,2)
                    write_vol_denoised(V_m{n}, abs(img(:,:,:,:,n)))
                    if ~isempty(V_p{n})
                        write_vol_denoised(V_p{n}, angle(img(:,:,:,:,n)))
                    end
                end

            end
        end

        function write_vol_denoised(V, img)
            bfile = bids.File(V(1).fname);
            if isfield(bfile.metadata, 'DenoisingMethod')
                obj.logger.warning('Denoising applied TWICE to "%s": This file was already denoised using "%s"', bfile.path, bfile.metadata.DenoisingMethod)
            end
            bfile.metadata.DenoisingMethod = obj.config.(obj.name).denoising.method;
            bfile.metadata.DenoisingKernel = obj.config.(obj.name).denoising.kernel;
            obj.logger.info("-> Saving: %s", V(1).fname)
            qb.utils.write_vol(V, img, bfile);
        end
    end

end

end

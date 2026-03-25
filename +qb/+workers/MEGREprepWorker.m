classdef MEGREprepWorker < qb.workers.Worker
%MEGREPREPWORKER Performs preprocessing on raw MEGRE data to produce workitems that can be used by other workers
%
% Processing steps:
%
% 1. Create a brain mask using the echo-1_mag image
% 2. Merge all echoes into a 4D file (for running the QSM workflows)
% 3. Denoise the merged 4D file (optional)
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (Constant)
    description = ["I am a working class hero that will happily do the following pre-processing work for you:";
                   "";
                   "1. Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask";
                   "   to produce a minimal output mask (for SEPIA)";
                   "2. Merge all echoes into a 4D file (for running the QSM workflows)"
                   "3. Denoise the merged 4D file (optional)"]
    needs       = "";       % List of workitems the worker needs. Workitems can contain regexp patterns
    usesGPU     = false
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters (each key is a workitem produced by get_work_done(), and can be used in ask_team())
        include                  = obj.config.General.BIDS.include;
        obj.bidsfilter.rawMEGRE  = setfields(include, ...
                                          modality = 'anat', ...
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
                                          part     = 'mag', ...
                                          desc     = 'ME4D');
        obj.bidsfilter.ME4Dphase = setfield(obj.bidsfilter.ME4Dmag, part='phase');
        
        % Constrain the raw input filters based on the BIDS include config
        if all(cellfun('isempty', regexp(include.suffix, 'MEGRE')))
            obj.bidsfilter.rawMEGRE = setfields(include, suffix='');    % MEGRE data is not to be included
        end
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        % Get the work done
        if ~isempty(obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawMEGRE))
            qb.workers.MEGREprepWorker.create_brainmask(obj, obj.BIDS, obj.bidsfilter.rawMEGRE) % Processing step 1
            obj.merge_MEVFAfiles(obj, obj.bidsfilter.rawMEGRE, obj.BIDS, false)                 % Processing step 2
            qb.workers.MEGREprepWorker.denoise_MPPCA(obj)                                       % Processing step 3
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

                    % Get the mag/phase echo images for this flip angle & run
                    [magfiles,   magbfiles]   = obj.query_ses(BIDS, 'data',  bfilter, part='mag');
                    [phasefiles, phasebfiles] = obj.query_ses(BIDS, 'data',  bfilter, part='phase');

                    % Sort the mag/phase files by their echo index
                    [~, magidx]   = sort(cellfun(@(s) s.metadata.EchoNumber, magbfiles));
                    [~, phaseidx] = sort(cellfun(@(s) s.metadata.EchoNumber, phasebfiles));
                    
                    % Create the 4D mag and phase QSM/MCR input data
                    bfile = obj.bfile_set(magfiles{1}, obj.bidsfilter.ME4Dmag);
                    obj.logger.info("-> Merging echo-1..%i mag images -> %s", length(magfiles), bfile.filename)
                    file_merge(magfiles(magidx), bfile.path, {'EchoNumber', 'EchoTime'}, cleanup);

                    bfile = obj.bfile_set(phasefiles{1}, obj.bidsfilter.ME4Dphase);
                    obj.logger.info("-> Merging echo-1..%i phase images -> %s", length(phasefiles), bfile.filename)
                    file_merge(phasefiles(phaseidx), bfile.path, {'EchoNumber', 'EchoTime'}, cleanup);
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

        % Process all acq/runs independently
        for acq = obj.query_ses(BIDS, 'acquisitions', bfilter)
            bfilter.acq = char(acq);
            for run = str2double(obj.query_ses(BIDS, 'runs', bfilter))

                obj.logger.info("--> Creating brain mask for run: %i", run)

                % Combine all (echo-1) masks to create a minimal brain mask (using mri_synthstrip)
                mask = true;
                for echo1 = obj.query_ses(BIDS, 'data', bfilter, echo=1, run=run, part='mag')     % This will loop over flips (NB: and possibly more)
                    bfile = bids.File(char(echo1));
                    specs = setfield(obj.bidsfilter.brainmask, desc=sprintf('VFA%02d', bfile.metadata.FlipAngle));    % Add desc -> (flip)mask is a temporary file
                    bfile = obj.bfile_set(bfile, specs);
                    [~,~] = mkdir(fileparts(bfile.path));   % Ensure the output directory exists
                    obj.run_command(sprintf("mri_synthstrip -i %s -m %s", char(echo1), bfile.path));        % [status,out] = system('echo $CUDA_VISIBLE_DEVICES') does not detect if pytorch was compiled with CUDA support
                    mask  = spm_read_vols(spm_vol(bfile.path)) & mask;
                    delete(bfile.path)                      % Delete the temporary mask file
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

        BIDSW   = obj.BIDSW_ses();
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
                    V_m{n}         = spm_vol(magfile);
                    V_p{n}         = spm_vol(strrep(magfile, 'part-mag', 'part-phase'));
                    img(:,:,:,:,n) = spm_read_vols(V_m{n}) .* exp(1i * qb.utils.read_vols_phase(V_p{n}));   % Read phase data in radians
                end

                % Get the mask
                mask = obj.query_ses(BIDSW, 'data', obj.bidsfilter.brainmask);
                mask = logical(spm_read_vols(spm_vol(char(mask))));

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
                    write_vol_denoised(obj, V_m{n},   abs(img(:,:,:,:,n)))
                    write_vol_denoised(obj, V_p{n}, angle(img(:,:,:,:,n)))
                end

            end
        end

        function write_vol_denoised(obj, V, img)
            bfile = bids.File(V(1).fname);
            if isfield(bfile.metadata, 'Denoised')
                obj.logger.warning('Denoising applied TWICE to "%s": This file was already denoised using "%s"', bfile.path, bfile.metadata.Denoised)
            end
            bfile.metadata.Denoised = obj.config.(obj.name).denoising.method;
            obj.logger.info("-> Saving: %s", V(1).fname)
            qb.utils.write_vol(V, img, bfile);
        end
    end

end

end

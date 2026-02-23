classdef MCRWorker < qb.workers.Worker
%MCRWORKER Runs MCR workflow on the CPU
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (GetAccess = public, SetAccess = protected)
    description = ["Don’t worry, we don’t believe in single compartments here — I can model you something with a lot more interaction.";
                   "";
                   "Methods:"
                   "- "]
    needs       = ["echos4Dmag", "unwrapped", "TB1map_GRE", "fieldmap", "localfmask"]           % List of workitems the worker needs. Workitems can contain regexp patterns
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This interface design allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        import qb.utils.setfields

        % Construct the bidsfilters
        obj.bidsfilter.MWFmap        = struct('modality', 'anat', ...
                                              'echo', [], ...
                                              'flip', [], ...
                                              'part', '', ...
                                              'desc', 'MWI', ...
                                              'suffix', 'MWFmap');
        obj.bidsfilter.FMW_exrate    = setfields(obj.bidsfilter.MWFmap, 'label','free2myelinwater', 'suffix','ExchRate');
        obj.bidsfilter.FitMask       = setfields(obj.bidsfilter.MWFmap, 'label','fitted', 'suffix','mask');
        obj.bidsfilter.MW_M0map      = setfields(obj.bidsfilter.MWFmap, 'label','myelinwater', 'suffix','M0Map');
        obj.bidsfilter.MW_R2starmap  = setfields(obj.bidsfilter.MW_M0map, 'suffix','R2starmap');
        obj.bidsfilter.FW_M0map      = setfields(obj.bidsfilter.MW_M0map, 'label','freewater');
        obj.bidsfilter.FW_T1map      = setfields(obj.bidsfilter.FW_M0map, 'suffix','T1map');
        obj.bidsfilter.FW_R1map      = setfields(obj.bidsfilter.FW_M0map, 'suffix','R1map');
        obj.bidsfilter.IAW_R2starmap = setfields(obj.bidsfilter.FW_M0map, 'label','axonalwater', 'suffix','R2starmap');
        
        % Create orthoslice variants of the bidsfilters
        for fn = string(fieldnames(obj.bidsfilter)')
            obj.bidsfilter.(fn + "_ortho") = setfield(obj.bidsfilter.(fn), 'desc', [obj.bidsfilter.(fn).desc 'ortho']);
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
        img            = single(NaN(dims));
        unwrappedPhase = single(NaN(dims));
        totalField     = single(NaN(dims([1:3 5])));                % Dimensions: [x,y,z,FA]
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

        % Get the algoPara struct and perform data normalisation if needed
        algoPara = obj.config.MCRWorker.algoPara;
        if ~algoPara.isNormData
            obj.logger.info('--> Normalising the multi-echo data')
            [~, img] = mwi_image_normalisation(img, mask);
        end

        % Construct orthoview montages (e.g. for QC) as indicated by the workitem (bidsfilter) name
        ortho = '';
        if endsWith(workitem, 'ortho')
            obj.logger.verbose('Constructing orthoview montages')
            ortho = '_ortho';
            [mask, sel] = obj.orthoslice(mask, 'tight');
            B1          = obj.orthoslice(B1(sel{:}));
            pini        = obj.orthoslice(pini(sel{:}));
            for n = dims(5):-1:1    % Loop backwards to preallocate the '_' variables
                totalField_(:,:,:,n) = obj.orthoslice(totalField(sel{:},n));
                for m = dims(4):-1:1
                    img_(:,:,:,m,n) = obj.orthoslice(img(sel{:},m,n));
                end
            end
            totalField = totalField_;
            img = img_;
        end

        % Construct the imgPara struct
        imgPara            = obj.config.MCRWorker.imgPara;
        imgPara.img        = img;
        imgPara.mask       = mask;
        imgPara.fieldmap   = totalField;
        imgPara.pini       = pini;
        imgPara.b1map      = B1;
        imgPara.te         = TE;
        imgPara.tr         = TR;
        imgPara.fa         = FA;
        imgPara.b0         = bfile.metadata.MagneticFieldStrength;
        imgPara.autosave   = false;
        imgPara.output_dir = char(obj.logger.logdir);
        % imgPara.identifier  = obj.subject.name;     % Add when the MWI PR is accepted and released
        % if obj.subject.session
        %     imgPara.identifier = [imgPara.identifier '_' obj.subject.session];
        % end

        % Estimate the MWI-MCR model
        ws = warning('off', 'MATLAB:nearlySingularMatrix');     % Supress the "Matrix is close to singular or badly scaled" warnings from mwi_3cx_2R1R2s_dimwi -> @(y)CostFunc()
        warning('off', 'MWI:IdentifierFile:NotFound')
        obj.logger.info('--> Estimating the MWI-MCR model')
        fitRes = mwi_3cx_2R1R2s_dimwi(algoPara, imgPara);
        warning(ws)

        % Extract and save the output data
        V(1).dim = [size(mask,1) size(mask,2) size(mask,3)];
        MWF = fitRes.S0_MW ./ (fitRes.S0_MW + fitRes.S0_EW + fitRes.S0_IW);
        spm_write_vol_gz(V(1), MWF,                         obj.bfile_set(bfile, obj.bidsfilter.(['MWFmap'        ortho])));
        spm_write_vol_gz(V(1), fitRes.S0_MW,                obj.bfile_set(bfile, obj.bidsfilter.(['MW_M0map'      ortho])));
        spm_write_vol_gz(V(1), fitRes.S0_IW + fitRes.S0_EW, obj.bfile_set(bfile, obj.bidsfilter.(['FW_M0map'      ortho])));
        spm_write_vol_gz(V(1), fitRes.R2s_MW,               obj.bfile_set(bfile, obj.bidsfilter.(['MW_R2starmap'  ortho])));
        spm_write_vol_gz(V(1), fitRes.R2s_IW,               obj.bfile_set(bfile, obj.bidsfilter.(['IAW_R2starmap' ortho])));
        spm_write_vol_gz(V(1), fitRes.T1_IEW,               obj.bfile_set(bfile, obj.bidsfilter.(['FW_T1map'      ortho])));
        spm_write_vol_gz(V(1), 1 ./ fitRes.T1_IEW,          obj.bfile_set(bfile, obj.bidsfilter.(['FW_R1map'      ortho])));
        spm_write_vol_gz(V(1), fitRes.kiewm,                obj.bfile_set(bfile, obj.bidsfilter.(['FMW_exrate'    ortho])));
        spm_write_vol_gz(V(1), fitRes.mask_fitted,          obj.bfile_set(bfile, obj.bidsfilter.(['FitMask'       ortho])));
    end

end

methods (Static, Access = private)

    function [montage, sel] = orthoslice(vol, crop, xyz)
        % [montage, sel] = orthoslice(vol, crop, xyz)
        %
        % Extract orthogonal slices from a 3D vol and return them as a concatenated row montage.
        %
        % Inputs:
        %   vol     - 3D image volume
        %   crop    - If 'tight' then the volume is cropped to the non-zero part of the image
        %   xyz     - kz positions (default: center of vol)
        %
        % Outputs:
        %   montage - 2D image of the orthogonal slices (axial, coronal, sagittal)
        %   sel     - cell array of the selection indices in each dimension (useful for applying the same cropping to other volumes)

        % Defaults
        if nargin < 2 || isempty(crop)
            crop = 'normal';
        end

        % Crop the volume to the non-zero part if 'tight' display is requested
        sel = {1:size(vol,1), 1:size(vol,2), 1:size(vol,3)};
        if strcmp(crop, 'tight')
            [x,y,z] = ind2sub(size(vol), find(vol));
            sel     = {min(x):max(x), min(y):max(y), min(z):max(z)};
            vol     = vol(sel{:});
        end

        % Set the slice positions to the center of the volume if not provided
        dims = size(vol);
        if nargin < 3 || isempty(xyz)
            xyz = round(dims/2);
        end

        % Create three blank images and 1) an axial, 2) a coronal and 3) a sagittal slice
        axial  = zeros([dims(1) max(dims(2:3))]);
        coron  = zeros([dims(1) max(dims(2:3))]);
        sagit  = zeros([dims(2) max(dims(2:3))]);
        axial_ = squeeze(vol(:,:,xyz(3)));
        coron_ = squeeze(vol(:,xyz(2),:));
        sagit_ = squeeze(vol(xyz(1),:,:));

        % Center the three slices in their respective blank images and concatenate them to a row montage
        axial(:, round((size(axial,2) - size(axial_,2))/2) + (1:size(axial_,2))) = axial_;
        coron(:, round((size(coron,2) - size(coron_,2))/2) + (1:size(coron_,2))) = coron_;
        sagit(:, round((size(sagit,2) - size(sagit_,2))/2) + (1:size(sagit_,2))) = sagit_;
        montage = cat(1, axial, coron, sagit);
    end

end

end

function prepSEPIA(obj, subjects)
% Method implementation for performing pre- and SEPIA-processing - Entry point is in qb.QuIDBBIDS.m

arguments
    obj qb.QuIDBBIDS
    subjects struct
end

% Create the prepdir work directory
obj.prepdir = fullfile(obj.workdir, mfilename);
[~, ~]      = mkdir(obj.prepdir);

% Process all subjects
for subject = subjects

    if ~subject.anat || ~subject.fmap
        continue
    end
    fprintf("\n==> Processing: %s\n", subject.path);
    obj = create_common_T1like_M0(obj, subject);    % Processing step 1
    obj = coreg_FAs_B1_2common(obj, subject);       % Processing step 2
    obj = create_brainmask(obj, subject);           % Processing step 3
    obj = create_QSM_R2star_maps(obj, subject);     % Processing step 4

end

% Create a BIDS structure for the prepdir
bids.init(char(obj.prepdir), ...
          'is_derivative', true,...
          'is_datalad_ds', false, ...
          'tolerant', true, ...
          'verbose', true)


function obj = create_common_T1like_M0(obj, subject)
% Pass echo-1_mag images to despot1 to compute T1w-like target + S0 maps for each FA.
% The results are blurry but within the common GRE space, hence, iterate the computation
% with the input images that have been realigned to the target in the common space

arguments
    obj qb.QuIDBBIDS
    subject struct
end

GRESignal = @(FlipAngle, TR, T1) sind(FlipAngle) .* (1-exp(-TR./T1)) ./ (1-(exp(-TR./T1)) .* cosd(FlipAngle));

% TODO: Index the prepdir if force=false
% BIDS_prep = bids.layout(obj.prepdir, 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all runs independently
for run = bids.query(obj.BIDS, 'runs', 'sub',subject.name, 'ses',subject.session, 'modality','anat')    % Note that the suffix (e.g. 'MEGRE') is already selected in the BIDS layout
    
    % Get the echo-1 magnitude files and metadata for all flip angles of this run
    select  = {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'echo',1, 'part','mag', 'run',run{1}};
    FAs_e1m = bids.query(obj.BIDS, 'data', select);
    meta    = bids.query(obj.BIDS, 'metadata', select);
    flips   = cellfun(@getfield, meta, repmat({'FlipAngle'}, size(meta)), "UniformOutput", true);
    if length(flips) <= 1
        error("Need at least two different flip angles to compute T1 and S0 maps, found:%s", sprintf(" %s", flips{:}));
    end

    % Get metadata from the first FA file (assume TR and nii-header identical for all FAs of the same run)
    Ve1m = spm_vol(FAs_e1m{1});
    TR   = meta{1}.RepetitionTime;

    % Compute T1 and M0 maps
    e1mag = zeros([Ve1m.dim length(flips)]);
    for n = 1:length(flips)
        e1mag(:,:,:,n) = spm_vol(FAs_e1m{n}).dat();
    end
    [T1, M0] = despot1_mapping(e1mag, flips, TR);

    % TODO: Iterate the computation with the input images realigned to the synthetic T1w images

    % Save T1w-like images in the prepdir work directory
    for n = 1:length(flips)
        T1w                  = M0 .* GRESignal(flips(n), TR, T1);
        T1w(~isfinite(T1w))  = 0;
        bfile                = bids.File(FAs_e1m{n});
        bfile.entities.space = 'withinGRE';
        bfile.entities.part  = '';
        bfile.entities.desc  = sprintf('FA%02dsynthetic', flips(n));
        bfile.suffix         = 'T1w';
        fprintf("Saving T1like reference " + bfile.bids_path);
        spm_write_vol_gz(Ve1m, T1w, fullfile(obj.prepdir, bfile.bids_path, bfile.filename));
        meta{n}.Sources      = {['bids:raw:' bfile.bids_path]};
        bids.util.jsonencode(fullfile(obj.prepdir, bfile.bids_path, bfile.json_filename), meta{n});
    end

    % Save the M0 volume as well
    bfile.entities.desc = 'despot1';
    bfile.suffix        = 'M0map';
    fprintf("Saving M0 map " + bfile.bids_path);
    spm_write_vol_gz(Ve1m, M0, fullfile(obj.prepdir, bfile.bids_path, bfile.filename));
    meta{1}.Sources     = strrep(FAs_e1m, extractBefore(bfile.path, bfile.bids_path), 'bids:raw:');
    bids.util.jsonencode(fullfile(obj.prepdir, bfile.bids_path, bfile.json_filename), meta{1});

end


function obj = coreg_FAs_B1_2common(obj, subject)
% Coregister all MEGRE FA-images to each T1w-like target image (using echo-1_mag),
% coregister the B1 images as well to the M0 (which is also in the common GRE space)

arguments
    obj qb.QuIDBBIDS
    subject struct
end

% (Re)index the prepdir layout
BIDS_prep = bids.layout(obj.prepdir, 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all runs independently
for run = bids.query(obj.BIDS, 'runs', 'sub',subject.name, 'ses',subject.session, 'modality','anat')

    % Get the echo-1 magnitude files and metadata for all flip angles of this run
    select  = {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'echo',1, 'part','mag', 'run',run{1}};
    FAs_e1m = bids.query(obj.BIDS, 'data', select);
    meta    = bids.query(obj.BIDS, 'metadata', select);
    flips   = cellfun(@getfield, meta, repmat({'FlipAngle'}, size(meta)), "UniformOutput", true);

    % Realign all FA images to their synthetic targets
    for n = 1:length(flips)

        % Get the common synthetic FA target image
        FAref = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'desc',sprintf('FA%02dsynthetic', flips(n)), 'space','withinGRE', 'run',run{1}});
        if length(FAref) ~= 1
            error("Unexpected synthetic reference images found: %s", sprintf("\n%s", FAref{:}));
        end

        % Coregister the FAs_e1m image to the synthetic target image using Normalized Cross-Correlation (NCC)
        Vref = spm_vol(FAref{1});
        Vin  = spm_vol(FAs_e1m{n});
        x    = spm_coreg(Vref, Vin, struct('cost_fun', 'ncc'));

        % Save all resliced echo images for this flip angle
        for echo = bids.query(obj.BIDS, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'run',run{1}})
            bfile = bids.File(echo{1});
            if bfile.metadata.FlipAngle ~= flips(n)
                continue
            end
            Vin    = spm_vol(echo{1});
            volume = zeros(Vref.dim);
            T      = Vin.mat \ spm_matrix(x) * Vref.mat;    % Transformation from voxels in Vref to voxels in Vin
            for z = 1:Vref.dim(3)
                volume(:,:,z) = spm_slice_vol(Vin, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
            end
            bfile.entities.space = 'withinGRE';
            bfile.entities.desc  = sprintf('FA%02d', flips(n));
            spm_write_vol_gz(Vref, volume, fullfile(obj.prepdir, bfile.bids_path, bfile.filename));
            meta{n}.Sources      = {['bids:raw:' bfile.bids_path]};
            bids.util.jsonencode(fullfile(obj.prepdir, bfile.bids_path, bfile.json_filename), meta{n});
        end

    end

    % Get the B1 images and the common M0 target image
    B1famp = bids.query(obj.BIDS,  'data', {'sub',subject.name, 'ses',subject.session, 'modality','fmap', 'acq','famp', 'echo',[], 'run',run{1}});
    B1anat = bids.query(obj.BIDS,  'data', {'sub',subject.name, 'ses',subject.session, 'modality','fmap', 'acq','anat', 'echo',[], 'run',run{1}});
    M0ref  = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'suffix','M0map', 'run',run{1}});
    if length(B1famp) ~= 1 || length(B1anat) ~= 1
        error("Unexpected B1 images found: %s", sprintf("\n%s", B1famp{:}, B1anat{:}));
    end
    if length(M0ref) ~= 1
        error("Unexpected M0map images found: %s", sprintf("\n%s", M0ref{:}));
    end

    % Coregister the B1-anat fmap to the M0 target image using Normalized Mutual Information (NMI)
    Vref = spm_vol(M0ref{1});
    Vin  = spm_vol(B1anat{1});
    x    = spm_coreg(Vref, Vin, struct('cost_fun', 'nmi'));

    % Save the resliced B1 imagezs
    for B1vol = [B1anat, B1famp]
        Vin    = spm_vol(B1vol{1});
        volume = zeros(Vref.dim);
        T      = Vin.mat \ spm_matrix(x) * Vref.mat;    % Transformation from voxels in Vref to voxels in Vin
        for z = 1:Vref.dim(3)
            volume(:,:,z) = spm_slice_vol(Vin, T * spm_matrix([0 0 z]), Vref.dim(1:2), 1);     % Using trilinear interpolation
        end
        bfile                = bids.File(B1vol{1});
        bfile.entities.space = 'withinGRE';
        spm_write_vol_gz(Vref, volume, fullfile(obj.prepdir, bfile.bids_path, bfile.filename));
        bids.util.jsonencode(fullfile(obj.prepdir, bfile.bids_path, bfile.json_filename), bfile.metadata);
    end

end


function obj = create_brainmask(obj, subject)
% Create a brain mask for each FA using the echo-1_mag image. Combine the individual mask
% to produce a minimal output mask (for Sepia)

arguments
    obj qb.QuIDBBIDS
    subject struct
end

% (Re)index the prepdir layout
BIDS_prep = bids.layout(obj.prepdir, 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all runs independently
for run = bids.query(BIDS_prep, 'runs', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE')

    % Get the echo-1 magnitude file for all flip angles of this run
    FAs_e1m = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'echo',1, 'part','mag', 'space','withinGRE', 'run',run{1}});

    % Create individual brain masks using mri_synthstrip
    Ve1m  = spm_vol(FAs_e1m{1});
    masks = zeros([Ve1m.dim length(FAs_e1m)]);
    for n = 1:length(FAs_e1m)
        bfile                 = bids.File(FAs_e1m{n});
        bfile.entities.label  = 'brain';
        bfile.entities.desc   = sprintf('FA%02d', bfile.metadata.FlipAngle);
        bfile.entities.suffix = 'mask';
        bfile.entities.part   = '';
        bfile.entities.echo   = '';
        run_command(sprintf("mri_synthstrip -i %s -m %s --no-csf", FAs_e1m{n}, bfile.path));
        masks(:,:,:,n)        = spm_vol(bfile.path).dat();
        % delete(bfile.path);    % Delete the individual mask to save space
    end

    % Combine the individual masks to create a minimal brain mask
    bfile.entities.label = 'brain';
    Ve1m.dt(1)           = spm_type('uint8');
    spm_write_vol_gz(Ve1m, all(masks,4), bfile.path);
    bids.util.jsonencode(fullfile(obj.prepdir, bfile.bids_path, bfile.json_filename), bfile.metadata);

end


function obj = create_QSM_R2star_maps(obj, subject)
% Run the Sepia QSM and R2-star pipelines

arguments
    obj qb.QuIDBBIDS
    subject struct
end

% (Re)index the prepdir layout
BIDS_prep = bids.layout(obj.prepdir, 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all runs independently
for run = bids.query(BIDS_prep, 'runs', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE')

    % Get the flip angles and brainmask for this run
    FAs  = bids.query(BIDS_prep, 'desc', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'desc','^FA\d*$', 'part','mag', 'run',run{1}, 'echo',1});
    mask = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'label','brain', 'suffix','mask', 'run',run{1}});
    if length(FAs) < 2
        error("No flip angle images found in: %s", subject.path);
    end
    if length(mask) ~= 1
        error("No brain mask found in: %s", subject.path);
    end

    % Run the Sepia pipelines for each flip angle
    for FA = FAs

        % Get the mag/phase echo images for this flip angle & run
        magfiles   = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'desc',FA{1}, 'part','mag', 'run',run{1}});
        phasefiles = bids.query(BIDS_prep, 'data', {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'desc',FA{1}, 'part','phase', 'run',run{1}});

        % Create 4D mag and phase SEPIA/MCR input data
        bfile               = bids.File(phasefiles{1});
        bfile.entities.echo = '';
        Vphase              = spm_file_merge_gz(phasefiles, bfile.path);
        bfile               = bids.File(magfiles{1});
        bfile.entities.echo = '';
        Vmag                = spm_file_merge_gz(magfiles, bfile.path);
        delete(magfiles{:}, phasefiles{:})                                                      % Delete the redundant 3D source files to save space

        % Create a SEPIA header file
        input.nifti = magfiles{1};                                                              % A nifti file for extracting B0 direction, voxel size, matrix size (from the first 3 dimensions. Alternatively use Vmag.fname)
        for n = 1:length(magfiles)
            input.TEFileList{n} = spm_file(spm_file(magfiles{n}, 'ext', ''), 'ext','.json');    % Cell array of json sidecar files for extracting TE
        end
        bfile.entities.part = '';
        fparts              = split(bfile.filename, '.');                                       % Split filename extensions to parse the basename
        output              = fullfile(obj.derivdir, 'SEPIA', bfile.bids_path, fparts{1});      % Output directory. N.B: SEPIA will interpret the last part of the path as a file-prefix
        save_sepia_header(input, [], output)

        % Run the SEPIA QSM pipeline
        clear input
        input(1).name = Vphase.fname;
        input(2).name = Vmag.fname;
        input(3).name = '';
        input(4).name = [output '_header.mat'];
        sepiaIO(input, output, mask{1}, obj.config.prepSEPIA.QSMParam)

        % Run the SEPIA R2-star pipeline
        sepiaIO(input, output, mask{1}, obj.config.prepSEPIA.R2starParam)

    end

end

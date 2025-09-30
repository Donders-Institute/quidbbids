function SCR_worker(obj, subjects)
% Method implementation for running SCR workflows - Entry point is in qb.QuIDBBIDS.m

arguments
    obj      qb.QuIDBBIDS
    subjects (1,:) struct        % 1×N struct array allowed
end

% Index the outputdir layout
Output = bids.layout(char(obj.outputdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all subjects
for subject = subjects

    if isempty(subject.anat) || isempty(subject.fmap)
        continue
    end
    fprintf("\n==> Processing: %s\n", subject.path)

    % Process all runs independently
    anat = {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE'};
    for run = bids.query(Output, 'runs', anat{:}, 'desc','^FA\d*$', 'suffix','S0map')

        % Get generic metadata (from any QSM output image). NB: Keep queries in sync with QSM_worker.m
        FAs   = bids.query(Output, 'descriptions', anat{:}, 'run',char(run), 'desc','^FA\d*$', 'suffix','S0map');
        files = bids.query(Output,         'data', anat{:}, 'run',char(run), 'desc','^FA\d*$', 'suffix','S0map');
        bfile = bids.File(files{1});
        V     = spm_vol(bfile.filename);

        % Read the QSM images (4th dimension = flip angle)
        S0   = NaN([V.dim(1:3) length(FAs)]);
        R2s  = NaN([V.dim(1:3) length(FAs)]);
        Chi  = NaN([V.dim(1:3) length(FAs)]);
        mask = true;
        for n = 1:length(FAs)
            S0_file   = bids.query(Output, 'data', anat{:}, 'run',char(run), 'desc',FAs{n}, 'suffix','S0map');
            R2s_file  = bids.query(Output, 'data', anat{:}, 'run',char(run), 'desc',FAs{n}, 'suffix','R2starmap');
            Chi_file  = bids.query(Output, 'data', anat{:}, 'run',char(run), 'desc',FAs{n}, 'suffix','Chimap');
            mask_file = bids.query(Output, 'data', anat{:}, 'run',char(run), 'desc',[FAs{n} '\+localfield'], 'suffix','mask');
            if (length(S0_file) ~= 1) || (length(R2s_file) ~= 1) || (length(Chi_file) ~= 1) || (length(mask_file) ~= 1)
                error("No unique QSM output files found in: %s", subject.path);
            end
            S0(:,:,:,n)  = spm_vol(S0_file{1}).dat();
            R2s(:,:,:,n) = spm_vol(R2s_file{1}).dat();
            Chi(:,:,:,n) = spm_vol(Chi_file{1}).dat();
            mask         = spm_vol(mask_file{1}).dat() & mask;
        end

        % Compute weighted means of the R2-star & Chi maps. TODO: Move this over to the QSM workflow
        R2smean  = sum(S0.^2 .* R2s, 4) ./ sum(S0.^2, 4);
        Chimean  = sum(S0.^2 .* Chi, 4) ./ sum(S0.^2, 4);
        spm_write_vol_gz(V, R2smean.*mask, fullfile(R1R2star_dir, [ '_R2starmap.nii.gz']));
        spm_write_vol_gz(V, Chimean.*mask, fullfile(R1R2star_dir, [ '_Chimap.nii.gz']));

        % Compute the R1 and M0 maps using DESPOT1 (based on S0). TODO: Adapt for using echo data as an alternative to S0
        FA_file  = bids.query(Output, 'data', 'sub',subject.name, 'ses',subject.session, 'modality','fmap', 'space','withinGRE', 'acq','famp', 'suffix','TB1TFL');     % TODO: Figure out which run to take (use the average?)
        FA       = spm_vol(FA_file{1}).dat();
        B1       = FA / 10 / bfile.metadata.FlipAngle;
        [T1, M0] = despot1_mapping(S0, fa, bfile.metadata.TR, mask, B1);
        R1       = (mask ./ T1) * 1000;
        R1(~isfinite(R1)) = 0;          % set NaN and Inf to 0
        
        % Save the SCR output maps
        spm_write_vol_gz(V, R1,            fullfile(R1R2star_dir, [ '_R1map.nii.gz']));
        spm_write_vol_gz(V, M0.*mask,      fullfile(R1R2star_dir, [ '_M0map.nii.gz']));

    end

end


%% Legacy code from here onwards
return

% load GRE data
S0   = [];
R2s  = [];
Chi  = [];
mask = [];
fa   = zeros(1, length(prot.flips));
for flipnr = 1:length(prot.flips)

    S0Hdr      =                            spm_vol(fullfile(seq_SEPIA_dir, [ '_space-withinGRE_S0map.nii.gz']));
    S0         = cat(4, S0,   spm_read_vols(S0Hdr));
    R2s        = cat(4, R2s,  spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [ '_space-withinGRE_R2starmap.nii.gz']))));
    Chi        = cat(4, Chi,  spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [ '_space-withinGRE_Chimap.nii.gz']))));
    mask       = cat(4, mask, spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [ '_space-withinGRE_mask_localfield.nii.gz']))));
    fa(flipnr) = []; % Before: SEPIA header
    tr         = []; % Before: SEPIA header. Note that here there was an assumption that all protocols have the same TR

end

% Load B1 info
true_flip_angle = spm_read_vols(spm_vol(fullfile(preproc_dir,    [sub_ses '_acq-famp_run-1_TB1TFLProtocolSpace.nii.gz'])));
b1_header       = jsondecode(fileread(fullfile(converted_b1_dir, [sub_ses '_acq-famp_run-1_TB1TFL.json'])));
b1              = true_flip_angle / 10 / b1_header.FlipAngle;

R2smean  = sum(S0.^2 .* R2s, 4) ./ sum(S0.^2, 4);
Chimean  = sum(S0.^2 .* Chi, 4) ./ sum(S0.^2, 4);

mask     = all(mask, 4);
[T1, M0] = despot1_mapping(S0, fa, tr, mask, b1);
R1       = (mask ./ T1) * 1000;
R1(~isfinite(R1)) = 0;          % set NaN and Inf to 0

spm_write_vol_gz(S0Hdr, R2smean.*mask, fullfile(R1R2star_dir, [ '_space-withinGRE_R2starmap.nii.gz']));
spm_write_vol_gz(S0Hdr, Chimean.*mask, fullfile(R1R2star_dir, [ '_space-withinGRE_Chimap.nii.gz']));
spm_write_vol_gz(S0Hdr, R1,            fullfile(R1R2star_dir, [ '_space-withinGRE_R1map.nii.gz']));
spm_write_vol_gz(S0Hdr, M0.*mask,      fullfile(R1R2star_dir, [ '_space-withinGRE_M0map.nii.gz']));

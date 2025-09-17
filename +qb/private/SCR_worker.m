%% load GRE data
S0   = [];
R2s  = [];
Chi  = [];
mask = [];
fa   = zeros(1, length(prot.flips));
for flipnr = 1:length(prot.flips)
    
    seq_SEPIA_dir = fullfile(SEPIA_dir, prot.acq_str{flipnr});
    
    % general GRE basename
    gre_basename    = [sub_ses '_' prot.acq_str{flipnr} '_' run];
    
    % Read magnitude nifti image data
    S0Hdr           = spm_vol(fullfile(seq_SEPIA_dir, [gre_basename '_MEGRE_space-withinGRE_S0map.nii.gz']));
    S0              = cat(5, S0, spm_read_vols(S0Hdr));
    R2s             = cat(5, R2s, spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [gre_basename '_MEGRE_space-withinGRE_R2starmap.nii.gz']))));
    Chi             = cat(5, Chi, spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [gre_basename '_MEGRE_space-withinGRE_Chimap.nii.gz']))));
    sepia_hdr{flipnr} = load(fullfile(SEPIA_dir, [gre_basename '_header.mat']));
    mask            = cat(5, mask, spm_read_vols(spm_vol(fullfile(seq_SEPIA_dir, [gre_basename '_MEGRE_space-withinGRE_mask_localfield.nii.gz']))));
    
    fa(flipnr)      = sepia_hdr{flipnr}.FA;
    tr              = sepia_hdr{flipnr}.TR; % note that here there is an assumption that all protocols have the same TR
end

% Load B1 info
true_flip_angle     = spm_read_vols(spm_vol(fullfile(preproc_dir, [sub_ses '_acq-famp_run-1_TB1TFLProtocolSpace.nii.gz'])));
b1_header           = jsondecode(fileread(fullfile(converted_b1_dir, [sub_ses '_acq-famp_run-1_TB1TFL.json'])));
b1                  = true_flip_angle / 10 / b1_header.FlipAngle;
figure
Orthoview2(sum(mask,5), [], [], 'tight')
mask = all(mask, 5);

sts = mkdir(R1R2star_dir);
gre_basename = [sub_ses '_' prot.select '_' run];

R2smean = sum(S0.^2 .* R2s,5)./sum(S0.^2 ,5);
Chimean = sum(S0.^2 .* Chi,5)./sum(S0.^2 ,5);

spm_write_vol_gz(S0Hdr, R2smean.*mask, fullfile(R1R2star_dir, [gre_basename '_MEGRE_space-withinGRE_R2starmap.nii.gz']));
spm_write_vol_gz(S0Hdr, Chimean.*mask, fullfile(R1R2star_dir, [gre_basename '_MEGRE_space-withinGRE_Chimap.nii.gz']));

[T1, M0] = despot1_mapping(double(squeeze(S0(:,:,:,1:2))), fa(1:2), tr, mask, b1);

R1 = (mask ./ T1) * 1000;
R1(~isfinite(R1)) = 0;          % set NaN and Inf to 0

spm_write_vol_gz(S0Hdr, R1,       fullfile(R1R2star_dir, [gre_basename '_MEGRE_space-withinGRE_R1map.nii.gz']));
spm_write_vol_gz(S0Hdr, M0.*mask, fullfile(R1R2star_dir, [gre_basename '_MEGRE_space-withinGRE_M0map.nii.gz']));

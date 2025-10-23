restoredefaultpath
addpath(genpath(fullfile('dependencies','despot1')))
addpath(fullfile('dependencies','sepia'))
addpath(fullfile('dependencies','spm'))
addpath(fullfile('dependencies','matlab-toml'))
addpath(fullfile('dependencies','bids-matlab'))
sepia_addpath
clear classes

%% Lukas

if isunix
    bids_dir = '/home/mrphys/marzwi/MWI/bidsPhilipsVariants_copy';
else
    bids_dir = 'P:\3055010.04\RunningProjects\MyelinWaterImaging\bidsPhilipsVariants_copy';
end

%% MCR-MWI

if isunix
    bids_dir = '/home/mrphys/marzwi/staff_scientists/marzwi_sandbox/bids_MCR-MWI';
else
    bids_dir = 'P:\3015999.02\marzwi_sandbox\bids_MCR-MWI';
end
quidb = qb.QuIDBBIDS(bids_dir)
quidb.resumes.Kwok.preferred = true;
mgr   = quidb.manager(["FW_R1map", "meanR2starmap", "MWFmap"])
mgr.start_workflow()

%% ABRIM

if isunix
    bids_dir = '/home/mrphys/marzwi/staff_scientists/marzwi_sandbox/bids_ABRIM';
else
    bids_dir = 'P:\3015999.02\marzwi_sandbox\bids_ABRIM';
end
quidb = qb.QuIDBBIDS(bids_dir)
% quidb.resumes.R2D2.preferred = true;
mgr   = quidb.manager(["Chimap", "R2starmap"])
mgr.start_workflow()

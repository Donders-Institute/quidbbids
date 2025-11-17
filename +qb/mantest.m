restoredefaultpath
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'dependencies','despot1')))
addpath(fullfile(root,'dependencies','sepia'))
addpath(fullfile(root,'dependencies','spm'))
addpath(fullfile(root,'dependencies','matlab-yaml'))
addpath(fullfile(root,'dependencies','bids-matlab'))
addpath(genpath(fullfile(root,'dependencies','gacelle','MCRMWI')))
addpath(genpath(fullfile(root,'dependencies','gacelle','R1R2s')))
addpath(genpath(fullfile(root,'dependencies','gacelle','utils')))
sepia_addpath
clear classes


%% MCR-MWI
if isunix
    bids_dir = '/project/3032002.02/data/bids_MCR-MWI';
else
    bids_dir = 'P:\3032002.02\data\bids_MCR-MWI';
end
quidb = qb.QuIDBBIDS(bids_dir)
quidb.resumes.R2D2.preferred = true;
mgr   = quidb.manager(["R1map", "R2starmap", "MWFmap"])
mgr.start_workflow()


%% ABRIM
if isunix
    bids_dir = '/project/3032002.02/data/bids_ABRIM';
else
    bids_dir = 'P:\3032002.02\data\bids_ABRIM';
end
quidb = qb.QuIDBBIDS(bids_dir)
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect = 1;
quidb.resumes.Kwok.preferred = true;
mgr   = quidb.manager(["Chimap", "R2starmap", "MP2RAGE_T1w"])
mgr.start_workflow()

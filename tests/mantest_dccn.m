restoredefaultpath
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root)
addpath(fullfile(root, "tests"))
clear classes


%% MCR-MWI
if isunix
    bids_dir = '/project/3032002.02/testdata/bids_MCR-MWI_VFA';
else
    bids_dir = 'P:\3032002.02\testdata\bids_MCR-MWI_VFA';
end
quidb = qb.QuIDBBIDS(bids_dir)
quidb.resumes.R2D2.preferred = true;
mgr   = quidb.manager(["R1map", "R2starmap", "MWFmap"])
mgr.start_workflow()


%% ABRIM
if isunix
    bids_dir = '/project/3032002.02/testdata/bids_ABRIM';
else
    bids_dir = 'P:\3032002.02\testdata\bids_ABRIM';
end
quidb = qb.QuIDBBIDS(bids_dir)
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect = 1;
quidb.resumes.Kwok.preferred = true;
mgr   = quidb.manager(["Chimap", "R2starmap", "MP2RAGE_T1w"])
mgr.start_workflow()

restoredefaultpath
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root)
addpath(fullfile(root, "tests"))
clear classes

if isunix
    testdata = '/project/3032002.02/testdata';
else
    testdata = 'P:\3032002.02\testdata';
end

%% MCR-MWI
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_MCR-MWI_VFA'))
quidb.products = ["R1map", "R2starmap", "MWFmap"];
quidb.resumes.R2D2.preferred = true;    % Optional, else GUI usage
mgr = quidb.manager();
mgr.start_workflow()
if isunix
    system(sprintf(['module load bidscoin; ' ...
        'slicereport %s anat/*R1R2s*R1map*     -r %s/report_R1map_gacelle     --options -i 0.2 1.5;' ...
        'slicereport %s anat/*R1R2s*R2starmap* -r %s/report_R2starmap_gacelle --options -i 5 50;' ...
        'slicereport %s anat/*MWFmap*          -r %s/report_MWFmap_gacelle    --options -i 0 20'], repmat(quidb.workdir,1,6)));
end

%% ABRIM
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_ABRIM'))
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect.value = 1;
quidb.products = ["Chimap", "R2starmap", "MP2RAGE_T1w"];
quidb.resumes.Kwok.preferred = true;    % Optional, else GUI usage
mgr = quidb.manager();
mgr.start_workflow()
if isunix
    system(sprintf(['module load bidscoin; ' ...
        'slicereport %s anat/*R2starmap* -r %s/report_R2starmap --options -i 5 50;' ...
        'slicereport %s anat/*Chimap*    -r %s/report_Chimap    --options -i 0.15 0.3'], repmat(replace(quidb.workdir,"QuIDBBIDS","SEPIA"),1,4)));
end

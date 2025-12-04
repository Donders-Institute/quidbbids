if isunix
    restoredefaultpath
    addpath('/home/common/matlab/sepia/sepia_1.2.2.6')
    sepia_addpath
    testdata = '/project/3032002.02/testdata';
else
    testdata = 'P:\3032002.02\testdata';
end
addpath(fileparts(fileparts(mfilename('fullpath'))))

%% MCR-MWI
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_MCR-MWI_VFA'))
quidb.products = ["R1map", "R2starmap", "MWFmap"];
quidb.resumes.R2D2.preferred = true;    % Optional, else GUI usage
mgr = quidb.manager();
mgr.start_workflow()
if isunix
    system(sprintf(['(module load bidscoin;' ...
        'slicereport.py %s anat/*R1R2s*R1map*     -r %s/report_R1map_gacelle     --options i 0.2 1.5;' ...
        'slicereport.py %s anat/*R1R2s*R2starmap* -r %s/report_R2starmap_gacelle --options i 5 50;' ...
        'slicereport.py %s anat/*MWFmap*          -r %s/report_MWFmap            --options i 0 20;' ...
        'slicereport.py %s anat/*Chimap*          -r %s/report_Chimap            --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
        [repmat([quidb.workdir fileparts(quidb.workdir)],1,3) replace(quidb.workdir,"QuIDBBIDS","SEPIA") fileparts(quidb.workdir)]));
end

%% ABRIM
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_ABRIM'))
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect.value = 1;
quidb.products = ["Chimap", "R2starmap", "MP2RAGE_T1w"];
quidb.resumes.Kwok.preferred = true;    % Optional, else GUI usage
mgr = quidb.manager();
mgr.start_workflow()
if isunix
    system(sprintf(['(module load bidscoin;' ...
        'slicereport.py %s anat/*R2starmap* -r %s/report_R2starmap --options i 5 50;' ...
        'slicereport.py %s anat/*Chimap*    -r %s/report_Chimap    --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
        repmat([replace(quidb.workdir,"QuIDBBIDS","SEPIA") fileparts(quidb.workdir)],1,2)));
end

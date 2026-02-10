% MANTEST_DCCN is a manual test script that performs integration test runs on various DCCN datasets

clear functions classes     %#ok<CLCLS,CLFUNC>
if isunix
    restoredefaultpath
    addpath('/home/common/matlab/sepia/sepia_1.2.2.6')
    sepia_addpath
    testdata = '/project/3032002.02/testdata';
else
    testdata = 'P:\3032002.02\testdata';
end
addpath(fileparts(fileparts(mfilename('fullpath'))))
qb.resetconfig              % Useful when running the development version

%% Hamburg_MPM
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_Hamburg_MPM'), "", "", "default")
quidb.resumes.R1R2sWorker.preferred = true;     % Optional, else GUI usage
quidb.config.General.useHPC.value = true;
quidb.config.B1prepWorker.FAscaling.Siemens.value = 100;
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect = 1;
mgr = quidb.manager();

% First run the non-GPU part of the pipeline
quidb.products = [quidb.resumes.R1R2sWorker.needs, quidb.resumes.MCRWorker.needs];  % Alternatively: p=[]; for fn = fieldnames(quidb.resumes)', if quidb.resumes.(char(fn)).usesGPU, p = [p, quidb.resumes.(char(fn)).needs]; end, end, quidb.products = p;
mgr.start_workflow()

% Then run the GPU part of the pipeline
quidb.config.General.HPC.value = {'memreq',20e9, 'timreq',36e3, 'options','--partition=gpu40g --gres=gpu:1'};
quidb.products = ["R1map", "R2starmap", "MWFmap"];
mgr.start_workflow()

% Make QC reports
if isunix
    system(sprintf(['(module load bidscoin; cd %s;' ...
        'slicereport.py %s anat/*R1R2s*R1map*     -r report_R1map_gacelle     --options i 0.2 1.5;' ...
        'slicereport.py %s anat/*R1R2s*R2starmap* -r report_R2starmap_gacelle --options i 5 50;' ...
        'slicereport.py %s anat/*MWFmap*          -r report_MWFmap            --options i 0 20;' ...
        'slicereport.py %s anat/*Chimap*          -r report_Chimap            --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
        fileparts(quidb.workdir), repmat(quidb.workdir,1,3), replace(quidb.workdir,"QuIDBBIDS","SEPIA")));
end

%% MCR-MWI_VFA
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_MCR-MWI_VFA'), "", "", "default")
quidb.resumes.R1R2sWorker.preferred = true;     % Optional, else GUI usage
quidb.config.General.useHPC.value = true;
mgr = quidb.manager();

% First run the non-GPU part of the pipeline
quidb.products = [quidb.resumes.R1R2sWorker.needs, quidb.resumes.MCRWorker.needs];  % Alternatively: p=[]; for fn = fieldnames(quidb.resumes)', if quidb.resumes.(char(fn)).usesGPU, p = [p, quidb.resumes.(char(fn)).needs]; end, end, quidb.products = p;
mgr.start_workflow()

% Then run the GPU part of the pipeline
quidb.config.General.HPC.value = {'memreq',20e9, 'timreq',36e3, 'options','--partition=gpu40g --gres=gpu:1'};
quidb.products = ["R1map", "R2starmap", "MWFmap"];
mgr.start_workflow()

% Make QC reports
if isunix
    system(sprintf(['(module load bidscoin; cd %s;' ...
        'slicereport.py %s anat/*R1R2s*R1map*     -r report_R1map_gacelle     --options i 0.2 1.5;' ...
        'slicereport.py %s anat/*R1R2s*R2starmap* -r report_R2starmap_gacelle --options i 5 50;' ...
        'slicereport.py %s anat/*MWFmap*          -r report_MWFmap            --options i 0 20;' ...
        'slicereport.py %s anat/*Chimap*          -r report_Chimap            --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
        fileparts(quidb.workdir), repmat(quidb.workdir,1,3), replace(quidb.workdir,"QuIDBBIDS","SEPIA")));
end

%% ABRIM_MEGRE
quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_ABRIM_MEGRE'), "", "", "default")
quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect.value = 1;
quidb.products = ["Chimap", "R2starmap", "MP2RAGE_T1w"];
quidb.resumes.QSMWorker.preferred = true;       % Optional, else GUI usage
quidb.config.General.useHPC.value = true;
mgr = quidb.manager();
mgr.start_workflow()

% Make QC reports
if isunix
    system(sprintf(['(module load bidscoin; cd %s;' ...
        'slicereport.py %s anat/*R2starmap* -r report_R2starmap --options i 5 50;' ...
        'slicereport.py %s anat/*Chimap*    -r report_Chimap    --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
        fileparts(quidb.workdir), repmat(replace(quidb.workdir,"QuIDBBIDS","SEPIA"),1,2)));
end

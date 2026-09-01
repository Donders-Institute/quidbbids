function mantest_dccn(datasets)

arguments
    datasets string = ["ABRIM_MEGRE", "MCR-MWI_VFA", "Hamburg_MPM"]
end

% MANTEST_DCCN is a manual test script that performs integration test runs on various DCCN datasets

% Clear QuIDBBIDS classes from cache to ensure that the latest code is used
qbfiles = [dir(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+qb', '**', '*.m'));
           dir(fullfile(fileparts(mfilename('fullpath')), '*.m'))];
for f = 1:length(qbfiles)
    clear(qbfiles(f).name(1:end-2))
end

if isunix
    restoredefaultpath
    addpath('/home/common/matlab/sepia/sepia_1.2.2.6')
    sepia_addpath
    testdata = '/project/3032002.02/testdata';
else
    testdata = 'P:\3032002.02\testdata';
end
addpath(fileparts(fileparts(mfilename('fullpath'))))
qb.resetconfig;             % Useful when running the development version

%% ABRIM_MEGRE
if ismember("ABRIM_MEGRE", datasets)
    quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_ABRIM_MEGRE'), "", "", "default")
    quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect.value = 1;
    quidb.config.MEGREprepWorker.denoising.method.value = "MPPCA";
    quidb.config.MP2RAGEWorker.NumberShots.value = 176;
    quidb.deliverables = ["Chimap", "R2starmap", "MP2RAGE_T1w"];
    quidb.resumes.QSMWorker.preferred = true;       % Optional, else GUI usage
    quidb.config.General.useHPC.value = true;
    quidb.config.General.tag.value = "manualtest";
    mgr = quidb.manager();
    mgr.start_workflow()

    % Make QC reports
    if isunix
        system(sprintf(['(module load bidscoin; cd %s;' ...
            'slicereport %s anat/*R2starmap* -r report_R2starmap --options i 5 50;' ...
            'slicereport %s anat/*Chimap*    -r report_Chimap    --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
            fileparts(quidb.outputdir), repmat(quidb.outputdir,1,2)));
    end
end

%% MCR-MWI_VFA
if ismember("MCR-MWI_VFA", datasets)
    quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_MCR-MWI_VFA'), "", "", "default")
    quidb.resumes.R1R2sWorker.preferred = true;     % Optional, else GUI usage
    quidb.resumes.MCR_GPUWorker.preferred = true;   % Optional, else GUI usage
    quidb.config.VFAprepWorker.denoising.method.value = "tMPPCA";
    quidb.config.General.useHPC.value = true;

    % First run the non-GPU part of the workflow
    quidb.config.General.HPC.value = {'memreq',20e9, 'timreq',48*36e2};
    quidb.deliverables = "MWFmap_ortho";
    quidb.manager().start_workflow()

    % Then run the GPU part of the workflow
    quidb.config.General.HPC.value = {'memreq',20e9, 'timreq',10*36e2, 'options','--partition=gpu --gres=gpu:1'};
    quidb.deliverables = ["R1map", "R2starmap", "Chimap", "MWFmap"];
    quidb.manager().start_workflow()

    % Make QC reports
    if isunix
        system(sprintf(['(module load bidscoin; cd %s;' ...
            'slicereport %s anat/*R1R2s*R1map*     -r report_R1map_gacelle     --options i 0.2 1.5;' ...
            'slicereport %s anat/*R1R2s*R2starmap* -r report_R2starmap_gacelle --options i 5 50;' ...
            'slicereport %s anat/*MWFmap*          -r report_MWFmap            --options i 0 0.2;' ...
            'slicereport %s anat/*Chimap*          -r report_Chimap            --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
            fileparts(quidb.outputdir), repmat(quidb.outputdir,1,4)));
    end
end

%% Hamburg_MPM
if ismember("Hamburg_MPM", datasets)
    quidb = qb.QuIDBBIDS(fullfile(testdata, 'bids_Hamburg_MPM'), "", "", "default")
    quidb.resumes.R1R2sWorker.preferred = true;     % Optional, else GUI usage
    quidb.resumes.MCR_GPUWorker.preferred = true;   % Optional, else GUI usage
    quidb.config.General.useHPC.value = true;
    quidb.config.B1prepWorker.FAscaling.value = 100;
    quidb.config.QSMWorker.QSM.unwrap.isEddyCorrect.value = 1;

    % First run the non-GPU part of the workflow
    % quidb.deliverables = [quidb.resumes.R1R2sWorker.needs, quidb.resumes.MCR_GPUWorker.needs];  % Alternatively: p=[]; for fn = fieldnames(quidb.resumes)', if quidb.resumes.(char(fn)).usesGPU, p = [p, quidb.resumes.(char(fn)).needs]; end, end, quidb.deliverables = p;
    % quidb.manager().start_workflow()

    % Then run the GPU part of the workflow
    quidb.config.General.HPC.value = {'memreq',100e9, 'timreq',10*36e2, 'options','--partition=gpu40g --gres=gpu:1 --constraint=nomig'};    % MIG/NOMIG -> Crashes with NVML errors on partitioned GPUs
    quidb.deliverables = ["R1map", "R2starmap", "Chimap", "MWFmap"];
    quidb.manager().start_workflow()

    % Make QC reports
    if isunix
        system(sprintf(['(module load bidscoin; cd %s;' ...
            'slicereport %s anat/*R1R2s*R1map*     -r report_R1map_gacelle     --options i 0.2 1.5;' ...
            'slicereport %s anat/*R1R2s*R2starmap* -r report_R2starmap_gacelle --options i 5 50;' ...
            'slicereport %s anat/*MWFmap*          -r report_MWFmap            --options i 0 0.2;' ...
            'slicereport %s anat/*Chimap*          -r report_Chimap            --options i -0.15 0.3) < /dev/null > /dev/null 2>&1'], ...
            fileparts(quidb.outputdir), repmat(quidb.outputdir,1,4)));
    end
end

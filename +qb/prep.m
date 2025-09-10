function prep(bids_dir, preprocessing, SepiaPrep, fittingMCR, fittingMCRGPU, writingMCR, acqname, run_label, varargin)
% Process a BIDS directory for Myelin Water Imaging
%
% Usage:
%   prep()     % uses all defaults
%   prep(bids_dir, preprocessing, SepiaPrep, fittingMCR, writingMCR, fittingMCRGPU, acqname, run, sub1, sub2, ...)
%
% Inputs:
%   bids_dir        - Path to BIDS directory (default: current directory)')
%   preprocessing   - Run preprocessing (0/1, default: 1)
%   SepiaPrep       - Advanced SEPIA preparation (0/1, default: 1)
%   fittingMCR      - CPU-based fitting (0/1, default: 1)
%   fittingMCRGPU   - GPU-based fitting (0/1, default: 0)
%   writingMCR      - Result writing (0/1, default: 0)
%   acqname         - Acquisition name coded in the filename as `sub-label_acq[acqname]FA##_run-#..` (default: 'fl3d')
%   run             - Run label (default: {'run-1'})
%   sub1, sub2, ... - Optional list of subject labels to process (default: all subjects in bids_dir)
%
% Examples:
%   prep('/path/to/bids', 0, 0, 0, 0, 1, 'fl3d')
%   prep('/path/to/bids', [], [], [], [], [], 'fl3d', 'run-1', 'sub-01', '02')

% Set default values
def_acqname       = 'fl3d';
def_run_label     = 'run-1';
def_preprocessing = 1;
def_SepiaPrep     = 1;
def_fittingMCR    = 1;
def_fittingMCRGPU = 0;
def_writingMCR    = 0;

% Provide help if the first argument is a help request. Useful for compiled versions
if nargin == 1 && isdeployed && ischar(bids_dir) && (strcmpi(bids_dir, '--help') || strcmpi(bids_dir, '-h'))
    fprintf('\nprep processes a BIDS directory for Myelin Water Imaging (compiled version)\n\n');
    fprintf('Usage:\n');
    fprintf('  run_prep.sh path/to/MCR     # uses all defaults\n');
    fprintf('  run_prep.sh path/to/MCR bids_dir preprocessing SepiaPrep fittingMCR fittingMCRGPU writingMCR acqname run sub1 sub2 ...\n\n');
    fprintf('Inputs:\n');
    fprintf('  bids_dir        - Path to BIDS directory (default: current directory\n');
    fprintf('  preprocessing   - Run preprocessing (0/1, default: %d)\n', def_preprocessing);
    fprintf('  SepiaPrep       - Advanced SEPIA preparation (0/1, default: %d)\n', def_SepiaPrep);
    fprintf('  fittingMCR      - CPU-based fitting (0/1, default: %d)\n', def_fittingMCR);
    fprintf('  fittingMCRGPU   - GPU-based fitting (0/1, default: %d)\n', def_fittingMCRGPU);
    fprintf('  writingMCR      - Result writing (0/1, default: %d)\n', def_writingMCR);
    fprintf('  acqname         - Acquisition name coded in the filename as `sub-label_acq[acqname]FA##_run-#..` (default: %s)\n', def_acqname);
    fprintf('  run             - Run label (default: %s)\n', def_run_label);
    fprintf('  sub1, sub2, ... - Optional list of subject labels to process (default: all subjects in bids_dir)\n\n');
    fprintf('Examples:\n');
    fprintf('  run_prep.sh path/to/MCR /path/to/bids 1 1 1 0 0 fl3d\n');
    fprintf('  run_prep.sh path/to/MCR /path/to/bids 0 0 0 0 1 fl3d run-1 sub-01 02\n');
    return
end

% Handle input arguments (argument blocks are not supported in compiled version)
if nargin < 1 || isempty(bids_dir)
    bids_dir = pwd;
end
if ~isfolder(bids_dir)
    error('BIDS directory not found: %s', bids_dir);
end
if nargin < 2 || isempty(preprocessing)
    preprocessing = def_preprocessing;
else
    preprocessing = logical(str2double(preprocessing));
end
if nargin < 3 || isempty(SepiaPrep)
    SepiaPrep = def_SepiaPrep;
else
    SepiaPrep = logical(str2double(SepiaPrep));
end
if nargin < 4 || isempty(fittingMCR)
    fittingMCR = def_fittingMCR;
else
    fittingMCR = logical(str2double(fittingMCR));
end
if nargin < 5 || isempty(fittingMCRGPU)
    fittingMCRGPU = def_fittingMCRGPU;
else
    fittingMCRGPU = logical(str2double(fittingMCRGPU));
end
if nargin < 6 || isempty(writingMCR)
    writingMCR = def_writingMCR;
else
    writingMCR = logical(str2double(writingMCR));
end
if nargin < 7 || isempty(acqname)
    acqname = def_acqname;
end
if nargin < 8 || isempty(run_label)
    run_label = def_run_label;
end
if isempty(regexp(run_label, 'run-\d+', 'once'))
    warning('Run label %s does not match BIDS pattern "run-<number>"', run_label);
end

% Collect the subject labels
if isempty(varargin)
    subjects = dir(fullfile(bids_dir, 'sub-*'));
    subjects = subjects([subjects.isdir]);  % Make sure we have only folders
else
    subjects = struct('name', varargin);    % Use provided subject names
    for i = 1:length(subjects)
        if ~startsWith(subjects(i).name, 'sub-')
            subjects(i).name = ['sub-' subjects(i).name];
        end
        if ~isfolder(fullfile(bids_dir, subjects(i).name))
            error('Subject folder not found: %s', fullfile(bids_dir, subjects(i).name));
        end
    end
end

% Inform the user about the parameters
fprintf('\nRunning prep with the following parameters:\n');
fprintf('       bids_dir: %s\n', bids_dir);
fprintf('  preprocessing: %d\n', preprocessing);
fprintf('      SepiaPrep: %d\n', SepiaPrep);
fprintf('     fittingMCR: %d\n', fittingMCR);
fprintf('  fittingMCRGPU: %d\n', fittingMCRGPU);
fprintf('     writingMCR: %d\n', writingMCR);
fprintf('        acqname: %s\n', acqname);
fprintf('      run_label: %s\n', run_label);
fprintf('       subjects: %s\n', strjoin({subjects.name}, ', '));

% Set up the user path. TODO: Remove tinkering with paths, they are static in the compiled version
code_dir = prep_path;

% Process the subjects in the BIDS directory
prot.rec = ['acq-' acqname];                % Protocol name, e.g., 'acq-fl3d'. TODO: Parse the protocol from the BIDS directory
for subjn = 1:length(subjects)

    % Parse the flip angles and echos from the filename
    prot_files    = dir(fullfile(bids_dir, subjects(subjn).name, 'anat', ['*' prot.rec '*.nii.gz']));
    bf_array      = arrayfun(@(x) bids.File(x.name), prot_files');
    echos         = arrayfun(@(x) x.entities.echo, bf_array, 'UniformOutput', false);
    flips         = arrayfun(@(x) x.entities.acq, bf_array, 'UniformOutput', false);
    prot.echo     = sort(unique(str2double(echos)));
    prot.flip     = sort(unique(str2double(extractAfter(flips, 'FA'))));
    prot.echo_str = arrayfun(@(n) sprintf('echo-%d', n), 1:length(prot.echo), 'UniformOutput', false);
    prot.flip_str = arrayfun(@(fa) sprintf('FA%d', fa), prot.flip, 'UniformOutput', false);
    prot.acq_str  = cellfun(@(fa) [prot.rec fa], prot.flip_str, 'UniformOutput', false);

    subj_label = subjects(subjn).name;
    subject_directory_master            % Puts foldernames in the worksapce, derived from bids_dir and subj_label
    fprintf('\n--> Processing: %s (%d/%d)\n', subj_label, subjn, length(subjects));
    disp(prot)

    if preprocessing
        ProcessingPipelineModular(prot, subj_label, run_label, bids_ses_dir, derivative_FSL_dir, derivative_SEPIA_dir, derivative_MRI_SYNTHSEG_dir)
    end

    if SepiaPrep
        if ~isdeployed
            sepia_addpath
        end
        SEPIA_03_standard_pipeline
        script_SCR
    end

    % Some solvers have similar names in various packages and we have to make sure the MWI is the one that gets used
    if ~isdeployed
        warning off
        rmpath(genpath(fullfile(code_dir,'sepia_1.2.2.5')));
        rmpath(genpath(fullfile(code_dir,'mwi')));
        warning on
        addpath(genpath(fullfile(code_dir,'mwi')));
    else
        disp('Running in compiled mode, not changing paths!!!');
    end
    
    input                      = struct();
    input.derivative_SEPIA_dir = derivative_SEPIA_dir;
    input.derivative_FSL_dir   = derivative_FSL_dir;
    input.acq_str              = prot.acq_str;
    input.B1scaleFactor        = 800;               % directory where json b1 information is present alternatively it can be the scaling factor of B1 field
    input.subj_label           = subj_label;
    input.run_label            = run_label;
    output.acq_str             = prot.rec;
    output.derivative_MWI_dir  = derivative_MWI_dir; % main output directory

    if fittingMCR || writingMCR
        % Check that MWI toolbox is at the top of the path it has a solver that has conflicts with SEPIA and despot
        % MPPCAdenoise = 1;     % this actually has a positive effect on maps
        if fittingMCR
            task.Submit_Job           = 1;
            task.ReSubmit_MissingJobs = 0;
            task.Read_JobResults      = 0; % ideally one would have this one as also 1, but that just takes too much time
        end
        if writingMCR
            task.Submit_Job           = 0;
            task.ReSubmit_MissingJobs = 1;
            task.Read_JobResults      = 1; % only do this if enough slices have successfully been processed
        end

        output.MPPCAdenoise = 0;
        func_MCR_AfterCoregistration_qsubfeval_submitread(input, output, task)
        output.MPPCAdenoise = 1;
        func_MCR_AfterCoregistration_qsubfeval_submitread(input, output, task)

        input.Configfile    = 'ConfigDiscardFirstEcho.m';
        output.acq_str      = [prot.rec 'Echo1corrupted'];
        output.MPPCAdenoise = 0;
        func_MCR_AfterCoregistration_qsubfeval_submitread(input, output, task)

    end
    if fittingMCRGPU
        jobmaxtime          = 4 * 60^2; % 60 minutes
        input.Configfile    = 'ConfigGPU.m';
        output.acq_str      = [prot.rec 'GPU'];
        output.MPPCAdenoise = 0;
        if canUseGPU || isdeployed
            func_MCR_AfterCoregistration_gpu(input, output);
        else
            qsubfeval(@func_MCR_AfterCoregistration_gpu, input, output, 'memreq',12*1024^3, 'timreq',jobmaxtime , 'options','--partition=gpu --gpus=nvidia_rtx_a6000:1');
        end
    end

end
disp("Finished processing")


function code_dir = prep_path
% Set and saves the matlab userpath for the compiled version of prep.m
% Returns the code directory where prep.m is located

code_dir = fileparts(mfilename('fullpath'));

if isdeployed
    return
end

% Get the original path
originalPaths = strsplit(path, pathsep);

% Add the userpaths
addpath(code_dir);
addpath(fullfile(code_dir,'sepia_1.2.2.5'));            % https://github.com/kschan0214/sepi
addpath(genpath(fullfile(code_dir,'despot1')));         % https://github.com/kschan0214/despot1
addpath(genpath(fullfile(code_dir,'EPG-X'))); 	        % KCL extended phase graphs
addpath(genpath(fullfile(code_dir,'utils')));
addpath(fullfile(code_dir,'MP-PCA-Denoising'));
addpath(fullfile(code_dir,'qsub'));
addpath(genpath(fullfile(code_dir,'gacelle')))          % /project/3055010.04/RunningProjects/AskAdam/gacelle/
addpath(genpath(fullfile(code_dir,'mwi')));
sepia_addpath

% Get the new path and save the difference (needed for creating a compiled version)
newPaths   = strsplit(path, pathsep);
addedPaths = setdiff(newPaths, originalPaths);
addedPaths = addedPaths(~contains(addedPaths, '.git'));
addedPaths = addedPaths(~cellfun(@isempty, addedPaths));
fid = fopen('prep_paths.txt', 'w');
for i = 1:numel(addedPaths)
    fprintf(fid, '%s\n', addedPaths{i});
end
fclose(fid);

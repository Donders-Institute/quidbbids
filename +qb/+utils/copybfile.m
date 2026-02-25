function copybfile(source, target, force)
%COPYBFILE(SOURCE, TARGET, LAYOUT) copies the SOURCE data + metadata to the TARGET destination.
% 
% Inputs:
%   SOURCE - Path to or bids.File object of the source file to be copied.
%   TARGET - bids.File object specifying the destination path.
%   FORCE  - (Optional) If true, existing files at the destination will be overwritten. Default: false.
%
% Example:
%   source = 'bidsdir/sub-004/anat/sub-004_acq-fl3d_MEGRE.nii.gz';
%   target = obj.bfile_set(source, struct('acq','demo', 'run',1, 'suffix','M0map'));
%   obj.copybfile(source, target)   % Write source data to: 'workdir/sub-004/anat/sub-004_acq-demo_run-1_M0map.*'
%
% See also: bids.File

arguments
    source  {mustBeA(source,["bids.File","char","string"])}
    target  bids.File
    force   logical = false
end

% Parse the input arguments
if ~isa(source,'bids.File')
    source = bids.File(char(source));
end

% Copy the data and metadata to the destination
if isfile(target.path) && ~force
    fprintf('File already exists at destination: %s. Use force=true to overwrite\n', target.path)
else
    [~,~] = mkdir(fileparts(target.path));
    copyfile(source.path, target.path)
    bids.util.jsonencode(char(strrep(target.path, target.filename, target.json_filename)), source.metadata)
end

function copybfile(source, target)
%COPYBFILE(SOURCE, TARGET, LAYOUT) copies the SOURCE data + metadata to the TARGET destination.
% 
% Inputs:
%   SOURCE - Path to or bids.File object of the source file to be copied.
%   TARGET - bids.File object specifying the destination path.
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
end

% Parse the input arguments
if ~isa(source,'bids.File')
    source = bids.File(char(source));
end

% Create the destination directory if it does not exist
if ~isfolder(fileparts(target.path))
    [~,~] = mkdir(fileparts(target.path));
end

% Copy the data and metadata to the destination
copyfile(source.path, target.path)
bids.util.jsonencode(strrep(target.path, target.filename, target.json_filename), source.metadata)

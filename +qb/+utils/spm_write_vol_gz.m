function V = spm_write_vol_gz(V, Y, fname)
% FUNCTION V = SPM_WRITE_VOL_GZ(V, Y, fname)
%
% A wrapper around SPM_WRITE_VOL that sets an appropriate datatype, writes a .nii or
% a .nii.gz file. If fname is provided, it will override the file name in V.fname.
% The V.mat field is required or V must be an array with voxelsizes in the x-, y- and
% z- dimension.
%__________________________________________________________________________
%   SPM_WRITE_VOL
%
%   Write an image volume to disk, setting scales and offsets as appropriate
%   FORMAT V = spm_write_vol(V,Y)
%   V (input)  - a structure containing image volume information (see spm_vol)
%   Y          - a one, two or three dimensional matrix containing the image voxels
%   V (output) - data structure after modification for writing.
%
%   Note that if there is no 'pinfo' field, then SPM will figure out the
%   max and min values from the data and use these to automatically determine
%   scalefactors.  If 'pinfo' exists, then the scalefactor in this is used.

% Create a minimal header struction if only voxel sizes are provided
if isnumeric(V) && isvector(V)
    V = struct('mat', diag([V(:); 1]));
    if nargin < 3 || isempty(fname)
        error('When providing only voxel sizes, an output filename must be specified')
    end
end

% Ensure dim field is correct (e.g. if only voxel sizes are provided)
if ~isfield(V, 'dim') || isempty(V.dim)
    V.dim = [size(Y, 1) size(Y, 2) size(Y, 3)];
end

% Choose appropriate data type if not specified
if ~isfield(V, 'dt') || isempty(V.dt)
    if isinteger(Y) || (all(abs(Y(:) - round(Y(:))) < 1e-6) && any(abs(Y(:)) > 0.5))
        V.dt = [spm_type('int32') spm_platform('bigend')];
    else
        V.dt = [spm_type('float32') spm_platform('bigend')];
    end
end
if islogical(Y)     % It makes no sense to store logical data (e.g. masks) as float or int32
    V.dt(1) = spm_type('uint8');
end

% Override filename if provided
if nargin > 2 && ~isempty(fname)
    V.fname = char(fname);
end

% Write the data to the file, either as .nii or .nii.gz
[fpath, ~, ext] = fileparts(V.fname);
[~,~]           = mkdir(fpath);
switch ext
    case '.gz'
        V.fname = spm_file(V.fname, 'ext','');
        V       = spm_write_vol(V, Y);
        gzip(V.fname)
        delete(V.fname)
        V.fname = [V.fname '.gz'];
    case '.nii'
        V = spm_write_vol(V, Y);
    otherwise
        error('Unknown file extension %s in %s', ext, V.fname)
end

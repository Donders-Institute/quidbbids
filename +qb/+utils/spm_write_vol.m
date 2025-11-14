function V = spm_write_vol(V, Y, fname, dt)
% A convenient wrapper around SPM_WRITE_VOL that writes either a .nii or .nii.gz file.
%
% Usage:
%   V = spm_write_vol(V, Y)
%   V = spm_write_vol(V, Y, fname)
%   V = spm_write_vol(V, Y, fname, dt)
%
% Inputs:
%   V     - Volume structure containing header information (see spm_vol).
%           Alternatively, V can be a numeric vector specifying voxel sizes [vx vy vz]
%   Y     - Image 3D data array to write to disk
%   fname - (Optional) Output file name. If provided, overrides V.fname. Needed
%           if V is specified as voxel sizes.
%   dt    - (Optional) Desired data type as a string. If not specified, an appropriate
%           type is automatically chosen based on Y.
%
% Ooutput:
%   V     - Updated volume structure after writing, with the correct filename
%           and data type.
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

if nargin < 4
    dt = [];
end

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

% Choose appropriate data type
if dt
    V.dt    = [spm_type(dt) spm_platform('bigend')];
elseif islogical(Y)
    V.dt    = [spm_type('uint8') spm_platform('bigend')];
    V.pinfo = [1;0;0];      % Ensure no scaling is applied
else
    V.dt    = [spm_type('float32') spm_platform('bigend')];
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
        V.dat   = Y;                % Cache data in case of re-reading
        gzip(V.fname)
        delete(V.fname)
        V.fname = [V.fname '.gz'];
        V.dt(1) = 64;               % Update datatype to align with spm_vol reading of .nii.gz files
    case '.nii'
        V = spm_write_vol(V, Y);
    otherwise
        error('Unknown file extension %s in %s', ext, V.fname)
end

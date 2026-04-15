function V = write_vol(V, Y, bfile, dt)
% A convenient wrapper around SPM_WRITE_VOL that writes either a .nii or .nii.gz file.
%
% Usage:
%   V = write_vol(V, Y)
%   V = write_vol(V, Y, bfile)
%   V = write_vol(V, Y, fname, dt)
%
% Inputs:
%   V     - Volume structure containing header information (see spm_vol).
%           Alternatively, V can be a numeric vector specifying voxel sizes [vx vy vz]
%   Y     - Image 3D/4D/5D data array to write to disk (5D will likely break SPM functions)
%   bfile - (Optional) Output bids.File or filename. If provided, overrides V.fname.
%           Needed if V is specified as voxel sizes. If provided as a bids.File, the
%           JSON sidecar file will also be saved with the metadata from the bfile.
%   dt    - (Optional) Desired data type as a string. If not specified, an appropriate
%           type is automatically chosen based on Y.
%
% Output:
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
    if nargin < 3 || isempty(bfile)
        error('QuIDBBIDS:Nifti:MissingInputArgument', 'When providing only voxel sizes, an output (b)filename must be specified')
    end
end

% For 4D data, just take the first (of all identical) volume, i.e. make sure we have a 3D vol
V = V(1);

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

% Save a json sidecar file and override V.fname if bfile was provided
if nargin > 2 && ~isempty(bfile)
    if isa(bfile, 'bids.File')
        [~,~] = mkdir(fileparts(bfile.path));
        bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)
        V.fname = char(bfile.path);
    else
        V.fname = char(bfile);
    end
end

% Write the (4D) data to the file, either as .nii or .nii.gz
[fpath, ~, ext] = fileparts(V.fname);
[~,~]           = mkdir(fpath);
V               = repmat(V, size(Y,4), size(Y,5));
switch ext
    case '.gz'
        for n = 1:size(Y,4)
            for m = 1:size(Y,5)
                V(n,m).fname = spm_file(V(n,m).fname, 'ext','');
                V(n,m).n     = [n m];
                V(n,m)       = spm_write_vol(V(n,m), Y(:,:,:,n,m));
                V(n,m).dat   = Y(:,:,:,n,m);      % Cache data in case of re-reading
                V(n,m).fname = [V(n,m).fname '.gz'];
                V(n,m).dt(1) = 64;                % Update datatype to align with spm_vol reading of .nii.gz files
            end
        end
        gzip(spm_file(V(1).fname, 'ext',''))
        delete(spm_file(V(1).fname, 'ext',''))
    case '.nii'
        for n = 1:size(Y,4)
            for m = 1:size(Y,5)
                V(n,m).n = [n m];
                V(n,m)   = spm_write_vol(V(n,m), Y(:,:,:,n,m));
            end
        end
    otherwise
        error('QuIDBBIDS:Nifti:InvalidInputArgument', 'Unknown file extension %s in %s', ext, V.fname)
end

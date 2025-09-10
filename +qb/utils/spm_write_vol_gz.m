function V = spm_write_vol_gz(V, Y, fname)
% FUNCTION V = SPM_WRITE_VOL_GZ(V, Y, fname)
%
% A wrapper around SPM_WRITE_VOL that removes the pinfo field, writes a
% .nii or a .nii.gz file. If fname is provided, it will override the file
% name in V.fname. The V.mat field is required or V must be an array
% with voxelsizes in the x-, y- and z- dimension.
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

if isnumeric(V) && isvector(V)
    V = struct('mat', [diag(V(:)); 1]);
end

if nargin > 2 && ~isempty(fname)
    V.fname = fname;
end

if isfield(V, 'pinfo')
    V = rmfield(V, 'pinfo');
end

if ~isfield(V, 'dim')
    V.dim = [size(Y, 1) size(Y, 2) size(Y, 3)];
end

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
        error('Unknown file extenstion %s in %s', ext, V.fname)
end

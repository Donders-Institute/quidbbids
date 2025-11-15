function V4 = spm_file_merge_gz(V, fname, metafields, cleanup, varargin)
% SPM_FILE_MERGE_GZ  Concatenate 3D volumes into a single 4D volume.
%
% V4 = SPM_FILE_MERGE_GZ(V, fname, metafields, dt, RT) is a wrapper around
% SPM_FILE_MERGE that writes out a 4D NIfTI volume (.nii or .nii.gz) and
% generates a JSON sidecar based on the first input JSON file (if available).
%
% Inputs:
%   V          - Images to concatenate. Can be a cellstr of filenames, or an
%                spm_vol struct array.
%   fname      - Output filename for the 4D volume (string or char).
%                Default: '4D.nii'. If no path is specified, the output
%                is written to the folder of the first input image.
%   metafields - Cell array of JSON sidecar field names. For each field, the
%                values are read from the input JSON files (if available) and
%                saved as a concatenated array in the output JSON sidecar file.
%                Default: {}
%   cleanup    - If true, deletes the 3D input NIfTI and JSON files. Default: true.
%   dt         - Data type (see spm_type). Default: 0 (same as first input volume).
%   RT         - Interscan interval in seconds. Default: NaN.
%
% Output:
%   V4         - spm_vol struct describing the merged 4D volume.
%
% Note:
% For integer datatypes, the scale factor is chosen to maximize the range of
% representable values. This may introduce small quantization differences between
% the input and output data.
%
% Example:
%   V  = spm_vol(char({'sub-01_echo-1.nii.gz', 'sub-01_echo-2.nii.gz'}));
%   V4 = spm_file_merge_gz(V, 'sub-01_4D.nii.gz', {'EchoNumber', 'EchoTime'});

arguments (Input)
    V
    fname      {mustBeTextScalar, mustBeNonempty} = '4D.nii.gz'
    metafields cell                               = {}
    cleanup   (1,1) logical                       = true
end

arguments (Input, Repeating)
    varargin
end

arguments (Output)
    V4 struct
end

fname            = char(fname);
[pth, name, ext] = fileparts(fname);
[~,~]            = mkdir(pth);
unzipped         = false(size(V));
switch ext
    case '.gz'
        if isstruct(V)                  % Convert to cellstr of filenames
            V = arrayfun(@(s) s.fname, V, 'UniformOutput', false);
        end
        for i = 1:numel(V)              % Unzip any .nii.gz files
            if endsWith(V{i}, '.gz')
                Vgz         = V{i};
                V(i)        = gunzip(V(i));
                unzipped(i) = true;
                if cleanup
                    delete(Vgz)         % Delete the original .nii.gz file (the .nii file will be deleted later)
                end
            end
        end
        niifile = fullfile(pth, name);  % NB: Here "name" has a '.nii' extension
        if nargout
            V4 = spm_file_merge(V, niifile, varargin{:});
            for n = 1:numel(V4)
                V4(n).fname = fname;
                V4(n).dt(1) = 64;                           % Update datatype to align with spm_vol reading of .nii.gz files
            end
        else
            spm_file_merge(V, niifile, varargin{:})
        end
        gzip(niifile)
        delete(niifile)
    case '.nii'
        if nargout
            V4 = spm_file_merge(V, fname, varargin{:});     % NB: This fails if V contains .nii.gz files
        else
            spm_file_merge(V, fname, varargin{:})
        end
    otherwise
        error('Unknown file extension %s in %s', ext, fname)
end

% Read/aggregate sidecar metadata, and delete the original .nii + sidecar files (if available)
for n = 1:numel(V)

    % Get the sidecar information
    if isstruct(V)
        niisrc = V(n).fname;
    else
        niisrc = V{n};
    end
    bfile    = bids.File(niisrc);
    jsonfile = spm_file(niisrc, 'ext','.json');

    % Read the metadata from the first sidecar (if available)
    if n == 1
        metadata   = bfile.metadata;
        metavalues = cell(length(metafields), numel(V));
    end

    % Aggregate the metavalues for the specified metafields (if available)
    for m = 1:length(metafields)
        if isfield(bfile.metadata, metafields{m})
            metavalues{m, n} = bfile.metadata.(metafields{m});
        end
        metadata.(metafields{m}) = metavalues(m,:);
    end

    % Delete the original nifti and json files, and unzipped nifti files
    if unzipped(n) || cleanup
        delete(niisrc)
    end
    if cleanup
        spm_unlink(jsonfile)
    end

end

% Write the output JSON sidecar (if there was at least one input sidecar)
if ~isempty(metadata)
    bids.util.jsonencode(spm_file(spm_file(fname, 'ext',''), 'ext','.json'), metadata)
end

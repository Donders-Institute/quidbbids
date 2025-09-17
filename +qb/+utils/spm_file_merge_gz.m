function V4 = spm_file_merge_gz(V, fname, metafields, varargin)
% SPM_FILE_MERGE_GZ  Concatenate 3D volumes into a single 4D volume.
%
% V4 = SPM_FILE_MERGE_GZ(V, fname, metafields, dt, RT) is a wrapper around
% SPM_FILE_MERGE that writes out a 4D NIfTI volume (.nii or .nii.gz) and
% generates a JSON sidecar based on the first input JSON file (if available).
% All original 3D input NIfTI and JSON files are deleted after merging.
%
% INPUTS:
%   V          - Images to concatenate. Can be a char array, cellstr of 
%                filenames, or an spm_vol struct array.
%   fname      - Output filename for the 4D volume (string or char). 
%                Default: '4D.nii'. If no path is specified, the output
%                is written to the folder of the first input image.
%   metafields - Cell array of JSON sidecar field names. For each field, the
%                values are read from the input JSON files (if available) and
%                saved as a concatenated array in the output JSON sidecar file.
%                Default: {}
%   dt         - Data type (see spm_type). Default: 0 (same as first input volume).
%   RT         - Interscan interval in seconds. Default: NaN.
%
% OUTPUT:
%   V4         - spm_vol struct describing the merged 4D volume.
%
% NOTE:
% For integer datatypes, the scale factor is chosen to maximize the range of
% representable values. This may introduce small quantization differences between
% the input and output data.
%
% EXAMPLE:
%   V  = spm_vol(char({'sub-01_echo-1.nii.gz', 'sub-01_echo-2.nii.gz'}));
%   V4 = spm_file_merge_gz(V, 'sub-01_4D.nii.gz', {'EchoNumber', 'EchoTime'});

arguments
    V
    fname       {mustBeText} = '4D.nii'
    metafields  (1,:) cellstr = {}
end
arguments (Repeating)
    varargin
end

fname            = char(fname);
[pth, name, ext] = fileparts(fname);
[~,~]            = mkdir(pth);
switch ext
    case '.gz'
        if isstruct(V)
            V = arrayfun(@(s) s.fname, V, 'UniformOutput', false);
        end
        for i = 1:numel(V)
            if endsWith(V{i}, '.gz')
                Vgz  = V{i};
                V(i) = gunzip(V(i));
                delete(Vgz)
            end
        end
        V4 = spm_file_merge(V, fullfile(pth, name), varargin{:});
        gzip(V4(1).fname)
        delete(V4(1).fname)
        V4 = spm_vol([V4(1).fname '.gz']);
    case '.nii'
        V4 = spm_file_merge(V, fname, varargin{:});
    otherwise
        error('Unknown file extension %s in %s', ext, fname)
end


% Delete files in V as well as read metafields and delete their json sidecar files (if available)
for n = 1:numel(V)

    % Get the sidecar information
    if isstruct(V)
        niifile = V(n).fname;
    else
        niifile = V{n};
    end
    bfile    = bids.File(niifile);
    jsonfile = spm_file(spm_file(niifile, 'ext',''), 'ext','.json');
    
    % Read the metadata from the first sidecar (if available)
    if n == 1
        metadata   = bfile.metadata;
        metavalues = cell(length(metafields), numel(V));
    end

    % Store the metavalues from the current sidecar (if available)
    for m = 1:length(metafields)
        if isfield(bfile.metadata, metafields{m})
            metavalues{m, n} = bfile.metadata.(metafields{m});
        end
        metadata.(metafields{m}) = metavalues(m,:);
    end

    % Delete the original nifti and json files
    delete(niifile)
    spm_unlink(jsonfile)

end

% Write the output JSON sidecar (if there was at least one input sidecar)
if ~isempty(metadata)
    bids.util.jsonencode(spm_file(spm_file(fname, 'ext',''), 'ext','.json'), metadata);
end

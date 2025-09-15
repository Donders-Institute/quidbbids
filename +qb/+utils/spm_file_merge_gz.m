function V4 = spm_file_merge_gz(V, fname, varargin)
% A wrapper around SPM_FILE_MERGE that writes a .nii or a .nii.gz file. 
%__________________________________________________________________________
%   SPM_FILE_MERGE
%
%   Concatenate 3D volumes into a single 4D volume
%   FORMAT V4 = spm_file_merge(V,fname,dt,RT)
%   V      - images to concatenate (char array or spm_vol struct)
%   fname  - filename for output 4D volume [default: '4D.nii']
%            Unless explicit, output folder is the one containing first image
%   dt     - datatype (see spm_type) [default: 0]
%            0 means same datatype than first input volume
%   RT     - Interscan interval {seconds} [default: NaN]
%   V4     - spm_vol struct of the 4D volume
%  
%   For integer datatypes, the file scale factor is chosen as to maximise
%   the range of admissible values. This may lead to quantization error
%   differences between the input and output images values.

arguments
    V
    fname {mustBeText}
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
                delete(Vgz);
            end
        end
        V4 = spm_file_merge(V, fullfile(pth, name), varargin{:});
        gzip(V4(1).fname)
        delete(V4(1).fname, V{:})
        V4 = spm_vol(V4(1).fname);
    case '.nii'
        V4 = spm_file_merge(V, fname, varargin{:});
    otherwise
        error('Unknown file extension %s in %s', ext, fname)
end

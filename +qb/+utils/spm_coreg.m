function x = spm_coreg(VG, VF, varargin)

% Wrapper function for spm_coreg to avoid float64 -> spm_slice_vol datatype errors

if isfield(VG, 'dat')
    VG.dt(1) = 64;
end
if isfield(VF, 'dat')
    VF.dt(1) = 64;
end

x = spm_coreg(VG, VF, varargin{:});

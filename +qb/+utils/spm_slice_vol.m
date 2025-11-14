function x = spm_slice_vol(V, varargin)

% Wrapper function for spm_slice_vol to avoid float64 datatype errors

if isfield(V, 'dat')
    V.dt(1) = 64;
end

x = spm_slice_vol(V, varargin{:});

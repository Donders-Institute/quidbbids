function Compleximage = load_complex_nii(filemagnitude, filephase)
% function Compleximage = loadcomplex_nii(filemagnitude, filephase)
%
% Load complex nifti image from separate magnitude and phase nifti files. Accounts for Siemens phase scaling.

arguments
    filemagnitude {mustBeText}
    filephase     {mustBeText}
end

Magnitude = spm_vol(char(filemagnitude)).dat();
Phase     = spm_vol(char(filephase)).dat();

phmax = max(Phase(:));
phmin = min(Phase(:));
if (phmin > -4090) && (phmax > 4090)
    Phase = (2*pi/4096) * Phase;  % Siemens scanner may scale from 0 to 4096 (or more, when unwrapped)
elseif (phmin <= -4090) && (phmax > 4090)
    Phase = (pi/4096) * Phase;    % Siemens scanner may also scale from -4096 to 4096 (or more, when unwrapped)
end
if max(abs(Phase(:))) >= 100*pi
    warning('Phase values seem to be out of range (i.e. > 100*pi). Please check %s', filephase);
end

Compleximage = Magnitude .* exp(1i * Phase);

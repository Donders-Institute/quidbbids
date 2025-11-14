function Phase = load_nii_phase(V)
% function Phase = load_nii_phase(V)
%
% Load phase data from nifti file. Accounts for Siemens phase scaling if
% necessary (i.e. when phase values are in range 0-4096 or -4096 to 4096).
%
% Input:
%   V - SPM volume structure or filename of nifti file
%
% Output:
%   Phase - phase data in radians

arguments
    V   {mustBeA(V, {'char', 'string', 'struct'})}
end

if ischar(V) || isstring(V)
    V = qb.utils.spm_vol(char(V));
end

Phase = spm_read_vols(V);
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

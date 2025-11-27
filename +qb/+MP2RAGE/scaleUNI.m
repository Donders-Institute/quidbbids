function UNIT1 = scaleUNI(UNIT1)
% UNIT1 = scaleUNI(UNIT1)
%
%SCALEUNI Scales the input UNIT1 image to the range -0.5 to 0.5 if it is in
% the range 0 to 4095 (as is the case for Siemens DICOM images)
% If the input UNIT1 is already in the range -0.5 to 0.5, it is returned unchanged.
%
% See also: unscaleUNI

% Check the input
minval = min(UNIT1(:));
maxval = max(UNIT1(:));
if minval + 0.5 < 0 || maxval > 4095 + 10   % Added arbitrary margins
    error('QuIDBBIDS:MP2RAGE:ValueError', 'Failed to scale UNIT1 from [0, 4095] to [-0.5, 0.5] -> scale = [%f, %f]', minval, maxval)
end

% Convert MP2RAGE UNIT1 to [-0.5, 0.5] scale - assumes that it is getting only positive values
if minval >= 0 && maxval >= 0.51
    UNIT1 = UNIT1/4095 - 0.5;               % = (UNIT1 - max(UNIT1(:))/2) ./ max(UNIT1(:))
else
    warning('Data already in range [-0.5, 0.5]: [%f, %f]\n', minval, maxval)
end

function UNIT1 = scaleUNI(UNIT1)
% UNIT1 = scaleUNI(UNIT1)
%
%SCALEUNI Scales the input UNIT1 image to the range -0.5 to 0.5 if it is in
% the range 0 to 4095 (as is the case for DICOM images)
% If the input UNIT1 is already in the range -0.5 to 0.5, it is returned unchanged.
%
% See also: unscaleUNI

if min(UNIT1(:)) >= 0 && max(UNIT1(:)) >= 0.51
    % converts MP2RAGE UNIT1 to [-0.5, 0.5] scale - assumes that it is getting only positive values
    UNIT1 = UNIT1/4095 - 0.5;       % = (UNIT1 - max(UNIT1(:))/2) ./ max(UNIT1(:))
end

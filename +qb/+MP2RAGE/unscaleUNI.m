function UNIT1 = unscaleUNI(UNIT1)
% UNIT1 = unscaleUNI(UNIT1)
%
%UNSCALEUNI Scales the input UNIT1 image from the range -0.5 to 0.5 to the
% range 0 to 4095 (as is the case for DICOM images)
% If the input UNIT1 is already in the range 0 to 4095, it is returned unchanged.
%
% See also: scaleUNI

if min(UNIT1(:)) >= -0.51 && max(UNIT1(:)) <= 0.5
    % converts MP2RAGE UNIT1 from [-0.5, 0.5] scale to [0, 4095] scale
    UNIT1 = 4095 * (UNIT1 + 0.5);
end

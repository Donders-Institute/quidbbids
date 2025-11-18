function [T1map, M0map, R1map] = estimateT1M0(UNIT1, INV2, MP2RAGE)
% [T1map, M0map, R1map] = estimateT1M0(UNIT1, MP2RAGE)
%
%T1M0ESTIMATEMP2RAGE Converts MP2RAGE images into T1 map estimates as suggested in:
%   MP2RAGE, a self bias-field corrected sequence for improved segmentation and T 1-mapping at high field
%   JP Marques, T Kober, G Krueger, W van der Zwaag, PF Van de Moortele, R. Gruetter, Neuroimage 49 (2), 1271-1281, 2010
%
%   UNIT1   - The MP2RAGE UNIT1 image
%   INV2    - The MP2RAGE INV2 image with or without Bias Correction
%   MP2RAGE - A structure containing all the relevant sequence information:
%
%     MP2RAGE.TR          = 6;                  % MP2RAGE TR in seconds
%     MP2RAGE.EchoSpacing = 6.7e-3;             % TR of the GRE readout
%     MP2RAGE.TIs         = [800e-3 2700e-3];   % inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
%     MP2RAGE.NumberShots = [40 80];            % Slices Per Slab * [PartialFourierInSlice-0.5  0.5]
%     MP2RAGE.FlipDegrees = [4 5];              % Flip angle of the two readouts in degrees
%     MP2RAGE.InvEff      = 0.96;               % inversion efficiency of the adiabatic inversion pulse
%
% Additionally the inversion efficiency of the adiabatic inversion can be set as a last optional variable. Ideally
% it should be 1. In the first implementation of the MP2RAGE the inversion efficiency was measured to be ~0.96

[Intensity, T1vector, IntensityUncomb] = qb.MP2RAGE.lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NumberShots, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);

% in a first instance the T1 map is computed.
UNIT1 = qb.MP2RAGE.scaleUNI(UNIT1);
T1    = interp1(Intensity, T1vector, UNIT1(:));

% and puts there the T1 estimation
T1map = reshape(T1, size(UNIT1));
R1map = 1./T1map;

T1map(isnan(T1map)) = 0;
R1map(isnan(R1map)) = 0;

% in second moment the M0 map is computed
IntensityUncomb2 = interp1(T1vector, IntensityUncomb(:,2), T1map(:));
M0map = reshape(INV2(:) ./ IntensityUncomb2, size(INV2));

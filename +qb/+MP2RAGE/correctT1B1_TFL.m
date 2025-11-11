function [T1corr, UNIcorr] = correctT1B1_TFL(B1, UNIT1, T1, MP2RAGE, brain)
% [T1corr, UNIcorr] = correctT1B1_TFL(B1, UNIT1, T1, MP2RAGE, brain)
%
% B1 and UNIT1 (and T1) are the nii structures resulting from loading
% the MP2RAGE (UNIT1, T1) and the result of some B1 mapping technique
%
% Only UNIT1 or the T1 have to be loaded (I usually use the UNIT1)
%
% MP2RAGE variable contains all the relevant sequence information as delailed below:
%
% B1 will be given in relative units => 1 if it was correct; values can vary from 0-2
%
%     MP2RAGE.TR          = 6;                  % MP2RAGE TR in seconds
%     MP2RAGE.EchoSpacing = 6.7e-3;             % TR of the GRE readout
%     MP2RAGE.TIs         = [800e-3 2700e-3];   % Inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
%     MP2RAGE.NZslices    = [40 80];            % Slices Per Slab * [PartialFourierInSlice-0.5  0.5]
%     MP2RAGE.FlipDegrees = [4 5];              % Flip angle of the two readouts in degrees
%     MP2RAGE.InvEff      = 0.96;               % Inversion efficiency of the adiabatic inversion pulse
%
% Brain can be an image in the same space as the MP2RAGE that has zeros
% where there is no need to do any T1/B1 calculation (can be a binary mask
% or not). if left empty the calculation is done everywhere
%
% Additionally the inversion efficiency of the adiabatic inversion can be
% set as a last optional variable. Ideally it should be 1.
% In the first implementation of the MP2RAGE the inversino efficiency was
% measured to be ~0.96
%
% Outputs are:
%  T1corr  - T1map corrected for B1 bias
%  UNIcorr - MP2RAGE UNIT1 image corrected for B1 bias
%
% Please cite:
%  Marques, J.P., Gruetter, R., 2013. New Developments and Applications of the MP2RAGE Sequence - Focusing the Contrast and High Spatial Resolution R1 Mapping. PLoS ONE 8. doi:10.1371/journal.pone.0069294
%  Marques, J.P., Kober, T., Krueger, G., van der Zwaag, W., Van de Moortele, P.-F., Gruetter, R., 2010a. MP2RAGE, a self bias-field corrected sequence for improved segmentation and T1-mapping at high field. NeuroImage 49, 1271?1281. doi:10.1016/j.neuroimage.2009.10.002

import qb.MP2RAGE.lookuptable

%% Parse the input arguments
if nargin < 5 || isempty(brain)
    if isempty(UNIT1)
        brain = T1;
    else
        brain = UNIT1;
    end
    brain = ones(size(brain));
end

%% definition of range of B1s and T1s and creation of MP2RAGE lookupvector to make sure the input data for the rest of the code is the UNIT1
[Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);

if isempty(UNIT1)
    UNIT1 = reshape(interp1(T1vector, Intensity, T1(:)), size(B1));    
    UNIT1(isnan(UNIT1)) = -0.5;
else
    UNIT1 = scaleUNI(UNIT1);    % scale UNIT1 to -0.5 to 0.5 range
end

% creates a lookup table of MP2RAGE intensities as a function of B1 and T1
B1_vector = 0.005:0.05:1.9;
T1_vector = 0.5:0.05:5.2;
k = 0;
for b1val = B1_vector    
    k = k + 1;
    [Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, b1val*MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
    MP2RAGEmatrix(k,:)    = interp1(T1vector, Intensity, T1_vector);
end

%% make the matrix MP2RAGEMatrix into T1_matrix(B1, ratio)
MP2RAGE_vector = linspace(-0.5, 0.5, 100);
k = 0;
for b1val = B1_vector
    k = k + 1;
    try
        T1matrix(k,:) = interp1(MP2RAGEmatrix(k,:), T1_vector, MP2RAGE_vector, 'pchip'); 
    catch
        temp              = MP2RAGEmatrix(k,:); 
        temp(isnan(temp)) = linspace(-0.5-eps, -1, sum(isnan(temp(:))));
        temp              = interp1(temp, T1_vector, MP2RAGE_vector);
        T1matrix(k,:)     = temp;       
    end
end

%% correcting the estimates of T1 and B1 iteratively
brain(B1==0)            = 0;
brain(UNIT1==min(UNIT1(:))) = 0;
T1corr                  = UNIT1;
T1corr(brain==0)        = 0;
T1corr(brain==1)        = 0;
T1corr(brain~=0)        = interp2(MP2RAGE_vector, B1_vector, T1matrix, UNIT1(brain~=0), B1(brain~=0));
T1corr(isnan(T1corr))   = 4;  % Set NaN to 4sec: When T1s are very long, you can get some nan out of the lookup table (that happens for some protocols for CSF)

%% creates an UNIcorr image and puts both the B1 and T1 in the ms scale
if nargout > 1
    [Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
    UNIcorr = reshape(interp1(T1vector, Intensity, T1corr(:)), size(T1corr));
    UNIcorr(isnan(UNIcorr)) = -0.5;
    UNIcorr = unscaleUNI(UNIcorr);      % unscale UNIT1 back to 0-4095 range
end

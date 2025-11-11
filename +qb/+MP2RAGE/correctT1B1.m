function [B1corr, T1corr, UNIcorr] = correctT1B1(Sa2RAGEimg, B1img, Sa2RAGE, UNIT1, T1img, MP2RAGE, brain)
% [B1corr, T1corr, UNIcorr] = correctT1B1(Sa2RAGEimg, B1, Sa2RAGE, UNIT1, T1img, MP2RAGE, brain)
%
% You only have to load either the Sa2RAGEimg or the B1img (I usually use the B1 map)
% You only have to load either the UNIT1 or the T1img (I usually use the UNIT1)
%
% MP2rage and Sa2RAGE are variables containing all the relevant sequence information as detailed below:
%    Sa2RAGE.TR          = 2.4;
%    Sa2RAGE.TRFLASH     = 3.1e-3;
%    Sa2RAGE.TIs         = [75e-3 1800e-3];
%    Sa2RAGE.NZslices    = [16+4 16+4];         % Excitations before and after kspace centre
%    Sa2RAGE.FlipDegrees = [4 11];
%    Sa2RAGE.averageT1   = 1.5;
%
%    MP2RAGE.TR          = 6;                   % MP2RAGE TR in seconds 
%    MP2RAGE.EchoSpacing = 6.7e-3;              % TR of the GRE readout
%    MP2RAGE.TIs         = [800e-3 2700e-3];    % Inversion times - time between middle of refocusing pulse and excitatoin of the k-space center encoding
%    MP2RAGE.NZslices    = [40 80];             % Slices Per Slab * [PartialFourierInSlice-0.5  0.5]
%    MP2RAGE.FlipDegrees = [4 5];               % Flip angle of the two readouts in degrees
%    MP2RAGE.InvEff      = 0.96;                % Inversion efficiency of the adiabatic inversion pulse
%
% Brain can be an image in the same space as the MP2RAGE and the
% Sa2RAGE that has zeros where there is no need to do any T1/B1 calculation
% (can be a binary mask or not). if left empty the calculation is done everywhere
%
% Additionally the inversion efficiency of the adiabatic inversion can be
% set as a last optional variable. Ideally it should be 1. 
% In the first implementation of the MP2RAGE the inversino efficiency was 
% measured to be ~0.96
%
% Outputs are:
%  B1corr  - corrected for T1 bias 
%  T1corr  - T1map corrected for B1 bias
%  UNIcorr - MP2RAGE image corrected for B1 bias 
% 
% Please cite:
%  Marques, J.P., Gruetter, R., 2013. New Developments and Applications of the MP2RAGE Sequence - Focusing the Contrast and High Spatial Resolution R1 Mapping. PLoS ONE 8. doi:10.1371/journal.pone.0069294
%  Marques, J.P., Kober, T., Krueger, G., van der Zwaag, W., Van de Moortele, P.-F., Gruetter, R., 2010a. MP2RAGE, a self bias-field corrected sequence for improved segmentation and T1-mapping at high field. NeuroImage 49, 1271?1281. doi:10.1016/j.neuroimage.2009.10.002

import qb.MP2RAGE.lookuptable
import qb.MP2RAGE.Sa2RAGElookuptable

if nargin < 7 || isempty(brain)
    if isempty(UNIT1)
        brain = T1img;
    else
        brain = UNIT1;
    end
    brain = ones(size(brain));
end

if ~isfield(MP2RAGE,'InvEff')
    MP2RAGE.InvEff = 0.99;
end

%% definition of range of B1s and T1s and creation of MP2RAGE and Sa2RAGE lookupvector to make sure the input data for the rest of the code is the Sa2RAGEimg and the UNIT1
[Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
if isempty(UNIT1)
    UNIT1 = reshape(interp1(T1vector, Intensity, T1img(:)), size(B1img));
    UNIT1(isnan(UNIT1)) = -0.5;
else
    UNIT1 = scaleUNI(UNIT1);    % scale UNIT1 to -0.5 to 0.5 range
end

[B1vector, Intensity] = Sa2RAGElookuptable(2, Sa2RAGE.TR, Sa2RAGE.TIs, Sa2RAGE.FlipDegrees, Sa2RAGE.NZslices, Sa2RAGE.TRFLASH, Sa2RAGE.averageT1);
if isempty(Sa2RAGEimg)
    Sa2RAGEimg = reshape(interp1(B1vector, Intensity, B1img(:)), size(B1img));
else
    Sa2RAGEimg = scaleUNI(Sa2RAGEimg) - 0.5;    % scale Sa2RAGE to -1 to 0 range
end

%% create lookup tables of MP2RAGE & Sa2RAGE intensities as a function of B1 and T1
B1_vector = 0.005:0.05:1.9;
T1_vector = 0.5:0.05:5.2;

k = 0;
for b1val = B1_vector
    k = k + 1;
    [Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, b1val*MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
    MP2RAGEmatrix(k,:)    = interp1(T1vector, Intensity, T1_vector);
end

k = 0;
for t1val = T1_vector
    k = k + 1;
    [B1vector, Intensity] = Sa2RAGElookuptable(2, Sa2RAGE.TR, Sa2RAGE.TIs, Sa2RAGE.FlipDegrees, Sa2RAGE.NZslices, Sa2RAGE.TRFLASH, t1val);
    Sa2RAGEmatrix(k,:)    = interp1(B1vector, Intensity, B1_vector);
end

%% make the matrix  Sa2RAGEMatrix into B1_matrix(T1,ratio)
npoints = 100;
Sa2RAGE_vector = linspace(min(Sa2RAGEmatrix(:)), max(Sa2RAGEmatrix(:)), npoints);
k = 0;
for t1val = T1_vector
    k = k + 1;
    try
        B1matrix(k,:) = interp1(Sa2RAGEmatrix(k,:), B1_vector, Sa2RAGE_vector, 'pchip');
    catch
        B1matrix(k,:) = 0;
    end
end

%% make the matrix  MP2RAGEMatrix into T1_matrix(B1, ratio)
MP2RAGE_vector = linspace(-0.5, 0.5, npoints);
k = 0;
for b1val = B1_vector
    k = k + 1;
    try
        T1matrix(k,:) = interp1(MP2RAGEmatrix(k,:), T1_vector, MP2RAGE_vector, 'pchip');
    catch
        temp              = MP2RAGEmatrix(k,:);
        temp(isnan(temp)) = linspace(-0.5 - eps, -1, length(find(isnan(temp))));
        temp              = interp1(temp, T1_vector, MP2RAGE_vector);
        T1matrix(k,:)     = temp;
    end
end

%% correcting the estimates of T1 and B1 iteratively
brain(Sa2RAGEimg==0)          = 0;
brain(UNIT1==min(UNIT1(:)))   = 0;
T1corr(brain==0)              = 0;
T1corr(brain==1)              = 1.5;
B1corr(brain==0)              = 0;
Sa2RAGEimg(isnan(Sa2RAGEimg)) = -0.5;
for k = 1:3
    B1corr(brain~=0)      = interp2(Sa2RAGE_vector, T1_vector, B1matrix, Sa2RAGEimg(brain~=0), T1corr(brain~=0));
    B1corr(isnan(B1corr)) = 2;        
    T1corr(brain~=0)      = interp2(MP2RAGE_vector, B1_vector, T1matrix, UNIT1(brain~=0), B1corr(brain~=0));
    T1corr(isnan(T1corr)) = 4;
end

%% creates an UNIcorr image and puts both the B1 and T1 in the ms scale
[Intensity, T1vector] = lookuptable(2, MP2RAGE.TR, MP2RAGE.TIs, MP2RAGE.FlipDegrees, MP2RAGE.NZslices, MP2RAGE.EchoSpacing, 'normal', MP2RAGE.InvEff);
UNIcorr = reshape(interp1(T1vector, Intensity, T1corr(:)), size(T1corr));
UNIcorr(isnan(UNIcorr)) = -0.5;
UNIcorr = unscale(UNIcorr);     % unscale MP2RAGE back to 0-4095 range

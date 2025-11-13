function [Intensity, T1vector, IntensityBeforeComb] = lookuptable(nimages, MPRAGE_tr, invtimesAB, flipangleABdegree, nZslices, FLASH_tr, sequence, InvEff, alldata)
% MP2RAGE_LOOKUPTABLE creates a lookup table for MP2RAGE sequences
%
% [Intensity, T1vector, IntensityBeforeComb] = lookuptable(nimages, MPRAGE_tr, invtimesAB, flipangleABdegree, nZslices, FLASH_tr, sequence, [InvEff], [alldata])
%
% alldata == 1 -> all data is shown
% alldata == 0 -> only the monotonic part is shown

import qb.MP2RAGE.estimateMPRAGE

if nargin < 9 || isempty(alldata)
    alldata = 0;
end
if nargin < 8
    InvEff = [];
end

invtimesa  = invtimesAB(1);
invtimesb  = invtimesAB(2);
flipanglea = flipangleABdegree(1);
flipangleb = flipangleABdegree(2);
B1vector   = 1;
T1vector   = 0.05:0.05:5;

if length(nZslices) == 2
    nZ_bef    = nZslices(1);
    nZ_aft    = nZslices(2);
    nZslices2 = nZslices;
    nZslices  = sum(nZslices);
elseif length(nZslices) == 1
    nZ_bef    = nZslices/2;
    nZ_aft    = nZslices/2;
    nZslices2 = nZslices;
end

for n = 1:length(T1vector)
    for MPRAGEtr = MPRAGE_tr
        for inversiontimesa = invtimesa
            for inversiontimesb = invtimesb
                for m = 1:length(B1vector)
                    inversiontimes2 = [inversiontimesa inversiontimesb];
                    if (diff(inversiontimes2) >= nZslices*FLASH_tr) && (inversiontimesa >= nZ_bef*FLASH_tr) && (inversiontimesb <= MPRAGEtr-nZ_aft*FLASH_tr)
                        Signal(n,m,1:2) = estimateMPRAGE(nimages, MPRAGEtr, inversiontimes2, nZslices2, FLASH_tr, B1vector(m)*[flipanglea flipangleb], sequence, T1vector(n), InvEff);
                    else
                        Signal(n,m,1:2) = 0;
                    end
                end
            end
        end
    end
end
Intensity = squeeze(real(Signal(:,:,1) .* conj(Signal(:,:,2))) ./ (abs(Signal(:,:,1)).^2 + abs(Signal(:,:,2)).^2));
T1vector  = squeeze(T1vector);
if alldata==0
    [~, minindex]       = max(Intensity);
    [~, maxindex]       = min(Intensity);
    Intensity           = Intensity(minindex:maxindex);
    T1vector            = T1vector(minindex:maxindex);
    IntensityBeforeComb = squeeze(Signal(minindex:maxindex,1,:));
    Intensity([1 end])  = [0.5 -0.5];   % pads the look up table to avoid points that fall out of the lookuptable
else
    Intensity           = squeeze(real(Signal(:,:,1) .* conj(Signal(:,:,2))) ./ (abs(Signal(:,:,1)).^2 + abs(Signal(:,:,2)).^2));
    IntensityBeforeComb = squeeze(Signal(:,1,:));
end

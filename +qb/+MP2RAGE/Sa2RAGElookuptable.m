function [B1, Intensity, Signal] = Sa2RAGElookuptable(nimage, MPRAGE_tr, invtimesAB, flipangleABdegree, nZslices, FLASH_tr, T1average)
% [B1, Intensity, Signal] = Sa2RAGElookuptable(nimage, MPRAGE_tr, invtimesAB, flipangleABdegree, nZslices, FLASH_tr, [T1average])

% size(varargin,2)
if nargin < 7 || isempty(T1average)
    T1average = 1.5;
end

B1 = 0.005:0.005:2.5;

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

for m = 1:length(B1)
    if (diff(invtimesAB) >= nZslices*FLASH_tr) && (invtimesAB(1) >= nZ_bef*FLASH_tr) && (invtimesAB(2) <= MPRAGE_tr-nZ_aft*FLASH_tr)
        Signal(m,1:2) = estimateMPRAGE(nimage, MPRAGE_tr, invtimesAB, nZslices2, FLASH_tr, B1(m)*flipangleABdegree, 'normal', T1average, -cos(B1(m)*pi/2));
    else
        Signal(m,1:2) = 0;
    end
end

Intensity = squeeze(real(Signal(:,1)) ./ real(Signal(:,2)));

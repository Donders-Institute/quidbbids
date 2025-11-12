function [INV1final, INV2final] = correctINV1INV2(INV1, INV2, UNIT1, CorrectBoth)
% function [INV1final, INV2final] = correctINV1INV2(INV1, INV2, UNIT1, [CorrectBoth])

if nargin < 4 || isempty(CorrectBoth)
    CorrectBoth = 0;
end

% scale UNIT1 to -0.5 to 0.5 range
UNIT1 = qb.MP2RAGE.scaleUNI(UNIT1);

%% Compute correct INV1 & INV2 datasets by using the phase sensitivity information available on the UNIT1 image
rootsquares_pos = @(a, b, c)(-b + sqrt(b.^2 - 4*a.*c)) ./ (2*a);
rootsquares_neg = @(a, b, c)(-b - sqrt(b.^2 - 4*a.*c)) ./ (2*a);

% Gives the correct polarity to INV1
INV1 = sign(UNIT1) .* INV1;

% Because the MP2RAGE INV1 and INV2 is a summ of squares data, while the
% UNIT1 is a phase sensitive coil combination.. some more maths has to
% be performed to get a better INV2 and INV1 estimate, which here is done by assuming
% both the bigger value at any pixel will be the closest approximations to a phase sensitive combination

INV1pos = rootsquares_pos(-UNIT1, INV2, -INV2.^2 .* UNIT1);
INV1neg = rootsquares_neg(-UNIT1, INV2, -INV2.^2 .* UNIT1);

INV2pos = rootsquares_pos(-UNIT1, INV1, -INV1.^2 .* UNIT1);
INV2neg = rootsquares_neg(-UNIT1, INV1, -INV1.^2 .* UNIT1);

INV1final = INV1;
INV2final = INV2;

if CorrectBoth == 1
    % making the correction when INV2>abs(INV1)
    INV1final(abs(INV1-INV1pos) >  abs(INV1-INV1neg)) = INV1neg(abs(INV1-INV1pos) >  abs(INV1-INV1neg));
    INV1final(abs(INV1-INV1pos) <= abs(INV1-INV1neg)) = INV1pos(abs(INV1-INV1pos) <= abs(INV1-INV1neg));

    % making the correction when abs(INV1)>INV2
    INV2final(abs(INV2-INV2pos) >  abs(INV2-INV2neg)) = INV2neg(abs(INV2-INV2pos) >  abs(INV2-INV2neg));
    INV2final(abs(INV2-INV2pos) <= abs(INV2-INV2neg)) = INV2pos(abs(INV2-INV2pos) <= abs(INV2-INV2neg));

    % reinforce the polarity
    INV2final = abs(INV2final);
    INV1final = sign(UNIT1) .* abs(INV1final);

elseif CorrectBoth == 0

    INV1final(abs(INV1-INV1pos) >  abs(INV1-INV1neg)) = INV1neg(abs(INV1-INV1pos) >  abs(INV1-INV1neg));
    INV1final(abs(INV1-INV1pos) <= abs(INV1-INV1neg)) = INV1pos(abs(INV1-INV1pos) <= abs(INV1-INV1neg));

else
    % currently the only condition is that the difference is smaller, but no requirement is made on the polarity being respected:
    % equal to the positive if closer and polarity is respected
    % equal to the negative if closer and polarity is respected
    INV1final(and(abs(INV1-INV1pos) >  abs(INV1-INV1neg), INV1neg.*INV1 > 0)) = INV1neg(and(abs(INV1-INV1pos) >  abs(INV1-INV1neg), INV1neg.*INV1 > 0));
    INV1final(and(abs(INV1-INV1pos) <= abs(INV1-INV1neg), INV1neg.*INV1 > 0)) = INV1pos(and(abs(INV1-INV1pos) <= abs(INV1-INV1neg), INV1neg.*INV1 > 0));
end

% only applies the correction if one of the images has less than 60 % of the SNR of the higher SNR image
INV1final(abs(INV1) >  abs(0.6 * INV2)) = INV1(abs(INV1) >  abs(0.6 * INV2));
INV2final(abs(INV2) >= abs(0.6 * INV1)) = INV2(abs(INV2) >= abs(0.6 * INV1));

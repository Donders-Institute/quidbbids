function [V, Y] = reorient2std(V, Y)
% Reorient an image to standard (MNI-style) orientation, like fslreorient2std.
%
% Only 0, 90, 180 or 270 degree rotations (axis permutations and flips) are
% applied - no reslicing. The voxel-to-world affine V.mat (the sform if
% sform_code > 0, otherwise the qform, as in spm_vol) determines the world
% axis that each voxel axis points along (largest element of the
% corresponding column, as in nifti_mat44_to_orientation). The axes are then
% permuted/flipped so that they point in the directions of the MNI152 standard
% template: P->A and I->S, and L->R or R->L depending on the sign of the
% determinant (fslreorient2std calls fslswapdim with "LR PA IS", or "RL PA IS"
% for a negative determinant, i.e. radiological storage). The affine is
% updated such that every voxel keeps its world coordinates.
%
% Usage:
%   [V, Y] = reorient2std(V, Y)
%
% Inputs:
%   V - Volume structure (see spm_vol) with fields mat and dim. For 4D/5D
%       images, spm_vol returns a struct array; since a NIfTI file stores a
%       single affine (sform/qform) for all volumes, the reorientation is
%       computed from the first element and applied to all elements (they
%       share the same voxel grid, e.g. after file_merge)
%   Y - Image 3D/4D/5D data array
%
% Outputs:
%   V - Volume structure(s) with updated mat and dim fields
%   Y - Reoriented data array

% World axis (row) and direction that each voxel axis (column) points along
R       = V(1).mat(1:3, 1:3);
[~, ax] = max(abs(R), [], 1);
dir     = sign(R(sub2ind(size(R), ax, 1:3)));

% Target world directions: P->A (+y) and I->S (+z), and L->R (+x) or R->L (-x)
% for a negative determinant (radiological convention, as in fslreorient2std)
t = [1 1 1];
if det(R) < 0
    t(1) = -1;
end

% New axis p takes the old voxel axis pointing along world axis p, flipped if
% needed so that it points in the target world direction
perm = zeros(1, 3);
sgn  = ones(1, 3);
for p = 1:3
    k       = find(ax == p, 1);
    perm(p) = k;
    sgn(p)  = t(p) * dir(k);
end

% Permute and flip the data (first three dimensions only)
Y = permute(Y, [perm 4:ndims(Y)]);
for p = 1:3
    if sgn(p) < 0
        Y = flip(Y, p);
    end
end

% Update the affine: old voxel coords = P * new voxel coords + c (1-based
% voxel coordinates, as in V.mat), where c keeps flipped axes in place
P = zeros(3);
c = zeros(3, 1);
for p = 1:3
    P(perm(p), p) = sgn(p);
    if sgn(p) < 0
        c(perm(p)) = V(1).dim(perm(p)) + 1;
    end
end
T = [P c; 0 0 0 1];
for i = 1:numel(V)
    V(i).mat = V(i).mat * T;
    V(i).dim = V(i).dim(perm);
end

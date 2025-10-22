restoredefaultpath
addpath(genpath(fullfile('dependencies','despot1')))
addpath(fullfile('dependencies','sepia'))
addpath(fullfile('dependencies','spm'))
addpath(fullfile('dependencies','matlab-toml'))
addpath(fullfile('dependencies','bids-matlab'))
sepia_addpath

if isunix
    bids_dir  = '/home/mrphys/marzwi/MWI/bidsPhilipsVariants_copy';
else
    bids_dir  = 'P:\3055010.04\RunningProjects\MyelinWaterImaging\bidsPhilipsVariants_copy';
end
quidb     = qb.QuIDBBIDS(bids_dir)
mgr       = quidb.manager(["Chimap", "R2starmap", "FW_R1map"])
% mgr.force = true;
mgr.start_workflow()

classdef R1R2sWorker < qb.workers.Worker
%R1R2SWORKER Runs MCR workflow
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (GetAccess = public, SetAccess = protected)
    description = ["I'm R2-D2, an astromech droid that can fix starships and, yes, generate precise R1- and R2-starmaps for all your neuro-navigation needs!";
                   "";
                   "Methods:"
                   "- Gacelle et al., MRM 2020 for R2-star mapping from multi-echo GRE data"]
    needs       = ["echos4Dmag", "TB1map_GRE", "brainmask"]   % List of workitems the worker needs. Workitems can contain regexp patterns. TODO: Ask Jose which mask to use
    usesGPU     = true
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Subclass-specific initialization hook called by the base constructor. This method allows 
        % subclasses to perform additional setup after the common Worker properties have been initialized.

        % Construct the bidsfilters
        obj.bidsfilter.R2starmap = struct('modality', 'anat', ...
                                          'echo', [], ...
                                          'part', '', ...
                                          'desc', 'gacelleR1R2s', ...
                                          'suffix', 'R2starmap');
        obj.bidsfilter.M0map     = setfield(obj.bidsfilter.R2starmap, 'suffix','M0Map');
        obj.bidsfilter.R1map     = setfield(obj.bidsfilter.R2starmap, 'suffix','R1map');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        import qb.utils.spm_write_vol_gz
        import qb.utils.spm_vol

        % Get the workitems we need from a colleague
        echos4Dmag = obj.ask_team('echos4Dmag');    % Multiple FA-images per run
        TB1map_GRE = obj.ask_team('TB1map_GRE');    % Single image per run
        brainmask  = obj.ask_team('brainmask');     % Multiple FA-images per run

        % Check the number of items we got: TODO: FIXME: multi-run acquisitions
        if length(echos4Dmag) < 2
            obj.logger.exception('%s received data for only %d flip angles', obj.name, length(echos4Dmag))
        end
        if length(TB1map_GRE) ~= 1          % TODO: Figure out which run/protocol to take (use IntendedFor or the average or so?)
            obj.logger.exception('%s expected only one B1map file but got: %s', obj.name, sprintf('%s ', TB1map_GRE{:}))
        end
        if length(brainmask) ~= 1           % TODO: FIXME
            obj.logger.exception('%s expected one brainmask but got:%s', obj.name, sprintf(' %s', brainmask{:}))
        end

        % Load the data + metadata
        V    = spm_vol(echos4Dmag{1});                          % For reading the 3D image dimensions
        dims = [V(1).dim length(V) length(echos4Dmag)];
        img  = NaN(dims);
        for n = 1:dims(5)
            img(:,:,:,:,n) = spm_read_vols(spm_vol(echos4Dmag{n}));
            bfile          = bids.File(echos4Dmag{n});          % For reading metadata, parsing entities, etc
            FA(n)          = bfile.metadata.FlipAngle;
        end
        mask = spm_read_vols(spm_vol(char(brainmask))) & all(~isnan(img), [4 5]);
        B1   = spm_read_vols(spm_vol(char(TB1map_GRE)));
        TR   = bfile.metadata.RepetitionTime;
        TE   = bfile.metadata.EchoTime;

        % Estimate the MCR model
        extraData     = [];
        extraData.b1  = single(B1);
        objGPU        = gpuJointR1R2starMapping(TE, TR, FA);
        askadam_R1R2s = objGPU.estimate(img, mask, extraData, obj.config.R1R2sWorker.fitting.GPU);  % TODO: Is single() needed/desired?

        % Save the output data
        V(1).dim = dims(1:3);
        spm_write_vol_gz(V(1), askadam_R1R2s.final.R1,     obj.bfile_set(bfile, obj.bidsfilter.R1map    ).path);
        spm_write_vol_gz(V(1), askadam_R1R2s.final.M0,     obj.bfile_set(bfile, obj.bidsfilter.M0map    ).path);
        spm_write_vol_gz(V(1), askadam_R1R2s.final.R2star, obj.bfile_set(bfile, obj.bidsfilter.R2starmap).path);
    end

end

end

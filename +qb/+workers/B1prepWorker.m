classdef B1prepWorker < qb.workers.Worker
%B1PREPWORKER Performs preprocessing to produce workitems that can be used by other workers
%
% See also: qb.workers.Worker (for base interface), qb.QuIDBBIDS (for overview)


properties (GetAccess = public, SetAccess = protected)
    name        = "Yoda"        % Display name of the worker
    description = ["I am a modest worker that fabricates regularized flip-angle maps in degrees (ready for the big B1-correction party!)"] % Description of the work that is done
    version     = "0.1.0"       % The version of B1prepWorker
    needs       = []            % List of workitems the worker needs. Workitems can contain regexp patterns
end


methods (Access = protected)

    function initialize(obj)
        %INITIALIZE Performs any subclass-specific construction steps

        % Construct the bidsfilters
        obj.bidsfilter.rawTB1map_famp = setfields(obj.config.General.BIDS.include, 'modality','fmap', 'acq','famp');
        obj.bidsfilter.rawTB1map_anat = setfields(obj.bidsfilter.rawTB1map_famp, 'acq','anat');
        obj.bidsfilter.TB1map_angle   = setfields(obj.bidsfilter.rawTB1map_famp, 'desc','corrected', 'space','raw', 'suffix','TB1map');
        obj.bidsfilter.TB1map_anat    = setfields(obj.bidsfilter.TB1map_angle, 'acq','anat');
    end

end


methods

    function get_work_done(obj, workitem)
        %GET_WORK_DONE Does the work to produce the WORKITEM and recruits other workers as needed

        arguments (Input)
            obj
            workitem {mustBeTextScalar, mustBeNonempty}
        end

        import qb.utils.spm_vol

        % Get the B1 anat and fa-map images
        B1famp = obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawTB1map_famp);
        B1anat = obj.query_ses(obj.BIDS, 'data', obj.bidsfilter.rawTB1map_anat);    % NB: Assumes the order is the same as for B1famp
        if length(B1anat) ~= length(B1famp)
            obj.logger.warning('Unexpected number of B1-files found: acq-anat=%d vs acq-famp=%d', length(B1anat), length(B1famp))
        end

        for n = 1:length(B1famp)

            % Load the FA-map
            bfile = bids.File(B1famp{n});
            FAVol = spm_vol(B1famp{n});
            FA    = spm_read_vols(FAVol);
            if isfield(obj.config.B1prepWorker.FAscaling, bfile.metadata.Manufacturer)
                FA = FA / obj.config.B1prepWorker.FAscaling.(bfile.metadata.Manufacturer);  % Scale to radians
            end

            % Regularize the FA-map in order to avoid influence of salt & pepper border noise
            if ~isempty(B1anat) && obj.config.B1prepWorker.FWHM ~= 0
                dim = spm_imatrix(FAVol.mat);
                FA  = spm_read_vols(spm_vol(B1anat{n})) .* exp(1i*FA);                              % Make complex and multiply with anat to avoid smoothing skull-noise across tissue borders
                FA  = angle(qb.MP2RAGE.smooth3D(FA, obj.config.B1prepWorker.FWHM, abs(dim(7:9))));  % Smooth and take angle again
            end

            % Save the FA-map image & json file
            bfile = obj.bfile_set(bfile, obj.bidsfilter.TB1map_angle);
            obj.logger.info("--> Saving regularized B1-map: %s", bfile.filename)
            qb.utils.spm_write_vol_gz(FAVol, FA, bfile.path);
            bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)

            % Copy the anat image & json file
            if ~isempty(B1anat)
                bfile = obj.bfile_set(B1anat{n}, obj.bidsfilter.TB1map_anat);
                copyfile(B1anat{n}, bfile.path);
                bids.util.jsonencode(replace(bfile.path, bfile.filename, bfile.json_filename), bfile.metadata)
            end

        end
    end

end

end

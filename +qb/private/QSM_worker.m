function QSM_worker(obj, subjects)
% Method implementation for running QSM and R2-star workflows - Entry point is in qb.QuIDBBIDS.m

arguments
    obj      qb.QuIDBBIDS
    subjects (1,:) struct        % 1×N struct array allowed
end

import qb.utils.spm_file_merge_gz

% Index the outputdir layout
Output = bids.layout(char(obj.outputdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all subjects
for subject = subjects

    if isempty(subject.anat) || isempty(subject.fmap)
        continue
    end
    fprintf("\n==> Processing: %s\n", subject.path)

    % Process all runs independently
    anat = {'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE'};
    for run = bids.query(Output, 'runs', anat{:}, 'desc','^FA\d*$', 'echo',[], 'part','mag')

        % Get the 4D mag/phase images and brainmask for this run (NB: keep queries in sync with preproc_worker.m)
        magfiles   = bids.query(Output, 'data', anat{:}, 'run',run{1}, 'desc','^FA\d*$', 'echo',[], 'part','mag');
        phasefiles = bids.query(Output, 'data', anat{:}, 'run',run{1}, 'desc','^FA\d*$', 'echo',[], 'part','phase');
        mask       = bids.query(Output, 'data', anat{:}, 'run',run{1}, 'desc','minimal', 'label','brain', 'suffix','mask');
        if isempty(magfiles) || (length(magfiles) ~= length(phasefiles))
            error("No unique pre-processed 4D mag/phase images found in: %s", subject.path);
        end
        if length(mask) ~= 1
            error("No single pre-processed brain mask found in: %s", subject.path);
        end

        % Run SEPIA QSM workflows for each flip angle
        for n = 1:length(magfiles)

            % Create a SEPIA header file
            clear input
            input.nifti         = magfiles{n};                                                  % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
            input.TEFileList    = spm_file(spm_file(magfiles(n), 'ext',''), 'ext','.json');     % Override TE with the array from the mag nifti json sidecar file
            bfile               = bids.File(input.nifti);
            bfile.entities.part = '';
            bfile.suffix        = '';
            fparts              = split(bfile.filename, '.');                                   % Split filename extensions to parse the basename
            output              = fullfile(char(obj.workdir), bfile.bids_path, fparts{1});      % Output path. N.B: SEPIA will interpret the last part of the path as a file-prefix
            save_sepia_header(input, struct('TE', bfile.metadata.EchoTime), output)

            % Run the SEPIA QSM workflow
            clear input
            input(1).name = phasefiles{n};
            input(2).name = magfiles{n};
            input(3).name = '';
            input(4).name = [output '_header.mat'];
            fprintf("\n--> Running SEPIA QSM workflow for %s/%s (run-%s)\n", subject.name, subject.session, run{1})
            sepiaIO(input, output, mask{1}, obj.config.QSM.QSMParam)

            % Run the SEPIA R2-star workflow. TODO: Split of in a separate worker
            fprintf("\n--> Running SEPIA R2-star workflow for %s/%s (run-%s)\n", subject.name, subject.session, run{1})
            sepiaIO(input, output, mask{1}, obj.config.QSM.R2starParam)

            % TODO: Rename/copy all files of interest to become BIDS valid, create sidecar files for them and move them over to obj.outputdir

        end

    end

end

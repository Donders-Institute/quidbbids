function SEPIA_worker(obj, subjects)
% Method implementation for running SEPIA QSM and R2-star pipelines - Entry point is in qb.QuIDBBIDS.m

arguments
    obj         qb.QuIDBBIDS
    subjects    (1,:) struct        % 1×N struct array allowed
end

import qb.utils.spm_file_merge_gz

% (Re)index the workdir layout
BIDS_prep = bids.layout(char(obj.workdir), 'use_schema',false, 'index_derivatives',false, 'index_dependencies',false, 'tolerant',true, 'verbose',false);

% Process all subjects
for subject = subjects

    if isempty(subject.anat) || isempty(subject.fmap)
        continue
    end
    fprintf("\n==> Processing: %s\n", subject.path)

    % Process all runs independently
    for run = bids.query(BIDS_prep, 'runs', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE')

        % Get the 4D mag/phase images and brainmask for this run (see / keep in sync with preproc_worker.m)
        magfiles   = bids.query(BIDS_prep, 'data', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'run',run{1}, 'desc','^FA\d*$', 'echo',[], 'part','mag');
        phasefiles = bids.query(BIDS_prep, 'data', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'run',run{1}, 'desc','^FA\d*$', 'echo',[], 'part','phase');
        mask       = bids.query(BIDS_prep, 'data', 'sub',subject.name, 'ses',subject.session, 'modality','anat', 'space','withinGRE', 'run',run{1}, 'desc','minimal', 'label','brain', 'suffix','mask');
        if isempty(magfiles) || (length(magfiles) ~= length(phasefiles))
            error("No unique 4D mag/phase images found in: %s", subject.path);
        end
        if length(mask) ~= 1
            error("No single brain mask found in: %s", subject.path);
        end

        % Run the SEPIA pipelines for each flip angle
        for n = 1:length(magfiles)

            % Create a SEPIA header file
            clear input
            input.nifti         = magfiles{n};                                                                  % For extracting B0 direction, voxel size, matrix size (only the first 3 dimensions)
            input.TEFileList    = spm_file(spm_file(magfiles(n), 'ext',''), 'ext','.json');                     % Override TE with the array from the mag nifti json sidecar file
            bfile               = bids.File(input.nifti);
            bfile.entities.part = '';
            bfile.suffix        = '';
            fparts              = split(bfile.filename, '.');                                                   % Split filename extensions to parse the basename
            output              = fullfile(char(fileparts(obj.derivdir)), 'SEPIA', bfile.bids_path, fparts{1}); % Output directory. N.B: SEPIA will interpret the last part of the path as a file-prefix
            save_sepia_header(input, struct('TE', bfile.metadata.EchoTime), output)

            % Run the SEPIA QSM pipeline
            clear input
            input(1).name = phasefiles{n};
            input(2).name = magfiles{n};
            input(3).name = '';
            input(4).name = [output '_header.mat'];
            fprintf("\n--> Running SEPIA QSM pipeline for %s/%s (run-%s)\n", subject.name, subject.session, run{1})
            sepiaIO(input, output, mask{1}, obj.config.SEPIA.QSMParam)

            % Run the SEPIA R2-star pipeline
            fprintf("\n--> Running SEPIA R2-star pipeline for %s/%s (run-%s)\n", subject.name, subject.session, run{1})
            sepiaIO(input, output, mask{1}, obj.config.SEPIA.R2starParam)

        end

    end

end

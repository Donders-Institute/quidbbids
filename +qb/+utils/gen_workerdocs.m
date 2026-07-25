function gen_workerdocs()
    % GEN_WORKERDOCS Generate RST documentation for all workers in +qb/+workers/
    %
    % Usage:
    %   gen_workerdocs()

    % Find all Worker files 
    worker_dir  = fileparts(which("qb.workers.Worker"));
    output_file = fullfile(fileparts(fileparts(worker_dir)), "docs", "workers.rst");

    % Create minimal BIDS and config for worker instantiation
    BIDS.pth = pwd;
    config = struct();
    config.General.BIDS.include = struct('suffix', {{''}}, 'modality', {{''}}, 'acq', {{''}});
    
    % Get all worker resumes (replicate Coordinator.get_resumes logic without creating derivatives)
    resumes = struct();
    for wfile = dir(fullfile(worker_dir, "*Worker*.m"))'
        if strcmp(wfile.name, 'Worker.m')
            continue  % Exclude the abstract Worker class
        end
        if endsWith(wfile.folder, '+workers')
            worker = qb.workers.(erase(wfile.name, '.m'))(BIDS, struct('name','','session',''), config);
        else
            worker = feval(erase(wfile.name, '.m'), BIDS, struct('name','','session',''), config);
        end
        resumes.(worker.name).handle = str2func(class(worker));
        resumes.(worker.name).name = worker.name;
        resumes.(worker.name).description = worker.description;
        resumes.(worker.name).makes = worker.makes();
        resumes.(worker.name).needs = worker.needs(:)';
        resumes.(worker.name).usesGPU = worker.usesGPU;
    end

    % Write header
    fid = fopen(output_file, 'w', 'n', 'UTF-8');
    fprintf(fid, 'Workers\n');
    fprintf(fid, '=======\n\n');
    fprintf(fid, 'This section describes all available workers in QuIDBBIDS.\n\n');

    % For each worker write an entry using the resume data from Coordinator
    for name = string(fieldnames(resumes))'
        resume = resumes.(name);

        % Write worker header
        fprintf(fid, '%s\n', name);
        fprintf(fid, '%s\n\n', repmat('~', 1, strlength(name)));

        % Format description (string array to paragraphs)
        for line = resume.description
            fprintf(fid, '%s\n', line);
        end
        fprintf(fid, '\n');

        % Format properties as list table
        fprintf(fid, 'Properties\n');
        fprintf(fid, '----------\n\n');
        fprintf(fid, '.. list-table::\n');
        fprintf(fid, '   :header-rows: 1\n');
        fprintf(fid, '   :widths: 25 75\n\n');
        fprintf(fid, '   - - Property\n');
        fprintf(fid, '     - Value\n');

        % Add properties from resume
        fprintf(fid, '   - - ``needs``\n');
        fprintf(fid, '     - %s\n', strjoin(resume.needs, ', '));
        fprintf(fid, '   - - ``makes``\n');
        fprintf(fid, '     - %s\n', strjoin(resume.makes, ', '));
        fprintf(fid, '   - - ``usesGPU``\n');
        fprintf(fid, '     - %s\n', string(resume.usesGPU));

        fprintf(fid, '\n');
    end

    fclose(fid);
    fprintf('Writing worker documentation to: %s\n', output_file)
end

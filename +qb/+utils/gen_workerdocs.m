function gen_workerdocs()
% GEN_WORKERDOCS Generate RST documentation for all workers in +qb/+workers/
%
% Usage:
%   gen_workerdocs()

% Find all Worker files 
worker_dir  = fileparts(which("qb.workers.Worker"));
output_file = fullfile(fileparts(fileparts(worker_dir)), "docs", "workers.rst");

% Create minimal BIDS and read the default config for worker instantiation
BIDS.pth = pwd;
config   = qb.utils.jsondecode(fileread(qb.resetconfig(false)));

% Write header
fid = fopen(output_file, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Workers\n');
fprintf(fid, '=======\n\n');
fprintf(fid, 'This section describes all available workers in QuIDBBIDS. Workers are used to process BIDS\n');
fprintf(fid, 'data and make workitems (output products) in a peer-to-peer network, orchestrated by the\n');
fprintf(fid, 'QuIDBBIDS manager.\n\n');

% For each worker write an entry using the class properties
for wfile = dir(fullfile(worker_dir, "*Worker*.m"))'
    if strcmp(wfile.name, 'Worker.m') || startsWith(wfile.name, '.')  % Exclude the abstract Worker class and hidden files
        continue
    end
    if endsWith(wfile.folder, '+workers')
        worker = qb.workers.(erase(wfile.name, '.m'))(BIDS, struct('name','','session',''), config);
    else
        worker = feval(erase(wfile.name, '.m'), BIDS, struct('name','','session',''), config);
    end

    % Write worker header
    fprintf(fid, '%s\n', worker.name);
    fprintf(fid, '%s\n\n', repmat('~', 1, strlength(worker.name)));

    % Add class description (already formatted in ReStructuredText)
    fprintf(fid, '%s\n', worker.description{:}, '');

    % Add remaining class properties as a list table
    fprintf(fid, 'Properties\n');
    fprintf(fid, '----------\n\n');
    fprintf(fid, '.. list-table::\n');
    fprintf(fid, '   :widths: 25 75\n\n');
    fprintf(fid, '   - - ``needs``\n');
    fprintf(fid, '     - %s\n', strjoin(worker.needs, ', '));
    fprintf(fid, '   - - ``makes``\n');
    fprintf(fid, '     - %s\n', strjoin(worker.makes(), ', '));
    fprintf(fid, '   - - ``usesGPU``\n');
    fprintf(fid, '     - %s\n\n', string(worker.usesGPU));

end

disp("Writing worker documentation to: " + output_file)

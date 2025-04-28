function ver = version()
    % VERSION() returns the SemVer string for QuIDBBIDS
    
    % Read and parse the version from the mpackage JSON file
    jsonfile = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'resources', 'mpackage.json');
    if exist(jsonfile, 'file')
        ver = jsondecode(fileread(jsonfile)).version;
    else
        error(['The file "' jsonfile '"does not exist']);
    end

end

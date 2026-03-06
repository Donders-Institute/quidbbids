function ver = version()
    % VERSION Returns the SemVer string for QuIDBBIDS

    % Read and parse the version from the mpackage JSON file
    jsonfile = fullfile(fileparts(fileparts(mfilename("fullpath"))), "package.json");
    if exist(jsonfile, "file")
        ver = jsondecode(fileread(jsonfile)).version;
    else
        warning("QuIDBBIDS:Setup:MissingMPackage", "The file '%s' does not exist", jsonfile)
        ver = '';
    end

end

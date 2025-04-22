function ver = version()
    % VERSION() returns the SemVer string for QuIDBBIDS
    
    p   = fileparts(mfilename('fullpath'));
    ver = strtrim(fileread(fullfile(p, 'VERSION.txt')));

end

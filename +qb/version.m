function [v, b] = version()
    % VERSION() returns the SemVer string for QuIDBBIDS and BIDS

    p = fileparts(mfilename('fullpath'));
    v = strtrim(fileread(fullfile(p, 'VERSION.txt')));       % The QuIDBBIDS version - Update via CI or manually
    b = strtrim(fileread(fullfile(p, 'BIDSVERSION.txt')));   % The BIDS version      - Update via CI or manually

end

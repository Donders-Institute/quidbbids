function [ver, latest] = version()
    % VERSION Returns the SemVer string of the installed codebase as well as of the latest GitHub release
    %
    % [VER, LATEST] = VERSION()

    % Read and parse the version from the project JSON file
    jsonfile = fullfile(fileparts(fileparts(mfilename("fullpath"))), "project.json");
    if exist(jsonfile, "file")
        ver = jsondecode(fileread(jsonfile)).project.version;
    else
        warning("QuIDBBIDS:Setup:MissingProjectFile", "The '%s' file does not exist", jsonfile)
        ver = '0.0.0-unknown';
    end

    % Retrieve the latest version from git or GitHub. NB: The GitHub API is rate-limited
    if nargout > 1
        try
            [status, cmdout] = system('git ls-remote --tags --refs https://github.com/Donders-Institute/quidbbids');
            if status == 0
                tags   = extractAfter(splitlines(strtrim(cmdout)), 'refs/tags/' + ("v"|"V"));
                vnums  = cellfun(@(s) sscanf(s,'%d.%d.%d')', tags, 'UniformOutput', false);
                [~, i] = sortrows(cell2mat(vnums), 'descend');
                latest = tags{i(1)};
            else
                rel    = webread('https://api.github.com/repos/Donders-Institute/quidbbids/releases/latest');
                latest = erase(rel.tag_name, "v"|"V");
            end
        catch ME
            fprintf('Could not retrieve the latest release version:\n%s', ME.message)
            latest = '0.0.0-unknown';
        end
    end
end

function tutorialdata(tutorialdir)
    % This function is used to download an example BIDS dataset for testing and tutorial purposes.

    arguments (Input)
        tutorialdir {mustBeTextScalar, mustBeNonempty} = 'tutorialdata'     % Directory where the tutorial data will be stored (will be created if it doesn't exist)
    end
    url = 'https://surfdrive.surf.nl/s/7N8wctg42SRWQHC/download';           % URL of the dataset (a tarred BIDS dataset)

    if ~isfolder(tutorialdir)
        mkdir(tutorialdir)
    end

    % Download and extract the dataset
    tarfile = fullfile(tutorialdir, 'tutorialdata.tar');
    if ~isfile(tarfile)
        disp('Downloading tutorial dataset (this may take a few minutes)...')
        websave(tarfile, url)
    else
        fprintf('Tutorial dataset already downloaded at %s\n', tarfile)
    end
    disp('Extracting tutorial dataset...')
    untar(tarfile, tutorialdir)
    disp('Done!')

end
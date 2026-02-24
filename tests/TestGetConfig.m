classdef TestGetConfig < BaseTest
    % Unit tests for private/get_config function

    properties
        TempDir
        ConfigFile
    end

    methods (TestMethodSetup)
        function createConfigFiles(testCase)
            % Create a temporary directory for config files
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir)
            cd(fullfile(fileparts(mfilename("fullpath")),'..','+qb','private'))

            % Path for test config file
            testCase.ConfigFile = fullfile(testCase.TempDir, 'code', 'QuIDBBIDS', 'config.json');
        end
    end

    methods (TestMethodTeardown)
        function removeConfigFiles(testCase)
            % Clean up temporary directory
            rmdir(testCase.TempDir, 's')
        end
    end

    methods (Test)
        function testReadWriteConfig(testCase)

            % Verify the config file was created
            testCase.verifyFalse(isfile(testCase.ConfigFile))
            config = get_config(testCase.ConfigFile, struct());
            testCase.verifyTrue(isfile(testCase.ConfigFile))

            % Verify the config fields match the default
            testCase.verifyTrue(isfield(config, 'MP2RAGEWorker'))

            % Test writing a config
            config.param1 = [100; 101];
            config.param2 = [100, 101];
            config.param3 = [1, 2; 3, 4]; 
            config.param4 = {1, 'a'};
            config.param5 = 'written';
            get_config(testCase.ConfigFile, config);

            % Read it back
            newconfig = get_config(testCase.ConfigFile, struct());

            testCase.verifyEqual(newconfig.param1, config.param1')
            testCase.verifyEqual(newconfig.param2, config.param2)
            testCase.verifyEqual(newconfig.param3, config.param3)
            testCase.verifyEqual(newconfig.param4, config.param4)
            testCase.verifyEqual(newconfig.param5, config.param5)
        end

        function testVersionMismatchWarning(testCase)

            config = get_config(testCase.ConfigFile);

            % Write a version mismatch that triggers a warning
            config.General.version.value = 'foo.bar.baz';     % intentionally mismatch
            get_config(testCase.ConfigFile, config);

            % Verify that reading triggers a warning
            testCase.verifyWarning(@() get_config(testCase.ConfigFile), "QuIDBBIDS:Config:VersionMismatch")
        end
    end
end

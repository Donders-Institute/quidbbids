classdef TestGetConfig < matlab.unittest.TestCase
    % Unit tests for qb.get_config function

    properties
        TempDir
        ConfigFile
    end

    methods (TestMethodSetup)
        function createConfigFiles(testCase)
            % Create a temporary directory for config files
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir)

            % Path for test config file
            testCase.ConfigFile = fullfile(testCase.TempDir, 'derivatives', 'QuIDBBIDS', 'code', 'config.json');
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
            config = qb.get_config(testCase.ConfigFile);
            testCase.verifyTrue(isfile(testCase.ConfigFile))

            % Verify the config fields match the default
            testCase.verifyTrue(isfield(config, 'MP2RAGEWorker'))

            % Test writing a config
            config.param1  = [100; 101];
            config.param2  = 'written';
            qb.get_config(testCase.ConfigFile, config);

            % Read it back
            newconfig = qb.get_config(testCase.ConfigFile);

            testCase.verifyEqual(newconfig.param1, config.param1)
            testCase.verifyEqual(newconfig.param2, config.param2)
        end

        function testVersionMismatchWarning(testCase)

            config = qb.get_config(testCase.ConfigFile);

            % Write a version mismatch that triggers a warning
            config.version.value = 'foo.bar.baz';     % intentionally mismatch
            qb.get_config(testCase.ConfigFile, config);

            % Verify that reading triggers a warning
            testCase.verifyWarning(@() qb.get_config(testCase.ConfigFile), "QuIDBBIDS:Config:VersionMismatch")
        end
    end
end

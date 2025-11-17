classdef TestGetConfigToml < matlab.unittest.TestCase
    % Unit tests for qb.get_config_toml function

    properties
        TempDir
        TempConfigFile
        DefaultConfigFile
    end

    methods (TestMethodSetup)
        function createTempFiles(testCase)
            % Create a temporary directory for config files
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir)

            % Path for test config file
            testCase.TempConfigFile = fullfile(testCase.TempDir, "test_config.toml");

            % Path for default config file (simulate home directory)
            testCase.DefaultConfigFile = fullfile(testCase.TempDir, "config_default.toml");

            % Create a fake default config TOML
            fid = fopen(testCase.DefaultConfigFile, 'w');
            fprintf(fid, "version = 1\nparam1 = 42\nparam2 = 'test'\n");
            fclose(fid);

            % Patch qb.version() to a fixed value for testing
            if ~exist('qb', 'var')
                eval('global qb; qb.version = @() 1;');
            end
        end
    end

    methods (TestMethodTeardown)
        function removeTempFiles(testCase)
            % Clean up temporary directory
            if isfolder(testCase.TempDir)
                rmdir(testCase.TempDir, 's')
            end
        end
    end

    methods (Test)
        function testReadNonexistentConfigCreatesDefault(testCase)
            % Test reading a config that does not exist creates the default
            config = qb.get_config_toml(testCase.TempConfigFile);

            % Verify the config fields match the default
            testCase.verifyEqual(config.version, 1)
            testCase.verifyEqual(config.param1, 42)
            testCase.verifyEqual(config.param2, 'test')

            % Verify the config file was created
            testCase.verifyTrue(isfile(testCase.TempConfigFile))
        end

        function testWriteConfig(testCase)
            % Test writing a config
            cfgStruct.version = 1;
            cfgStruct.param1  = 100;
            cfgStruct.param2  = 'written';

            qb.get_config_toml(testCase.TempConfigFile, cfgStruct);

            % Read it back
            cfgRead = qb.get_config_toml(testCase.TempConfigFile);

            testCase.verifyEqual(cfgRead.version, 1)
            testCase.verifyEqual(cfgRead.param1, 100)
            testCase.verifyEqual(cfgRead.param2, 'written')
        end

        function testVersionMismatchWarning(testCase)
            % Test that a version mismatch triggers a warning
            cfgStruct.version = 0; % intentionally mismatch
            cfgStruct.param1  = 5;
            cfgStruct.param2  = 'mismatch';

            qb.get_config_toml(testCase.TempConfigFile, cfgStruct);

            % Verify that reading triggers a warning
            testCase.verifyWarning(@() qb.get_config_toml(testCase.TempConfigFile), "QuIDBBIDS:Config:VersionMismatch")
        end
    end
end

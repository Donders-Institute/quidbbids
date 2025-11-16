classdef TestGetConfigToml < matlab.unittest.TestCase
    % Test class for qb.get_config_toml function

    properties
        TestConfigFile
        TestDataDir
        OriginalPath
        OriginalHome
        MockVersion = '0.0.3'
        MockQbDir
    end

    methods (TestClassSetup)
        function setup(testCase)
            % Setup test environment
            testCase.TestDataDir = tempname;
            mkdir(testCase.TestDataDir)
            testCase.TestConfigFile = fullfile(testCase.TestDataDir, 'test_config.toml');

            % Save original HOME and set to test directory
            testCase.OriginalHome = getenv('HOME');
            setenv('HOME', testCase.TestDataDir)

            % Save original path
            testCase.OriginalPath = path;

            % Mock qb.version to return fixed test version
            testCase.mockQbVersion()
        end
    end

    methods (TestClassTeardown)
        function teardown(testCase)
            % Clean up test environment
            rmdir(testCase.TestDataDir, 's');

            % Remove mock path and restore original path
            if ~isempty(testCase.MockQbDir) && isfolder(testCase.MockQbDir)
                rmpath(testCase.MockQbDir)
            end
            path(testCase.OriginalPath)

            % Restore original HOME
            setenv('HOME', testCase.OriginalHome)
        end
    end

    methods
        function mockQbVersion(testCase)
            % Mock qb.version to return fixed test version
            testCase.MockQbDir = fullfile(testCase.TestDataDir, 'qb');
            mkdir(testCase.MockQbDir);

            versionFile = fullfile(testCase.MockQbDir, 'version.m');
            fid = fopen(versionFile, 'w');
            fprintf(fid, 'function v = version()\n');
            fprintf(fid, '    v = ''%s'';\n', testCase.MockVersion);
            fprintf(fid, 'end\n');
            fclose(fid);

            addpath(testCase.MockQbDir);
        end

        function config = createSimpleConfig(testCase)
            % Create simple config with only the three specified items
            config = struct('version', testCase.MockVersion, ...
                            'useHPC', 1, ...
                            'gyro', 42.57747892);
        end
    end

    methods (Test)
        function testReadConfigFile(testCase)
            % Test reading an existing config file
            testConfig = testCase.createSimpleConfig();
            toml.write(testCase.TestConfigFile, testConfig)

            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify the three fields
            testCase.verifyEqual(config.version, testCase.MockVersion)
            testCase.verifyEqual(config.useHPC, 1)
            testCase.verifyEqual(config.gyro, 42.57747892)
        end

        function testCreateConfigFileIfNotExists(testCase)
            % Test that config file is created if it doesn't exist
            nonExistentFile = fullfile(testCase.TestDataDir, 'nonexistent_config.toml');

            % Don't pre-create default config - let get_config_toml handle it
            % This tests the actual automatic creation logic
            config = qb.get_config_toml(nonExistentFile);

            testCase.verifyTrue(isfile(nonExistentFile))
            testCase.verifyEqual(config.version, testCase.MockVersion)

            % Verify default config was also created automatically
            expectedDefaultPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');
            testCase.verifyTrue(isfile(expectedDefaultPath))
        end

        function testWriteConfigFile(testCase)
            % Test writing a config file
            testConfig = testCase.createSimpleConfig();
            testConfig.useHPC = 0;  % Modified value

            qb.get_config_toml(testCase.TestConfigFile, testConfig);

            testCase.verifyTrue(isfile(testCase.TestConfigFile))

            % Read back and verify modified field
            readConfig = toml.read(testCase.TestConfigFile);
            testCase.verifyEqual(readConfig.useHPC, 0)
        end

        function testInt64ToDoubleConversion(testCase)
            % Test that int64 values are converted to double
            testConfig = testCase.createSimpleConfig();
            testConfig.useHPC = int64(1);  % Simulate TOML int64

            toml.write(testCase.TestConfigFile, testConfig)
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify conversion happened
            testCase.verifyClass(config.useHPC, 'double')
            testCase.verifyEqual(config.useHPC, 1)
        end

        function testVersionMismatchWarning(testCase)
            % Test that version mismatch produces warning
            testConfig = testCase.createSimpleConfig();
            testConfig.version = '0.0.2';  % Different version

            toml.write(testCase.TestConfigFile, testConfig)

            testCase.verifyWarning(@() qb.get_config_toml(testCase.TestConfigFile), 'QuIDBBIDS:Config:VersionMismatch')
        end

        function testNoVersionMismatchWarning(testCase)
            % Test that no warning is produced when versions match
            testConfig = testCase.createSimpleConfig();
            toml.write(testCase.TestConfigFile, testConfig)

            testCase.verifyWarningFree(@() qb.get_config_toml(testCase.TestConfigFile))
        end

        function testDefaultConfigCreation(testCase)
            % Test that default config is created in HOME directory
            expectedDefaultPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');

            % Ensure default config doesn't exist initially
            if isfile(expectedDefaultPath)
                delete(expectedDefaultPath);
            end

            config = qb.get_config_toml(testCase.TestConfigFile);

            testCase.verifyTrue(isfile(expectedDefaultPath))
            testCase.verifyEqual(config.version, testCase.MockVersion)
        end
    end
end

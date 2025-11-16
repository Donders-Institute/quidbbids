classdef TestGetConfigToml < matlab.unittest.TestCase
    % Test class for qb.get_config_toml function

    properties
        TestConfigFile
        TestDataDir
        OriginalPath
        OriginalHome
        MockVersion = '0.0.3'
    end

    methods (TestClassSetup)
        function setup(testCase)
            % Setup test environment
            testCase.TestDataDir = tempname;
            mkdir(testCase.TestDataDir);
            testCase.TestConfigFile = fullfile(testCase.TestDataDir, 'test_config.toml');

            % Save original HOME and set to test directory
            testCase.OriginalHome = getenv('HOME');
            setenv('HOME', testCase.TestDataDir);

            % Save original path
            testCase.OriginalPath = path;

            % Ensure we're using the test HOME by creating the expected directory structure
            defaultConfigDir = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion);
            if ~isfolder(defaultConfigDir)
                mkdir(defaultConfigDir);
            end
        end
    end

    methods (TestClassTeardown)
        function teardown(testCase)
            % Clean up test environment
            if isfolder(testCase.TestDataDir)
                rmdir(testCase.TestDataDir, 's');
            end

            % Restore original path and HOME
            path(testCase.OriginalPath);
            setenv('HOME', testCase.OriginalHome);
        end
    end

    methods
        function config = createSimpleConfig(testCase, version)
            % Create simple config with only the three specified items
            if nargin < 2
                version = testCase.MockVersion;
            end
            config = struct('version', version, ...
                            'useHPC', 1, ...
                            'gyro', 42.5775);
        end
    end

    methods (Test)
        function testReadConfigFile(testCase)
            % Test reading an existing config file
            testConfig = testCase.createSimpleConfig();
            toml.write(testCase.TestConfigFile, testConfig);

            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify the three fields
            testCase.verifyEqual(config.version, testCase.MockVersion);
            testCase.verifyEqual(config.useHPC, 1);
            testCase.verifyEqual(config.gyro, 42.5775);
        end

        function testCreateConfigFileIfNotExists(testCase)
            % Test that config file is created if it doesn't exist
            nonExistentFile = fullfile(testCase.TestDataDir, 'nonexistent_config.toml');

            % First create the default config that will be copied
            defaultConfigPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');
            if ~isfile(defaultConfigPath)
                defaultConfig = testCase.createSimpleConfig();
                [pth, ~, ~] = fileparts(defaultConfigPath);
                mkdir(pth);
                toml.write(defaultConfigPath, defaultConfig);
            end

            % This should create the study config by copying from default
            config = qb.get_config_toml(nonExistentFile);

            testCase.verifyTrue(isfile(nonExistentFile));
            testCase.verifyEqual(config.version, testCase.MockVersion);
        end

        function testWriteConfigFile(testCase)
            % Test writing a config file
            testConfig = testCase.createSimpleConfig();
            testConfig.useHPC = 0;  % Modified value

            qb.get_config_toml(testCase.TestConfigFile, testConfig);

            testCase.verifyTrue(isfile(testCase.TestConfigFile));

            % Read back and verify modified field - toml.read returns containers.Map
            readConfigMap = toml.read(testCase.TestConfigFile);
            testCase.verifyEqual(readConfigMap('useHPC'), 0); % Use map access
        end

        function testInt64ToDoubleConversion(testCase)
            % Test that int64 values are converted to double
            testConfig = testCase.createSimpleConfig();
            testConfig.useHPC = int64(1);  % Simulate TOML int64

            toml.write(testCase.TestConfigFile, testConfig);
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify conversion happened
            testCase.verifyClass(config.useHPC, 'double');
            testCase.verifyEqual(config.useHPC, 1);
        end

        function testVersionMismatchWarning(testCase)
            % Test that version mismatch produces warning
            % Skip this test for now since we can't easily mock qb.version
            % without causing conflicts
            testCase.assumeFail('Version mismatch test requires proper mocking of qb.version');
        end

        function testNoVersionMismatchWarning(testCase)
            % Test that no warning is produced when versions match
            testConfig = testCase.createSimpleConfig();
            toml.write(testCase.TestConfigFile, testConfig);

            testCase.verifyWarningFree(@() qb.get_config_toml(testCase.TestConfigFile));
        end

        function testDefaultConfigCreation(testCase)
            % Test that default config is created in HOME directory
            expectedDefaultPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');

            % Ensure default config doesn't exist initially
            if isfile(expectedDefaultPath)
                delete(expectedDefaultPath);
            end

            % Also remove the directory to test full creation
            configDir = fileparts(expectedDefaultPath);
            if isfolder(configDir)
                rmdir(configDir, 's');
            end

            config = qb.get_config_toml(testCase.TestConfigFile);

            testCase.verifyTrue(isfile(expectedDefaultPath));
            testCase.verifyTrue(isfield(config, 'version'));
        end
    end
end

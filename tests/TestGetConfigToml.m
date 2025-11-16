classdef TestGetConfigToml < matlab.unittest.TestCase
    % Test class for qb.get_config_toml function

    properties
        TestConfigFile
        TestDataDir
        OriginalPath
        OriginalHome
        MockVersion = '99.99.99'  % Fixed test version
    end

    methods (TestClassSetup)
        function setup(testCase)
            % Setup test environment
            testCase.TestDataDir = tempname;
            mkdir(testCase.TestDataDir)
            testCase.TestConfigFile = fullfile(testCase.TestDataDir, 'test_config.toml');

            % Save original HOME and set to test directory
            testCase.OriginalHome = getenv('HOME');
            setenv('HOME', testCase.TestDataDir);

            % Add the function to path if not already there
            testCase.OriginalPath = path;

            % Mock qb.version to return fixed test version
            testCase.mockQbVersion();
        end
    end

    methods (TestClassTeardown)
        function teardown(testCase)
            % Clean up test environment
            if isfolder(testCase.TestDataDir)
                rmdir(testCase.TestDataDir, 's');
            end
            path(testCase.OriginalPath);
            setenv('HOME', testCase.OriginalHome);
        end
    end

    methods
        function mockQbVersion(testCase)
            % Mock qb.version to return fixed test version
            % This ensures deterministic behavior in tests

            % Create a temporary function that shadows qb.version
            mockDir = fullfile(testCase.TestDataDir, 'qb');
            mkdir(mockDir);

            % Create version.m that returns our test version
            versionFile = fullfile(mockDir, 'version.m');
            fid = fopen(versionFile, 'w');
            fprintf(fid, 'function v = version()\n');
            fprintf(fid, '    v = ''%s'';\n', testCase.MockVersion);
            fprintf(fid, 'end\n');
            fclose(fid);

            % Add to path so it shadows the real qb.version
            addpath(mockDir)
        end
    end

    methods (Test)
        function testReadConfigFile(testCase)
            % Test reading an existing config file
            % Create a test config file
            testConfig = struct('version', testCase.MockVersion, 'setting1', 'value1', 'numeric_setting', 42);
            toml.write(testCase.TestConfigFile, testConfig);

            % Read the config
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify the content
            testCase.verifyEqual(config.version, testCase.MockVersion);
            testCase.verifyEqual(config.setting1, 'value1');
            testCase.verifyEqual(config.numeric_setting, 42);
        end

        function testCreateConfigFileIfNotExists(testCase)
            % Test that config file is created if it doesn't exist
            nonExistentFile = fullfile(testCase.TestDataDir, 'nonexistent_config.toml');

            % This should create the file
            config = qb.get_config_toml(nonExistentFile);

            % Verify file was created
            testCase.verifyTrue(isfile(nonExistentFile));

            % Verify config has expected structure (at minimum version field)
            testCase.verifyTrue(isfield(config, 'version'));
        end

        function testWriteConfigFile(testCase)
            % Test writing a config file
            testConfig = struct('version', testCase.MockVersion, 'new_setting', 'new_value', 'number', 123);

            % Write the config
            qb.get_config_toml(testCase.TestConfigFile, testConfig);

            % Verify file was created
            testCase.verifyTrue(isfile(testCase.TestConfigFile));

            % Read it back and verify content
            readConfig = toml.read(testCase.TestConfigFile);
            testCase.verifyEqual(readConfig.version, testCase.MockVersion);
            testCase.verifyEqual(readConfig.new_setting, 'new_value');
            testCase.verifyEqual(readConfig.number, 123);
        end

        function testInt64ToDoubleConversion(testCase)
            % Test that int64 values are converted to double
            % Create a config with int64 values (simulating TOML parsing)
            testConfig = struct('int64_value', int64(100), 'double_value', 3.14, 'text', 'hello');

            % Write and read back to test the conversion
            toml.write(testCase.TestConfigFile, testConfig);
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify int64 was converted to double
            testCase.verifyClass(config.int64_value, 'double');
            testCase.verifyEqual(config.int64_value, 100);

            % Verify other types unchanged
            testCase.verifyClass(config.double_value, 'double');
            testCase.verifyEqual(config.text, 'hello');
        end

        function testNestedStructureConversion(testCase)
            % Test int64 conversion with nested structures
            nestedConfig = struct('level1', struct('int64_val', int64(200), ...
                                                   'level2', struct('another_int64', int64(300))), ...
                                  'simple_int64', int64(400));

            toml.write(testCase.TestConfigFile, nestedConfig);
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify all levels converted
            testCase.verifyClass(config.level1.int64_val, 'double');
            testCase.verifyClass(config.level1.level2.another_int64, 'double');
            testCase.verifyClass(config.simple_int64, 'double');
        end

        function testCellArrayConversion(testCase)
            % Test int64 conversion with cell arrays
            cellConfig = struct('cell_with_int64', {{int64(1), int64(2), int64(3)}}, ...
                                'mixed_cell', {{'text', int64(99), 3.14}});

            toml.write(testCase.TestConfigFile, cellConfig);
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify cell array elements converted
            testCase.verifyClass(config.cell_with_int64{1}, 'double');
            testCase.verifyClass(config.cell_with_int64{2}, 'double');
            testCase.verifyClass(config.cell_with_int64{3}, 'double');
            testCase.verifyClass(config.mixed_cell{2}, 'double');
        end

        function testVersionMismatchWarning(testCase)
            % Test that version mismatch produces warning
            % Use a different version in config file
            differentVersion = '0.9.0';
            testConfig = struct('version', differentVersion, 'setting', 'test');
            toml.write(testCase.TestConfigFile, testConfig);

            % This should trigger a warning due to version mismatch
            testCase.verifyWarning(@() qb.get_config_toml(testCase.TestConfigFile), ...
                                  'QuIDBBIDS:Config:VersionMismatch');
        end

        function testNoVersionMismatchWarning(testCase)
            % Test that no warning is produced when versions match
            testConfig = struct('version', testCase.MockVersion, 'setting', 'test');
            toml.write(testCase.TestConfigFile, testConfig);

            % This should NOT trigger a warning
            testCase.verifyWarningFree(@() qb.get_config_toml(testCase.TestConfigFile));
        end

        function testDefaultConfigCreation(testCase)
            % Test that default config is created in HOME directory
            expectedDefaultPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');

            % Ensure default config doesn't exist initially
            if isfile(expectedDefaultPath)
                delete(expectedDefaultPath);
            end

            % Call function - should create default config in test HOME
            config = qb.get_config_toml(testCase.TestConfigFile);

            % Verify default config was created in test directory
            testCase.verifyTrue(isfile(expectedDefaultPath), ...
                'Default config should be created in test HOME directory');

            % Verify the directory structure was created
            testCase.verifyTrue(isfolder(fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion)));
        end

        function testDefaultConfigCopyWhenMissing(testCase)
            % Test that default config is copied when study config is missing
            studyConfigFile = fullfile(testCase.TestDataDir, 'study_config.toml');

            % First ensure default config exists
            defaultConfigPath = fullfile(testCase.TestDataDir, '.quidbbids', testCase.MockVersion, 'config_default.toml');
            if ~isfile(defaultConfigPath)
                [pth, ~, ~] = fileparts(defaultConfigPath);
                mkdir(pth);
                % Create a minimal default config
                defaultConfig = struct('version', testCase.MockVersion, 'default_setting', 'default_value');
                toml.write(defaultConfigPath, defaultConfig);
            end

            % Now call get_config_toml with non-existent study config
            config = qb.get_config_toml(studyConfigFile);

            % Verify study config was created as copy of default
            testCase.verifyTrue(isfile(studyConfigFile));
            testCase.verifyEqual(config.version, testCase.MockVersion);
            testCase.verifyEqual(config.default_setting, 'default_value');
        end

        function testInvalidInputs(testCase)
            % Test function behavior with invalid inputs
            % Test non-scalar text input
            testCase.verifyError(@() qb.get_config_toml(['file1.toml'; 'file2.toml']), ...
                                'MATLAB:validators:mustBeTextScalar');
        end
    end

    methods (Test, TestTags = {'Integration'})
        function testRoundTrip(testCase)
            % Integration test: write and read back configuration
            originalConfig = struct('version', testCase.MockVersion, ...
                                   'database', struct('host', 'localhost', 'port', 5432), ...
                                   'processing', struct('enabled', true, 'max_workers', int64(4)), ...
                                   'tags', {{'EEG', 'MEG', 'fMRI'}});

            % Write config
            qb.get_config_toml(testCase.TestConfigFile, originalConfig);

            % Read config back
            readConfig = qb.get_config_toml(testCase.TestConfigFile);

            % Verify all values preserved (with int64 conversion)
            testCase.verifyEqual(readConfig.version, testCase.MockVersion);
            testCase.verifyEqual(readConfig.database.host, 'localhost');
            testCase.verifyEqual(readConfig.database.port, 5432);
            testCase.verifyEqual(readConfig.processing.enabled, true);
            testCase.verifyEqual(readConfig.processing.max_workers, 4); % Should be double now
            testCase.verifyEqual(readConfig.tags, {'EEG', 'MEG', 'fMRI'});
        end
    end
end

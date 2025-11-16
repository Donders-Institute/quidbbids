classdef TestGetConfigToml < matlab.mock.TestCase
    % Unit tests for get_config_toml

    properties
        TempDir
        ConfigFile
        DefaultDir
        OriginalHome
        MockVersion = "1.2.3"
    end

    methods (TestMethodSetup)
        function setupEnvironment(testCase)

            % Create a temporary test directory
            testCase.TempDir = tempname;
            mkdir(testCase.TempDir);

            % Pretend HOME is the temp directory
            testCase.OriginalHome = getenv("HOME");
            setenv("HOME", testCase.TempDir);

            % Location where default configs should be created
            testCase.DefaultDir = fullfile(testCase.TempDir, ".quidbbids", testCase.MockVersion);

            % Where study-level config will be read/written
            testCase.ConfigFile = fullfile(testCase.TempDir, "study", "config.toml");

            % --- Mock qb.version() ---
            import matlab.mock.actions.AssignOutputs
            [mockQB, behavior] = testCase.createMock('AddedMethods', "version");
            when(withExactInputs(behavior.version), AssignOutputs(testCase.MockVersion));
            assignin('base', 'qb', mockQB);

            % --- Create a minimal default config so copyfile works ---
            defaultTemplate = fullfile(fileparts(mfilename("fullpath")), "config_default.toml");
            fid = fopen(defaultTemplate, 'w');
            fprintf(fid, 'version = "%s"\nvalue = 10\n', testCase.MockVersion);
            fclose(fid);
        end
    end

    methods (TestMethodTeardown)
        function teardownEnvironment(testCase)
            % Restore original environment variable
            setenv("HOME", testCase.OriginalHome);

            % Clean up
            rmdir(testCase.TempDir, 's')
        end
    end

    methods (Test)

        function testDefaultConfigCreated(testCase)
            % Call without config struct → should create default config first
            qb.get_config_toml(testCase.ConfigFile);

            expectedDefault = fullfile(testCase.DefaultDir, "config_default.toml");

            testCase.verifyTrue(isfile(expectedDefault), "Default config file was not created.")
        end

        function testStudyConfigCreatedFromDefault(testCase)
            qb.get_config_toml(testCase.ConfigFile);

            testCase.verifyTrue(isfile(testCase.ConfigFile), "Study config file was not created.")

            contents = fileread(testCase.ConfigFile);
            testCase.verifyContains(contents, "version")
        end

        function testReadingConfigReturnsStruct(testCase)
            config = qb.get_config_toml(testCase.ConfigFile);

            testCase.verifyClass(config, "struct")
            testCase.verifyEqual(config.version, testCase.MockVersion)
        end

        function testWritingConfigOverwritesFile(testCase)

            % First create a config file
            cfg = struct("version", testCase.MockVersion, "value", 123);
            qb.get_config_toml(testCase.ConfigFile, cfg);

            % Now load it again
            loaded = qb.get_config_toml(testCase.ConfigFile);

            testCase.verifyEqual(loaded.value, 123)
        end

        function testCastInt64Converted(testCase)
            cfg = struct("a", int64(5), "b", { {int64(3)} });

            out  = evalc('qb.get_config_toml("dummy.toml", cfg)');
            conv = qb.get_config_toml("dummy.toml", cfg);

            testCase.verifyClass(conv.a, "double")
            testCase.verifyClass(conv.b{1}, "double")
        end

        function testVersionMismatchWarning(testCase)
            % Create a config file with the wrong version
            fid = fopen(testCase.ConfigFile, 'w');
            fprintf(fid, 'version = "WRONG"\n');
            fclose(fid);

            testCase.verifyWarning(@() qb.get_config_toml(testCase.ConfigFile), 'QuIDBBIDS:Config:VersionMismatch');
        end

    end
end

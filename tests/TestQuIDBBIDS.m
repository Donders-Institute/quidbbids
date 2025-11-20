classdef TestQuIDBBIDS < matlab.unittest.TestCase

    properties
        TmpDir  % Temporary directory path
    end

    methods(TestClassSetup)
        % Shared setup for the entire test class
    end

    methods(TestMethodSetup)
        function createTempDir(testCase)
            testCase.TmpDir = tempname;
            mkdir(fullfile(testCase.TmpDir))
            bids.init(testCase.TmpDir)
        end
    end

    methods(TestMethodTeardown)
        function removeTempDir(testCase)
            rmdir(testCase.TmpDir, 's')
        end
    end

    methods(Test)

        function test_constructor(testCase)
            % Test basic object construction
            obj = qb.QuIDBBIDS(testCase.TmpDir);
            testCase.assertClass(obj, 'qb.QuIDBBIDS')
        end

        function test_getconfig(testCase)
            configfile = fullfile(testCase.TmpDir, 'derivatives', 'QuIDBBIDS', 'code', 'config.json');
            testCase.assertFalse(isfile(configfile), sprintf('Configfile "%s" should not yet exist', configfile))

            % Test if settings are created correctly
            obj = qb.QuIDBBIDS(testCase.TmpDir);
            testCase.assertTrue(isfile(configfile), sprintf('Configfile "%s" not found', configfile));
            testCase.assertClass(obj.get_config(struct('configfile',configfile)), 'struct', 'Settings should be a struct')
        end
    end

end

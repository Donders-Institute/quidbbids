classdef TestQuIDBBIDS < matlab.unittest.TestCase

    properties
        TmpDir  % Temporary directory path
    end
    
    methods(TestClassSetup)
        % Shared setup for the entire test class
    end
    
    methods(TestMethodSetup)
        function createTempDir(testCase)
            testCase.TmpDir = fullfile(tempdir, ['test_', char(java.util.UUID.randomUUID)]);
            mkdir(testCase.TmpDir);
        end
    end

    methods(TestMethodTeardown)
        function removeTempDir(testCase)
            rmdir(testCase.TmpDir, 's');
        end
    end

    methods(Test)

        function test_constructor(testCase)
            % Test basic object construction
            obj = qb.QuIDBBIDS(testCase.TmpDir);
            testCase.assertClass(obj, 'qb.QuIDBBIDS');
        end
    
        function test_getconfig(testCase)
            % Test if settings are created correctly
            obj = qb.QuIDBBIDS(testCase.TmpDir);
            configfile = fullfile(testCase.TmpDir, 'config_test.toml');
            testCase.assertFalse(isfile(configfile), sprintf('Configfile "%s" should not yet exist', configfile));
            testCase.assertClass(obj.getconfig(configfile), 'struct', 'Settings should be a struct');
            testCase.assertTrue(isfile(configfile), sprintf('Configfile "%s" not found', configfile));
        end
    end
    
end

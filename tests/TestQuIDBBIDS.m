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
    
        function test_getsettings(testCase)
            % Test if settings are created correctly
            obj = qb.QuIDBBIDS(testCase.TmpDir);
            settingsfile = fullfile(testCase.TmpDir, 'test.json');
            testCase.assertFalse(isfile(settingsfile), 'Expected settingsfile not to exist');
            testCase.assertClass(obj.getsettings(settingsfile), 'struct', 'Settings should be a struct');
            testCase.assertTrue(isfile(settingsfile), 'Expected settingsfile to exist');
        end
    end
    
end

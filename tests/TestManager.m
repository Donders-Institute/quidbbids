classdef TestManager < matlab.unittest.TestCase

    properties
        TmpDir  % Temporary directory path
        mgr     % QuIDBBIDS manager instance
    end

    methods(TestClassSetup)
        % Shared setup for the entire test class
    end

    methods(TestMethodSetup)
        function createTempDir(testCase)
            testCase.TmpDir = tempname;
            mkdir(fullfile(testCase.TmpDir, 'sub-01', 'ses-01', 'anat'))
            bids.init(testCase.TmpDir)
            testCase.mgr = qb.QuIDBBIDS(testCase.TmpDir).manager();
        end
    end

    methods(TestMethodTeardown)
        function removeTempDir(testCase)
            rmdir(testCase.TmpDir, 's')
        end
    end

    methods(Test)

        function testInitialization(testCase)
            % Manager should not have looked up workers and created an empty team
            testCase.verifyEmpty(testCase.mgr.products, 'Manager should have initialized an empty product list')
            testCase.verifyEmpty(testCase.mgr.team, 'Manager team should hence be empty')
            testCase.verifyTrue(isstruct(testCase.mgr.team), 'Team must be a struct mapping workitems -> worker resumes')

            % start_workflow must run without throwing an error, even without workers
            testCase.verifyWarningFree(@() testCase.mgr.start_workflow(), 'Manager.start_workflow produced an unexpected error')
        end

        function testCreateTeam(testCase)

            % Manager should store products as string row
            testCase.mgr.products = ["a", "b", "c"];
            testCase.verifyEqual(testCase.mgr.products, ["a", "b", "c"])

            % Should throw when no worker can make a requested product
            testCase.verifyError(@() testCase.mgr.create_team(), ?MException, "Manager should error for unknown products")
            testCase.verifyError(@() testCase.mgr.create_team("thisDoesNotExist"), ?MException, "Manager should error for unknown directly passed products")
            testCase.verifyWarningFree(@() testCase.mgr.create_team("rawMEGRE"), "Manager should not error for known directly passed products")
            testCase.verifyNotEmpty(testCase.mgr.team, 'Manager team should not be empty')
        end

    end

end

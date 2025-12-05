classdef TestManager < BaseTest

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
            mkdir(fullfile(testCase.TmpDir))
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
            testCase.verifyEqual(testCase.mgr.team, struct(), 'Manager team should hence be empty')
            testCase.verifyTrue(isstruct(testCase.mgr.team), 'Team must be a struct mapping workitems -> worker resumes')

            % start_workflow must run without throwing an error, even without workers
            testCase.verifyWarningFree(@() testCase.mgr.start_workflow(), 'Manager.start_workflow produced an unexpected error')
        end

        function testCreateTeam(testCase)

            % Should throw an error if no worker can make a requested product
            testCase.mgr.coord.products = ["rawMEGRE", "echo.*D(mag|phase)"];
            testCase.verifyWarningFree(@() testCase.mgr.create_team(), "Manager should not error for known directly passed products")
            testCase.verifyNotEmpty(testCase.mgr.team, 'Manager team should not be empty')
        end

    end

end

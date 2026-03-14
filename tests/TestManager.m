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
            testCase.mgr.interactive = false;
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

            % Should not throw an error if a worker can make the requested product
            testCase.mgr.coord.resumes.MEGREprepWorker.preferred = true;
            testCase.mgr.coord.products = ["rawMEGRE", "echo.*D(mag|phase)"];
            testCase.verifyWarningFree(@() testCase.mgr.create_team(), "Manager should not error for known products")
            testCase.verifyNotEmpty(testCase.mgr.team, 'Manager team should not be empty')

            % Should not error if the preferred worker is set
            testCase.mgr.coord.products = ["R1map", "R2starmap", "MWFmap"];
            testCase.mgr.coord.resumes.R1R2sWorker.preferred = true;
            testCase.mgr.coord.resumes.MCR_GPUWorker.preferred = true;
            testCase.verifyWarningFree(@() testCase.mgr.create_team(), "Manager should not error when preferred worker is set")
            testCase.verifyNotEmpty(testCase.mgr.team, 'Manager team should not be empty')

            % Should error if the preferred worker is not set
            testCase.mgr.coord.resumes.R1R2sWorker.preferred = false;
            testCase.verifyError(@() testCase.mgr.create_team(), "QuIDBBIDS:WorkItem:InvalidCount", "Manager should error when preferred worker is not set")
            testCase.verifyNotEmpty(testCase.mgr.team, 'Manager team should not be empty')
        end

    end

end

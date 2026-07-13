classdef TestWorkers < BaseTest
    % Unit tests for the abstract Worker class + construction of its children

    properties
        WorkDir
        OutputDir
        BIDS
        Subject
        Config
        BidsExamplesRepo  % Shared repository for all test methods
        BidsLayout        % Shared BIDS layout for all test methods
    end

    methods (TestClassSetup)
        function setupBidsExamples(testCase)
            % Clone bids-examples repository once for all test methods in this class
            testCase.BidsExamplesRepo = fullfile(tempname, 'quidbbids_test_bids_examples');
            if ~exist(testCase.BidsExamplesRepo, 'dir')
                system(sprintf('git clone --depth 1 %s %s', 'https://github.com/bids-standard/bids-examples.git', testCase.BidsExamplesRepo));
            end
            
            % Initialize BIDS layout once for all test methods
            testCase.BidsLayout = bids.layout(fullfile(testCase.BidsExamplesRepo, 'qmri_vfa'));
            
            % Load configuration once for all test methods
            configFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+qb', 'private', 'config_default.json');
            testCase.Config = bids.util.jsondecode(configFile);
        end
    end

    methods (TestMethodSetup)
        function setupWorkerEnvironment(testCase)
            % Create temporary directories for this test method
            testCase.WorkDir = tempname;
            testCase.OutputDir = tempname;
            
            % Use the pre-created BIDS layout and config from TestClassSetup
            testCase.BIDS = testCase.BidsLayout;
            
            % Use the first subject from the dataset
            testCase.Subject = testCase.BIDS.subjects(1);
        end
    end

    methods (TestClassTeardown)
        function teardownBidsExamples(testCase)
            % Clean up the bids-examples repository
            if exist(testCase.BidsExamplesRepo, 'dir')
                rmdir(testCase.BidsExamplesRepo, 's')
            end
        end
    end

    methods (TestMethodTeardown)
        function teardownWorkerEnvironment(testCase)
            % Clean up the temporary directories
            if exist(testCase.WorkDir, 'dir')
                rmdir(testCase.WorkDir, 's')
            elseif exist(testCase.WorkDir, 'file')
                delete(testCase.WorkDir)
            end
            if exist(testCase.OutputDir, 'dir')
                rmdir(testCase.OutputDir, 's')
            elseif exist(testCase.OutputDir, 'file')
                delete(testCase.OutputDir)
            end
        end
    end

    methods (Test)

        function testWorkersConstruction(testCase)
            % Test that all concrete Worker subclasses can be constructed
            for classFile = dir(fullfile(fileparts(which('qb.workers.Worker')), '*Worker*.m'))'
                fullClassName = ['qb.workers.' classFile.name(1:end-2)];    % Remove .m extension
                isAbstract = meta.class.fromName(fullClassName).Abstract;
                if strcmp(fullClassName, 'qb.workers.Worker')
                    testCase.verifyTrue(isAbstract)
                else
                    testCase.verifyFalse(isAbstract)
                    testCase.verifyWarningFree(@() feval(fullClassName, testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir))
                    worker = feval(fullClassName, testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
                    testCase.verifyTrue(isa(worker, 'qb.workers.Worker'), sprintf('%s should be a Worker', fullClassName))
                    testCase.verifyTrue(isa(worker, fullClassName), sprintf('%s should be of its own class', fullClassName))
                    testCase.verifyEqual(worker.name, string(classFile.name(1:end-2)))
                    testCase.verifyEqual(worker.BIDS, testCase.BIDS, 'BIDS property should match input')
                    testCase.verifyClass(worker.logger, 'qb.workers.Logging')
                    testCase.verifyEqual(worker.subject, testCase.Subject, 'subject property should match input')
                    testCase.verifyEqual(worker.workdir, testCase.WorkDir, 'workdir property should match input')
                    testCase.verifyEqual(worker.outputdir, testCase.OutputDir, 'outputdir property should match input')
                    testCase.verifyClass(worker.config, 'struct', 'config should be a struct')
                    testCase.verifyFalse(worker.force, 'force should default to false')
                    testCase.verifyClass(worker.team, 'struct', 'team should be a struct')
                    testCase.verifyClass(worker.bidsfilter, 'struct', 'bidsfilter should be a struct')
                    testCase.verifyNotEmpty(worker.bidsfilter, 'bidsfilter should not be empty')
                    testCase.verifyClass(worker.usesGPU, 'logical')
                    testCase.verifyClass(worker.description, 'string', 'description should be a string')
                end
            end
        end

        function testSubSesMethods(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Test that subject/session parsing methods work with real BIDS data
            subLabel = worker.sub();
            sesLabel = worker.ses();
            subses   = worker.sub_ses();
            
            % Verify that sub() returns the exact numeric subject label (e.g., '01')
            testCase.verifyNotEmpty(subLabel, 'sub() should return non-empty label')
            testCase.verifyTrue(all(isstrprop(subLabel, 'digit')), 'sub() should return only digits (e.g., ''001'')')
            
            % Verify that ses() is empty (qmri_vfa case) or a numeric session label (e.g. '01')
            if isempty(sesLabel)
                testCase.verifyEqual(subses, ['sub-' subLabel], 'sub_ses should equal sub-# when no session exists (e.g., sub-01)')
            else
                testCase.verifyTrue(all(isstrprop(sesLabel, 'digit')), 'ses() should return only digits (e.g., ''01'')')
                testCase.verifyEqual(subses, ['sub-' subLabel '_ses-' sesLabel], 'sub_ses should equal sub-#_ses-# when session exists')
            end
        end

        function testMakes(testCase)
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            workitems = worker.makes();
            testCase.verifyClass(workitems, 'string')
            testCase.verifyTrue(isrow(workitems))
            testCase.verifyGreaterThan(numel(workitems), 0)
        end

        function testFetchMethodErrorHandling(testCase)
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            work = worker.fetch('NONEXISTENT_WORKITEM');
            testCase.verifyEmpty(work)
        end

        function testLockUnlockMethods(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Verify initially not locked
            testCase.verifyEmpty(worker.is_locked(), 'Should not be locked initially')
            
            % Test lock
            worker.lock()
            lockedInfo = worker.is_locked();
            testCase.verifyNotEmpty(lockedInfo, 'Should be locked after calling lock()')
            testCase.verifySubstring(lockedInfo, 'B1prepWorker', 'Lock file should contain worker class name')
            
            % Test unlock
            worker.unlock()
            testCase.verifyEmpty(worker.is_locked(), 'Should not be locked after calling unlock()')
        end

        function testDone(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Create the necessary directory structure for the done file
            % The done file will be in workdir/sub-XX/ where XX is the subject label
            subDir = fullfile(testCase.WorkDir, ['sub-' worker.sub()]);
            if ~exist(subDir, 'dir')
                mkdir(subDir);
            end
            
            % Verify initially not done
            testCase.verifyEmpty(worker.is_done(), 'Should not be done initially')
            
            % Test done
            worker.done()
            doneInfo = worker.is_done();
            testCase.verifyNotEmpty(doneInfo, 'Should have done info after calling done()')
            testCase.verifySubstring(doneInfo, 'B1prepWorker', 'Done file should contain worker class name')
        end

        function testAskTeam(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Test error handling when team is empty
            testCase.verifyError(@() worker.ask_team('nonexistent'), ?MException)
            
            % Test error handling when no team member can produce the workitem
            worker.team = struct();
            testCase.verifyError(@() worker.ask_team('nonexistent'), ?MException)
        end

        function testBIDS_ses(testCase)
            % Use the qMRLab derivatives directory from bids-examples as workdir
            workDir = fullfile(testCase.BidsExamplesRepo, 'qmri_vfa', 'derivatives', 'qMRLab');
            
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, workDir, testCase.OutputDir);
            
            % Test BIDS_ses returns a struct filtered to one subject
            bidsLayout = worker.BIDS_ses(workDir);
            testCase.verifyClass(bidsLayout, 'struct')
            testCase.verifyNotEmpty(bidsLayout, 'BIDS_ses should return a non-empty struct')
            testCase.verifyEqual(numel(bidsLayout.subjects), 1, 'BIDS_ses should filter to exactly one subject')
            
            % Also verify session filtering when session exists
            if ~isempty(worker.ses())
                testCase.verifyEqual(numel(bidsLayout.sessions), 1, 'BIDS_ses should filter to exactly one session')
            end
        end

        function testQuery_ses(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Test query_ses with 'data' query. This should return filtered results for the current subject/session
            [result, bfiles] = worker.query_ses(testCase.BIDS, 'data');
            testCase.verifyClass(result, 'cell')
            testCase.verifyTrue(isrow(result), 'Result should be a row cell array')
            
            % Test query_ses with additional filters
            [result, bfiles] = worker.query_ses(testCase.BIDS, 'data', 'modality', 'anat');
            testCase.verifyClass(result, 'cell')
            
            % Test query_ses with struct filter
            filter = struct('modality', 'anat');
            [result, bfiles] = worker.query_ses(testCase.BIDS, 'data', filter);
            testCase.verifyClass(result, 'cell')
            
            % Test query_ses with metadata query
            result = worker.query_ses(testCase.BIDS, 'metadata');
            testCase.verifyClass(result, 'cell')
        end

        function testBfile_set(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Create a mock BIDS file path
            originalPath = fullfile(testCase.WorkDir, 'sub-001', 'anat', 'sub-001_acq-test_T1w.nii.gz');
            
            % Create a bids.File object from the path
            bfile = bids.File(originalPath);
            
            % Test updating entities
            specs = struct('acq', 'updated', 'run', 2, 'suffix', 'T1map');
            updatedBfile = worker.bfile_set(bfile, specs, testCase.WorkDir);
            
            testCase.verifyClass(updatedBfile, 'bids.File')
            testCase.verifyEqual(updatedBfile.entities.acq, 'updated')
            testCase.verifyEqual(updatedBfile.entities.run, '2')
            testCase.verifyEqual(updatedBfile.suffix, 'T1map')
            
            % Test with string path input
            updatedBfile2 = worker.bfile_set(originalPath, specs, testCase.WorkDir);
            testCase.verifyClass(updatedBfile2, 'bids.File')
        end

        function testRun_command(testCase)
            % Create worker for this test
            worker = qb.workers.B1prepWorker(testCase.BIDS, testCase.Subject, testCase.Config, testCase.WorkDir, testCase.OutputDir);
            
            % Test with a simple command that should succeed. MATLAB's system() handles 'echo' both on Windows or 'echo' on Unix
            [status, output] = worker.run_command('echo test_output');
            testCase.verifyEqual(status, 0, 'Command should succeed')
            testCase.verifyNotEmpty(output, 'Command should produce output')
        end

    end

end

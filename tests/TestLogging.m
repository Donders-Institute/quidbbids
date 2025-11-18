classdef TestLogging < matlab.unittest.TestCase
    % Unit tests for the Logging class

    properties
        TempDir
        Logger
    end

    methods (TestMethodSetup)
        function setupEnvironment(testCase)

            % Create a temp subject directory
            testCase.TempDir = tempname;
            SubjectDir       = fullfile(testCase.TempDir, 'sub-01', 'ses-01');
            mkdir(SubjectDir)

            % BIDS struct
            bids.init(testCase.TempDir)
            BIDS = bids.layout(testCase.TempDir);

            % Create any concrete worker
            worker = qb.workers.B1prepWorker(BIDS, BIDS.subjects(1), struct(), '', testCase.TempDir);

            testCase.Logger = worker.logger;
        end
    end

    methods (TestMethodTeardown)
        function teardownEnvironment(testCase)
            rmdir(testCase.TempDir, 's')
        end
    end

    methods (Test)

        function testLogInfo(testCase)
            testCase.Logger.info("Test message %d", 123)

            logFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);
            testCase.verifyTrue(isfile(logFile), "The main log file was not created")
            contents = fileread(logFile);
            testCase.verifySubstring(contents, "INFO", "INFO level not written to log")
            testCase.verifySubstring(contents, "Test message 123", "Message not written correctly")
        end

        function testLogVerbose(testCase)
            testCase.Logger.verbose("Verbose %s", "XYZ")

            logFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);
            contents = fileread(logFile);
            testCase.verifySubstring(contents, "VERBOSE", "Verbose level not logged correctly")
            testCase.verifySubstring(contents, "Verbose XYZ")
        end

        function testLogWarning(testCase)
            testCase.Logger.warning("Warn %s %s", "ABC", "DEF");

            warnFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '_warnings.log']);
            mainFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);

            testCase.verifyTrue(isfile(warnFile), "Warning log file not created")
            testCase.verifyTrue(isfile(mainFile), "Main log was not created by warning")
            testCase.verifySubstring(fileread(warnFile), "Warn ABC DEF")
            testCase.verifySubstring(fileread(mainFile), "WARNING")
        end

        function testLogError(testCase)
            testCase.Logger.error("Err %s", "XYZ");

            errFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '_errors.log']);
            mainFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);

            testCase.verifyTrue(isfile(errFile))
            testCase.verifyTrue(isfile(mainFile))
            testCase.verifySubstring(fileread(errFile), "Err XYZ")
            testCase.verifySubstring(fileread(mainFile), "ERROR")
        end

        function testLogException(testCase)
            testCase.verifyError(@() testCase.Logger.exception("Oops %d", 9), "QuIDBBIDS:FatalException", "Expected a raised QuIDBBIDS error")
        end

        function testSubSesParsing(testCase)
            subses = testCase.Logger.sub_ses();

            testCase.verifyEqual(subses, 'sub-01_ses-01', "Subject/session parsing incorrect");
        end

    end
end

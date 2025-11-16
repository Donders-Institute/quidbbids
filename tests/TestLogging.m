classdef TestLogging < matlab.unittest.TestCase
    % Unit tests for the Logging class

    properties
        TempDir
        Logger
    end

    methods (TestMethodSetup)
        function setupEnvironment(testCase)

            % Create a temp subject directory for isolated testing
            testCase.TempDir = tempname;
            SubjectDir       = fullfile(testCase.TempDir, 'sub-01', 'ses-01');
            mkdir(SubjectDir)

            % Create a fake BIDS structure
            BIDS.pth = testCase.TempDir;

            % Define a minimal mock worker class inline (MATLAB allows dynamic class creation for test use)
            MockWorker.outputdir    = testCase.TempDir;
            MockWorker.BIDS         = BIDS;
            MockWorker.subject.path = SubjectDir;

            % Create Logger instance
            testCase.Logger = Logging(struct2obj(MockWorker));  % convert struct to a fake handle object
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
            testCase.verifyContains(contents, "INFO", "INFO level not written to log")
            testCase.verifyContains(contents, "Test message 123", "Message not written correctly")
        end

        function testLogVerbose(testCase)
            testCase.Logger.verbose("Verbose %s", "XYZ")

            logFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);
            contents = fileread(logFile);
            testCase.verifyContains(contents, "VERBOSE", "Verbose level not logged correctly")
            testCase.verifyContains(contents, "Verbose XYZ")
        end

        function testLogWarning(testCase)
            testCase.Logger.warning("Warn %s %s", "ABC", "DEF");

            warnFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '_warnings.log']);
            mainFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);

            testCase.verifyTrue(isfile(warnFile), "Warning log file not created")
            testCase.verifyTrue(isfile(mainFile), "Main log was not created by warning")
            testCase.verifyContains(fileread(warnFile), "Warn ABC DEF")
            testCase.verifyContains(fileread(mainFile), "WARNING")
        end

        function testLogError(testCase)
            testCase.Logger.error("Err %s", "XYZ");

            errFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '_errors.log']);
            mainFile = fullfile(testCase.Logger.outputdir, [testCase.Logger.sub_ses() '.log']);

            testCase.verifyTrue(isfile(errFile))
            testCase.verifyTrue(isfile(mainFile))
            testCase.verifyContains(fileread(errFile), "Err XYZ");
            testCase.verifyContains(fileread(mainFile), "ERROR");
        end

        function testLogException(testCase)
            testCase.verifyError(@() testCase.Logger.exception("Oops %d", 9), "MATLAB:SomeDummyID", ...
                "Expected an error. Update this if you set a specific ID");
        end

        function testSubSesParsing(testCase)
            subses = testCase.Logger.sub_ses();

            testCase.verifyEqual(subses, "sub-01_ses-01", "Subject/session parsing incorrect");
        end

    end
end


function obj = struct2obj(S)
    % Helper function to convert struct to a dummy handle object.
    % Create a dynamic handle class on the fly to host struct fields

    meta.class.fromName('dynamicHandleClassForWorkerMock');
    obj = dynamicHandleClassForWorkerMock();

    for fieldname = fieldnames(S)'
        obj.(fieldname{1}) = S.(fieldname{1});
    end
end

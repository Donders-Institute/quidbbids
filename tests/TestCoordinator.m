classdef TestCoordinator < matlab.unittest.TestCase
    % Unit tests for the abstract Coordinator class

    properties
        TmpDir
        coord       % Concrete Coordinator instance (qb.QuIDBBIDS)
    end

    methods(TestMethodSetup)
        function createTempDir(testCase)
            testCase.TmpDir = tempname;
            mkdir(fullfile(testCase.TmpDir, 'sub-01', 'ses-01'))
            bids.init(testCase.TmpDir)
            testCase.coord = qb.QuIDBBIDS(testCase.TmpDir);
        end
    end

    methods(TestMethodTeardown)
        function removeTempDir(testCase)
            rmdir(testCase.TmpDir, 's')
        end
    end

    methods(Test)

        function testPropertiesInitialized(testCase)
            % Check that key properties are initialized
            testCase.verifyClass(testCase.coord.BIDS, 'struct', "BIDS should be a struct")
            testCase.verifyNotEmpty(testCase.coord.outputdir, "outputdir should be set")
            testCase.verifyNotEmpty(testCase.coord.workdir, "workdir should be set")
            testCase.verifyNotEmpty(testCase.coord.configfile, "configfile should be set")
            testCase.verifyClass(testCase.coord.config, 'struct', "config should be a struct")
            testCase.verifyClass(testCase.coord.resumes, 'struct', "resumes should be a struct")
        end

        function testWorkitems(testCase)
            % Should return all unique workitems across resumes
            items = testCase.coord.workitems();
            testCase.verifyClass(items, 'string', "workitems should be a string array")
            testCase.verifyGreaterThanOrEqual(numel(items), 0, "Should have zero or more workitems")
            testCase.verifyEqual(numel(items), numel(unique(items)), "Workitems should be unique")
        end

        function testGetResumes(testCase)
            % Ensure get_resumes returns properly structured resumes
            resumes = testCase.coord.get_resumes();
            names = fieldnames(resumes);
            testCase.verifyGreaterThanOrEqual(numel(names), 1, "There should be at least one worker resume")

            for name = names'
                res = resumes.(name{1});
                testCase.verifyTrue(isfield(res,'handle') && isa(res.handle,'function_handle'), "Resume must have handle")
                testCase.verifyTrue(isfield(res,'name') && isstring(res.name), "Resume must have name as string")
                testCase.verifyTrue(isfield(res,'description') && isstring(res.description), "Resume must have description as string")
                testCase.verifyTrue(isfield(res,'version') && isstring(res.version), "Resume must have version as string")
                testCase.verifyTrue(isfield(res,'makes') && iscell(res.makes), "Resume must have makes as cell array")
                testCase.verifyTrue(isfield(res,'needs') && iscell(res.needs), "Resume must have needs as cell array")
                testCase.verifyTrue(isfield(res,'usesGPU') && islogical(res.usesGPU), "Resume must have usesGPU as logical")
                testCase.verifyTrue(isfield(res,'preferred') && islogical(res.preferred), "Resume must have preferred as logical")
            end
        end

    end
end

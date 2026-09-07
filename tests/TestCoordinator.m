classdef TestCoordinator < BaseTest
    % Unit tests for the abstract Coordinator class

    properties
        TmpDir
        quidb_empty       % Concrete Coordinator instance (qb.QuIDBBIDS) for an empty BIDS folder
        quidb_megre       % Concrete Coordinator instance (qb.QuIDBBIDS) for the qmri_megre example BIDS folder
    end

    methods (TestClassSetup)
        function setupBidsExamples(testCase)
            % Clone bids-examples repository once for all test methods in this class
            if ~exist(testCase.BidsExamplesRepo, 'dir')
                system(sprintf('git clone --depth 1 %s %s', 'https://github.com/bids-standard/bids-examples.git', testCase.BidsExamplesRepo));
            end
            
            % Initialize example BIDS layout once for all test methods
            testCase.quidb_megre = qb.QuIDBBIDS(fullfile(testCase.BidsExamplesRepo, 'qmri_megre'));
        end
    end

    methods(TestMethodSetup)
        function createTempDir(testCase)
            testCase.TmpDir = tempname;
            mkdir(fullfile(testCase.TmpDir))
            bids.init(testCase.TmpDir)
            testCase.quidb_empty = qb.QuIDBBIDS(testCase.TmpDir);
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
            testCase.verifyClass(testCase.quidb_empty.BIDS, 'struct', "BIDS should be a struct")
            testCase.verifyNotEmpty(testCase.quidb_empty.outputdir, "outputdir should be set")
            testCase.verifyNotEmpty(testCase.quidb_empty.workdir, "workdir should be set")
            testCase.verifyNotEmpty(testCase.quidb_empty.configfile, "configfile should be set")
            testCase.verifyClass(testCase.quidb_empty.config, 'struct', "config should be a struct")
            testCase.verifyClass(testCase.quidb_empty.resumes, 'struct', "resumes should be a struct")
        end

        function testDeliverables(testCase)
            % Check that deliverables is a valid string row
            testCase.verifyEmpty(testCase.quidb_empty.deliverables, 'deliverables should be empty')
            testCase.quidb_empty.deliverables = ["a", "b", "c"];
            testCase.verifyEmpty(testCase.quidb_empty.deliverables, 'deliverables should be empty')
            testCase.verifyWarning(@() setfield(testCase.quidb_empty, deliverables = ["a", "b", "c"]), 'QuIDBBIDS:Deliverables:Ambiguous', 'Should throw ambiguous deliverable warning')
            testCase.quidb_empty.deliverables = ["R1map"; "ME.*Dmag"];
            testCase.verifyEqual(testCase.quidb_empty.deliverables, ["R1map", "ME.*Dmag"])
        end

        function testWorkitems(testCase)
            % Should return all unique workitems across resumes
            items = testCase.quidb_empty.catalog();
            testCase.verifyClass(items, 'string', "workitems should be a string array")
            testCase.verifyGreaterThanOrEqual(numel(items), 0, "Should have zero or more workitems")
            testCase.verifyEqual(numel(items), numel(unique(items)), "Workitems should be unique")
        end

        function testGetResumes(testCase)
            % Ensure get_resumes returns properly structured resumes
            resumes = testCase.quidb_empty.resumes;     % QuIDBBIDS only masks the workflow in case there are raw subject folders in the BIDS folder, so RESUMES represents the complete set of workers
            names = fieldnames(resumes);
            testCase.verifyGreaterThanOrEqual(numel(names), 10, "There should be at least ten worker resumes")

            for name = names'
                res = resumes.(name{1});
                testCase.verifyTrue(isfield(res,'handle') && isa(res.handle,'function_handle'), "Resume must have handle")
                testCase.verifyTrue(isfield(res,'name') && isstring(res.name), "Resume must have name as string")
                testCase.verifyTrue(isfield(res,'description') && isstring(res.description), "Resume must have description as string")
                testCase.verifyTrue(isfield(res,'makes') && isstring(res.makes) && isrow(res.makes), "Resume must have makes as list")
                testCase.verifyTrue(isfield(res,'needs') && (isempty(res.needs) || (isstring(res.needs) && isrow(res.needs))), "Resume must have needs as list")
                testCase.verifyTrue(isfield(res,'usesGPU') && islogical(res.usesGPU), "Resume must have usesGPU as logical")
                testCase.verifyTrue(isfield(res,'preferred') && islogical(res.preferred), "Resume must have preferred as logical")
            end

            % Ensure get_resumes returns is properly masked when there are raw subject folders in the BIDS folder
            testCase.verifyEqual(fieldnames(testCase.quidb_megre.resumes), {'MEGREprepWorker'; 'QSMWorker'})
            testCase.verifyLessThan(length(testCase.quidb_megre.catalog()), 15, "There should be less than fifteen work-items in the catalog")
        end

    end
end

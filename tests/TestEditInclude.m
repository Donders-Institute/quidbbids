classdef TestEditInclude < BaseTest
    % TestEditInclude - Tests for qb.GUI.EditInclude

    properties
        BIDS            % BIDS layout for current test method
    end

    methods (TestClassSetup)
        function setupBidsExamples(testCase)
            % Clone bids-examples repository once for all test methods in this class
            if ~exist(testCase.BidsExamplesRepo, 'dir')
                system(sprintf('git clone --depth 1 %s %s', 'https://github.com/bids-standard/bids-examples.git', testCase.BidsExamplesRepo));
            end
            
            % Initialize BIDS layout once for all test methods
            testCase.BIDS = bids.layout(fullfile(testCase.BidsExamplesRepo, 'qmri_vfa'));
        end
    end

    methods(Test)
        
        function testConstructor(testCase)
            % Test basic EditInclude construction
            include = struct('modality', {{'anat', 'fmap'}}, 'suffix', {{'MEGRE', 'VFA'}});
            
            gui = qb.GUI.EditInclude(include, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Verify properties are set
            testCase.verifyClass(gui, 'qb.GUI.EditInclude')
            testCase.verifyClass(gui.NodeMap, 'containers.Map')
            
            delete(gui)
        end

        function testTreeStructure(testCase)
            % Test that the tree is built correctly
            include = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            
            gui = qb.GUI.EditInclude(include, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Verify tree has root nodes
            testCase.verifyGreaterThan(length(gui.Tree.Children), 0, 'Tree should have root nodes')
            
            % Check that subjects are in the tree
            nodeTexts = {gui.Tree.Children.Text};
            testCase.verifyTrue(any(contains(nodeTexts, 'sub-')))
            
            delete(gui)
        end

        function testIncludeFilter(testCase)
            % Test that the include filter JSON field is populated correctly
            include = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            
            gui = qb.GUI.EditInclude(include, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Verify the input field contains the JSON representation
            expectedJSON = jsonencode(include, 'PrettyPrint', true);
            testCase.verifyEqual(strjoin(gui.InputField.Value, newline), expectedJSON)
            
            delete(gui)
        end

        function testNodeMap(testCase)
            % Test that NodeMap is populated with paths and tree nodes
            include = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            
            gui = qb.GUI.EditInclude(include, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Verify NodeMap is not empty
            testCase.verifyGreaterThan(length(keys(gui.NodeMap)), 0, 'NodeMap should have entries')
            
            % Verify that at least one key contains a subject directory
            hasSubject = false;
            keysList = keys(gui.NodeMap);
            for i = 1:length(keysList)
                if contains(keysList{i}, 'sub-')
                    hasSubject = true;
                    break
                end
            end
            testCase.verifyTrue(hasSubject, 'NodeMap should contain subject path')
            
            % Verify that values are uitreenode objects
            allValues = values(gui.NodeMap);
            testCase.verifyTrue(~isempty(allValues), 'NodeMap should have values')
            testCase.verifyClass(allValues{1}, 'matlab.ui.container.TreeNode')
            
            delete(gui)
        end

        function testReset(testCase)
            % Test that reset restores the original include filter
            original = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            modified = struct('modality', {{'fmap'}}, 'suffix', {{'VFA'}});
            
            gui = qb.GUI.EditInclude(original, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Modify the current include
            gui.IncludeCurrent = modified;
            
            % Call reset
            gui.onReset()
            
            % Verify it's back to original
            testCase.verifyEqual(gui.IncludeCurrent, original)
            % InputField.Value is a cell array of strings - convert to char for comparison
            actualValue = strjoin(gui.InputField.Value, newline);
            expectedValue = jsonencode(original, 'PrettyPrint', true);
            testCase.verifyEqual(actualValue, expectedValue)
            
            delete(gui)
        end

        function testDone(testCase)
            % Test that Done sets the result
            include = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            
            gui = qb.GUI.EditInclude(include, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Modify the current include by creating a new struct
            gui.IncludeCurrent = struct('modality', {{'fmap'}}, 'suffix', {{'VFA'}});
            
            % Call done
            gui.onDone()
            
            % Verify result is set to the current value (not the original)
            testCase.verifyEqual(gui.IncludeResult.modality, gui.IncludeCurrent.modality)
            testCase.verifyEqual(gui.IncludeResult.suffix, gui.IncludeCurrent.suffix)
            
            delete(gui)
        end

        function testCancel(testCase)
            % Test that Cancel restores the original
            original = struct('modality', {{'anat'}}, 'suffix', {{'MEGRE'}});
            
            gui = qb.GUI.EditInclude(original, testCase.BIDS);
            gui.Fig.Visible = 'off';
            
            % Modify the current include
            gui.IncludeCurrent = struct('modality', {{'fmap'}}, 'suffix', {{'VFA'}});
            
            % Call cancel
            gui.onCancel()
            
            % Verify result is the original
            testCase.verifyEqual(gui.IncludeResult, original)
            
            delete(gui)
        end
    end

end

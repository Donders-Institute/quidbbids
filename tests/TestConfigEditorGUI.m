classdef TestConfigEditorGUI < BaseTest
    % TestConfigEditorGUI  Comprehensive tests for qb.GUI.ConfigEditor
    % Uses a temporary copy of qb.config_default.json to avoid modifying the repo file.

    properties
        TempJSONFile
        Config
        DefaultJSONPath
    end

    methods(TestMethodSetup)
        function setupDefaultConfig(testCase)
            % Path to default config in the repo
            testCase.DefaultJSONPath = fullfile(fileparts(mfilename('fullpath')), fullfile('..','+qb','private','config_default.json'));

            % Copy to temp file for safe testing
            testCase.TempJSONFile = [tempname, '.json'];
            copyfile(testCase.DefaultJSONPath, testCase.TempJSONFile);

            % Load into MATLAB struct
            testCase.Config = jsondecode(fileread(testCase.TempJSONFile));
        end
    end

    methods(TestMethodTeardown)
        function cleanupTempFile(testCase)
            if exist(testCase.TempJSONFile,'file')
                delete(testCase.TempJSONFile);
            end
        end
    end

    methods(Test)
        function testConstructorLoadsConfig(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, [], {'General','QSMWorker'});
            gui.Fig.Visible = 'off';

            % Root nodes contain requested workers
            testCase.verifyTrue(all(ismember({'General','QSMWorker'}, {gui.RootNodes.Text})));

            delete(gui)
        end

        function testSearch(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, testCase.Config);
            gui.Fig.Visible = 'off';

            % Test incremental search (ValueChangingFcn)
            gui.SearchField.Value = 'gyro';
            gui.onSearchLive(struct('Value', 'gyro'));  % Use onSearchLive for incremental search
            testCase.verifyGreaterThanOrEqual(numel(gui.SearchMatches), 1);
            testCase.verifyEqual(gui.SearchMatches{1}.Text, 'gyro');

            % Test search with wildcard using incremental search
            gui.SearchField.Value = '*WH*';
            gui.onSearchLive(struct('Value', '*WH*'));  % Use onSearchLive for incremental search
            matches = {gui.SearchMatches{:}.Text};
            testCase.verifyTrue(any(contains(matches,'FWHM')));

            delete(gui);
        end

        function testSearchEnterKeyAlert(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, testCase.Config);
            gui.Fig.Visible = 'off';

            % Test that Enter key behavior - we can't test the uialert directly
            % since it requires visible figure, but we can verify the search logic
            
            % First test with a valid search to ensure matches work
            gui.SearchField.Value = 'gyro';
            gui.onSearchEnter(struct('Value', 'gyro'));
            testCase.verifyGreaterThanOrEqual(numel(gui.SearchMatches), 1);
            
            % Now test with nonexistent search - verify search state is cleared
            gui.SearchField.Value = 'nonexistent123';
            
            % Temporarily make figure visible to avoid uialert error
            gui.Fig.Visible = 'on';            
            gui.onSearchEnter(struct('Value', 'nonexistent123'))
            gui.Fig.Visible = 'off';
            
            % Verify no matches were found and search state is reset
            testCase.verifyEmpty(gui.SearchMatches)
            testCase.verifyEqual(gui.SearchIndex, 0)

            delete(gui);
        end
        
        function testIncrementalSearchUpdates(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, [], {});
            gui.Fig.Visible = 'off';

            % Test that incremental search updates with each character
            gui.onSearchLive(struct('Value', 'g'))   % Type 'g'
            initialMatches = numel(gui.SearchMatches);
            
            gui.onSearchLive(struct('Value', 'gy'))   % Type 'y' - more specific
            refinedMatches = numel(gui.SearchMatches);
            
            % The matches should become more specific (fewer or equal matches)
            testCase.verifyTrue(refinedMatches <= initialMatches)
            
            % Should find 'gyro' specifically
            if refinedMatches > 0
                matchTexts = {gui.SearchMatches{:}.Text};
                testCase.verifyTrue(any(contains(matchTexts, 'gyro')))
            end

            delete(gui)
        end

        function testLeafEdit(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, [], {'General'});
            gui.Fig.Visible = 'off';
        
            % Select leaf: General -> gyro
            generalNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'General'));
            gyroNode = generalNode.Children(strcmp({generalNode.Children.Text}, 'gyro'));
            gui.Tree.SelectedNodes = gyroNode;
        
            % Verify initial state
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892)
            testCase.verifyEqual(gui.Config.General.gyro.value, 42.57747892)
        
            % Update value
            gui.ValField.Value = '50';
            gui.updateLeafFromField()
        
            % Verify BOTH tree node and config are updated
            testCase.verifyEqual(gyroNode.NodeData.value, 50)
            testCase.verifyEqual(gui.Config.General.gyro.value, 50)
        
            % Reset leaf
            gui.resetLeaf()
            
            % Verify BOTH are reset
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892)
            testCase.verifyEqual(gui.Config.General.gyro.value, 42.57747892)
        
            delete(gui)
        end

        function testNestedLeafEdit(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, [], {'MCRWorker'});
            gui.Fig.Visible = 'off';
        
            % Navigate to nested leaf
            mcrNode    = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'MCRWorker'));
            mcrSubNode = mcrNode.Children(strcmp({mcrNode.Children.Text}, 'fitting'));
            gpuNode    = mcrSubNode.Children(strcmp({mcrSubNode.Children.Text}, 'GPU'));
            leafNode   = gpuNode.Children(strcmp({gpuNode.Children.Text}, 'start'));
        
            % Verify initial state
            testCase.verifyEqual(leafNode.NodeData.value, 'prior');
            testCase.verifyEqual(gui.Config.MCRWorker.fitting.GPU.start.value, 'prior');
        
            % METHOD 1: Test direct update and manual reset using existing methods
            % Update the value
            nodeData = leafNode.NodeData;
            nodeData.value = 'Test';
            leafNode.NodeData = nodeData;
            path = {'MCRWorker', 'fitting', 'GPU', 'start'};
            gui.Config = gui.setValueInConfig(gui.Config, path, nodeData);
            
            testCase.verifyEqual(leafNode.NodeData.value, 'Test')
            testCase.verifyEqual(gui.Config.MCRWorker.fitting.GPU.start.value, 'Test')
        
            % Reset using GUI logic
            gui.Tree.SelectedNodes = leafNode;
            gui.resetLeaf()

            testCase.verifyEqual(leafNode.NodeData.value, 'prior')
            testCase.verifyEqual(gui.Config.MCRWorker.fitting.GPU.start.value, 'prior')
        
            delete(gui)
        end

        function testSaveNestedConfig(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, [], {'QSMWorker'});
            gui.Fig.Visible = 'off';

            % Find the specific leaf node in the tree
            qsmNode    = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'QSMWorker'));
            qsmSubNode = qsmNode.Children(strcmp({qsmNode.Children.Text}, 'QSM'));
            bfrNode    = qsmSubNode.Children(strcmp({qsmSubNode.Children.Text}, 'bfr'));
            leafNode   = bfrNode.Children(strcmp({bfrNode.Children.Text}, 'refine_order'));

            % Update the tree node directly (this is what the UI would do)
            nodeData          = leafNode.NodeData;
            nodeData.value    = 999;
            leafNode.NodeData = nodeData;

            % Also update the main config to keep them in sync
            path = {'QSMWorker', 'QSM', 'bfr', 'refine_order'};
            gui.Config = gui.setValueInConfig(gui.Config, path, nodeData);

            % Verify both tree and config are updated
            testCase.verifyEqual(leafNode.NodeData.value, 999)
            testCase.verifyEqual(gui.Config.QSMWorker.QSM.bfr.refine_order.value, 999)

            % Save and load back and verify the change persisted
            gui.saveConfig()
            savedConfig = jsondecode(fileread(testCase.TempJSONFile));
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.bfr.refine_order.value, 999)
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.qsm.lambda.value, 0.05)  % unchanged

            delete(gui)
        end

        function testLeafEditVariousDataTypes(testCase)
            gui = qb.GUI.ConfigEditor(testCase.TempJSONFile, testCase.Config);
            gui.Fig.Visible = 'off';

            %--- Test 1: Numeric scalar (gyro)
            generalNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'General'));
            gyroNode = generalNode.Children(strcmp({generalNode.Children.Text}, 'gyro'));
            gui.Tree.SelectedNodes = gyroNode;
            
            % Verify initial state
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892);
            
            % Update to different numeric value
            gui.ValField.Value = '99.5';
            gui.updateLeafFromField()
            testCase.verifyEqual(gyroNode.NodeData.value, 99.5)
            gui.resetLeaf()
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892)

            %--- Test 2: String value
            mcrNode    = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'MCRWorker'));
            mcrSubNode = mcrNode.Children(strcmp({mcrNode.Children.Text}, 'fitting'));
            unwrapNode = mcrSubNode.Children(strcmp({mcrSubNode.Children.Text}, 'GPU'));
            stringNode = unwrapNode.Children(strcmp({unwrapNode.Children.Text}, 'start'));
            
            gui.Tree.SelectedNodes = stringNode;
            originalValue = stringNode.NodeData.value;
            
            % Test string update
            gui.ValField.Value = '"New String Value"';
            gui.updateLeafFromField()
            testCase.verifyEqual(stringNode.NodeData.value, "New String Value")
            
            % Test without quotes (should still work)
            gui.ValField.Value = 'Another String';
            gui.updateLeafFromField()
            testCase.verifyEqual(stringNode.NodeData.value, "Another String")
            
            gui.resetLeaf()
            testCase.verifyEqual(stringNode.NodeData.value, originalValue)
            
            %--- Test 3: Numeric array
            qsmNode    = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'QSMWorker'));
            qsmSubNode = qsmNode.Children(strcmp({qsmNode.Children.Text}, 'QSM'));
            bfrNode    = qsmSubNode.Children(strcmp({qsmSubNode.Children.Text}, 'bfr'));
            arrayNode  = bfrNode.Children(strcmp({bfrNode.Children.Text}, 'radius'));
            gui.Tree.SelectedNodes = arrayNode;
            originalArrayValue     = arrayNode.NodeData.value;
            
            % Test array input in JSON format
            gui.ValField.Value = '[1, 2, 3, 4]';    % JSON style -> column vector
            gui.updateLeafFromField()
            testCase.verifyEqual(arrayNode.NodeData.value, [1, 2, 3, 4]')
            
            % Test MATLAB array format
            gui.ValField.Value = '[5 6 7]';         % Not valid JSON, but MATLAB style
            gui.updateLeafFromField()
            testCase.verifyEqual(arrayNode.NodeData.value, [5, 6, 7])
            
            gui.resetLeaf()
            testCase.verifyEqual(arrayNode.NodeData.value, originalArrayValue)
            
            %--- Test 4: Logical values
            unwrapNode  = qsmSubNode.Children(strcmp({qsmSubNode.Children.Text}, 'unwrap'));
            logicalNode = unwrapNode.Children(strcmp({unwrapNode.Children.Text}, 'isEddyCorrect'));
            gui.Tree.SelectedNodes = logicalNode;
            originalLogicalValue   = logicalNode.NodeData.value;
            
            % Test different boolean representations
            gui.ValField.Value = 'true';
            gui.updateLeafFromField()
            testCase.verifyEqual(logicalNode.NodeData.value, true)
            
            gui.ValField.Value = 'false';
            gui.updateLeafFromField()
            testCase.verifyEqual(logicalNode.NodeData.value, false)
            
            gui.ValField.Value = '0';
            gui.updateLeafFromField()
            testCase.verifyEqual(logicalNode.NodeData.value, false)
            
            gui.ValField.Value = '1';
            gui.updateLeafFromField()
            testCase.verifyEqual(logicalNode.NodeData.value, true)
            
            gui.resetLeaf()
            testCase.verifyEqual(logicalNode.NodeData.value, originalLogicalValue)
            
            delete(gui)
        end

    end

end

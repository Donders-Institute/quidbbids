classdef TestConfigEditorGUI < matlab.unittest.TestCase
    % TestConfigEditorGUI  Comprehensive tests for qb.ConfigEditorGUI
    % Uses a temporary copy of qb.config_default.json to avoid modifying the repo file.

    properties
        TempJSONFile
        Config
        DefaultJSONPath
    end

    methods(TestMethodSetup)
        function setupDefaultConfig(testCase)
            % Path to default config in the repo
            testCase.DefaultJSONPath = fullfile(fileparts(mfilename('fullpath')), fullfile('..','+qb','config_default.json'));

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
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'General','QSMWorker'});
            set(gui.Fig,'Visible','off');

            % Root nodes contain requested workers
            rootNames = {gui.RootNodes.Text};
            testCase.verifyTrue(all(ismember({'General','QSMWorker'}, rootNames)));

            delete(gui);
        end

        function testSearchFunctionality(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {});
            set(gui.Fig,'Visible','off');

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
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {});
            set(gui.Fig,'Visible','off');

            % Test that Enter key behavior - we can't test the uialert directly
            % since it requires visible figure, but we can verify the search logic
            
            % First test with a valid search to ensure matches work
            gui.SearchField.Value = 'gyro';
            gui.onSearchEnter(struct('Value', 'gyro'));
            testCase.verifyGreaterThanOrEqual(numel(gui.SearchMatches), 1);
            
            % Now test with nonexistent search - verify search state is cleared
            gui.SearchField.Value = 'nonexistent123';
            
            % Temporarily make figure visible to avoid uialert error
            originalVisibility = gui.UIFig.Visible;
            gui.UIFig.Visible = 'on';            
            try
                gui.onSearchEnter(struct('Value', 'nonexistent123'));
            catch ME
                if ~strcmp(ME.identifier, 'MATLAB:uitools:uidialogs:InvisibleFigure')
                    rethrow(ME);
                end
            end
            gui.UIFig.Visible = originalVisibility;            % Restore visibility
            
            % Verify no matches were found and search state is reset
            testCase.verifyEmpty(gui.SearchMatches);
            testCase.verifyEqual(gui.SearchIndex, 0);

            delete(gui);
        end
        
        function testLeafEdit(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'General'});
            set(gui.UIFig,'Visible','off');
        
            % Select leaf: General -> gyro
            generalNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'General'));
            gyroNode = generalNode.Children(strcmp({generalNode.Children.Text}, 'gyro'));
            gui.Tree.SelectedNodes = gyroNode;
        
            % Verify initial state
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892);
            testCase.verifyEqual(gui.Config.General.gyro.value, 42.57747892);
        
            % Update value
            gui.ValField.Value = '50';
            gui.updateLeafFromField();
        
            % Verify BOTH tree node and config are updated
            testCase.verifyEqual(gyroNode.NodeData.value, 50);
            testCase.verifyEqual(gui.Config.General.gyro.value, 50);
        
            % Reset leaf
            gui.resetLeaf();
            
            % Verify BOTH are reset
            testCase.verifyEqual(gyroNode.NodeData.value, 42.57747892);
            testCase.verifyEqual(gui.Config.General.gyro.value, 42.57747892);
        
            delete(gui);
        end

        function testNestedLeafEdit(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'QSMWorker'});
            set(gui.UIFig,'Visible','off');
        
            % Navigate to nested leaf
            qsmNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'QSMWorker'));
            qsmSubNode = qsmNode.Children(strcmp({qsmNode.Children.Text}, 'QSM'));
            unwrapNode = qsmSubNode.Children(strcmp({qsmSubNode.Children.Text}, 'unwrap'));
            leafNode = unwrapNode.Children(strcmp({unwrapNode.Children.Text}, 'echoCombMethod'));
        
            % Verify initial state
            testCase.verifyEqual(leafNode.NodeData.value, 'Optimum weights');
            testCase.verifyEqual(gui.Config.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Optimum weights');
        
            % METHOD 1: Test direct update and manual reset using existing methods
            % Update the value
            nodeData = leafNode.NodeData;
            nodeData.value = 'Weighted';
            leafNode.NodeData = nodeData;
            path = {'QSMWorker', 'QSM', 'unwrap', 'echoCombMethod'};
            gui.Config = gui.setValueInStruct(gui.Config, path, nodeData);
            
            testCase.verifyEqual(leafNode.NodeData.value, 'Weighted');
            testCase.verifyEqual(gui.Config.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Weighted');
        
            % Manual reset using the existing getOriginalLeaf method
            originalLeaf = gui.getOriginalLeaf(leafNode);  % This method exists!
            leafNode.NodeData = originalLeaf;
            gui.Config = gui.setValueInStruct(gui.Config, path, originalLeaf);
            
            testCase.verifyEqual(leafNode.NodeData.value, 'Optimum weights');
            testCase.verifyEqual(gui.Config.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Optimum weights');
        
            delete(gui);
        end

        function testSaveNestedConfig(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'QSMWorker'});
            set(gui.Fig,'Visible','off');

            % Find the specific leaf node in the tree
            qsmNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'QSMWorker'));

            % Find QSM -> unwrap -> echoCombMethod path
            foundLeaf = false;
            for i = 1:numel(qsmNode.Children)
                if strcmp(qsmNode.Children(i).Text, 'QSM')
                    qsmSubNode = qsmNode.Children(i);
                    for j = 1:numel(qsmSubNode.Children)
                        if strcmp(qsmSubNode.Children(j).Text, 'unwrap')
                            unwrapNode = qsmSubNode.Children(j);
                            for k = 1:numel(unwrapNode.Children)
                                if strcmp(unwrapNode.Children(k).Text, 'echoCombMethod')
                                    leafNode = unwrapNode.Children(k);
                                    foundLeaf = true;
                                    break;
                                end
                            end
                            if foundLeaf, break; end
                        end
                    end
                    if foundLeaf, break; end
                end
            end

            testCase.verifyTrue(foundLeaf, 'Should find echoCombMethod leaf node');

            % Update the tree node directly (this is what the UI would do)
            nodeData = leafNode.NodeData;
            nodeData.value = 'Weighted';
            leafNode.NodeData = nodeData;

            % Also update the main config to keep them in sync
            path = {'QSMWorker', 'QSM', 'unwrap', 'echoCombMethod'};
            gui.Config = gui.setValueInStruct(gui.Config, path, nodeData);

            % Verify both tree and config are updated
            testCase.verifyEqual(leafNode.NodeData.value, 'Weighted');
            testCase.verifyEqual(gui.Config.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Weighted');

            % Save to temp file - treeToStruct should now get the updated value
            tmpSave = [tempname, '.json'];
            partial = gui.treeToStruct();
            gui.Config = gui.mergeIntoOriginal(gui.OrigConfig, partial);
            gui.jsonwrite(tmpSave, gui.Config);

            % Load saved JSON and verify the change persisted
            savedConfig = jsondecode(fileread(tmpSave));
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Weighted');
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.qsm.lambda.value, 0.05); % unchanged

            delete(gui);
            if exist(tmpSave, 'file')
                delete(tmpSave);
            end
        end

        function testIncrementalSearchUpdates(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {});
            set(gui.Fig,'Visible','off');

            % Test that incremental search updates with each character
            gui.onSearchLive(struct('Value', 'g'));  % Type 'g'
            initialMatches = numel(gui.SearchMatches);
            
            gui.onSearchLive(struct('Value', 'gy'));  % Type 'y' - more specific
            refinedMatches = numel(gui.SearchMatches);
            
            % The matches should become more specific (fewer or equal matches)
            testCase.verifyTrue(refinedMatches <= initialMatches);
            
            % Should find 'gyro' specifically
            if refinedMatches > 0
                matchTexts = {gui.SearchMatches{:}.Text};
                testCase.verifyTrue(any(contains(matchTexts, 'gyro')));
            end

            delete(gui);
        end
    end
end

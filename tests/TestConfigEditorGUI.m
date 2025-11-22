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

        function testLeafEdit(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'General'});
            set(gui.Fig,'Visible','off');

            % Select leaf: General -> gyro
            node = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'General')).Children(strcmp({gui.RootNodes(strcmp({gui.RootNodes.Text}, 'General')).Children.Text}, 'gyro'));
            gui.Tree.SelectedNodes = node;

            % Update value
            gui.ValField.Value = '50';
            gui.updateLeafFromField();

            testCase.verifyEqual(gui.Config.General.gyro.value, 50);

            % Reset leaf
            gui.resetLeaf();
            testCase.verifyEqual(gui.Config.General.gyro.value, 42.57747892);

            delete(gui);
        end

        function testSearchFunctionality(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {});
            set(gui.Fig,'Visible','off');

            % Search exact leaf
            gui.SearchField.Value = 'gyro';
            gui.onSearchFieldChanged(struct('Source', gui.SearchField));
            testCase.verifyGreaterThanOrEqual(numel(gui.SearchMatches), 1);
            testCase.verifyEqual(gui.SearchMatches{1}.Text, 'gyro');

            % Search with wildcard
            gui.SearchField.Value = '*WH*';
            gui.onSearchFieldChanged(struct('Source', gui.SearchField));
            matches = {gui.SearchMatches{:}.Text};
            testCase.verifyTrue(any(contains(matches,'FWHM')));

            delete(gui);
        end

        function testSaveNestedConfig(testCase)
            gui = qb.ConfigEditorGUI(testCase.TempJSONFile, {'QSMWorker'});
            set(gui.Fig,'Visible','off');

            % Change nested value
            qsmNode = gui.RootNodes(strcmp({gui.RootNodes.Text}, 'QSMWorker')).Children(1); % QSM
            unwrapNode = qsmNode.Children(1); % unwrap
            leafNode = unwrapNode.Children(1); % echoCombMethod

            gui.Tree.SelectedNodes = leafNode;
            gui.ValField.Value = '"Weighted"';
            gui.updateLeafFromField();

            % Save to temp file
            tmpSave = [tempname, '.json'];
            partial = gui.treeToStruct();
            gui.Config = gui.mergeIntoOriginal(gui.OrigConfig, partial);
            gui.jsonwrite(tmpSave, gui.Config);

            % Load saved JSON
            savedConfig = jsondecode(fileread(tmpSave));
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.unwrap.echoCombMethod.value, 'Weighted');
            testCase.verifyEqual(savedConfig.QSMWorker.QSM.qsm.lambda.value, 0.05); % unchanged

            delete(gui);
            delete(tmpSave);
        end
    end
end

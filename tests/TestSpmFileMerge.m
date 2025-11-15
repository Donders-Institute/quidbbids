classdef TestSpmFileMerge < matlab.unittest.TestCase
    % TestSpmFileMerge - Unit tests for spm_file_merge_gz function

    properties
        TestData
        TempDir
        NiftiFiles
    end

    methods (TestClassSetup)
        function setupTestClass(testCase)
            % Setup test class - runs once before all tests

            % Create test data paths
            testCase.TestData = fullfile(fileparts(mfilename('fullpath')), '..', 'dependencies', 'spm', 'canonical');
            testCase.TempDir  = tempname;
            mkdir(testCase.TempDir);
        end
    end

    methods (TestClassTeardown)
        function teardownTestClass(testCase)
            % Teardown test class - runs once after all tests
            if exist(testCase.TempDir, 'dir')
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    methods (TestMethodSetup)

        function setupTest(testCase)
            % Create test NIfTI files for testing

            % Delete existing files in TempDir
            delete(fullfile(testCase.TempDir, '*'));

            % Copy canonical NIfTI files to TempDir
            niifiles = {'avg152T1.nii', 'avg152T2.nii'};
            for n = 1:length(niifiles)
                copyfile(fullfile(testCase.TestData, niifiles{n}), testCase.TempDir)
                testCase.NiftiFiles{n} = fullfile(testCase.TempDir, niifiles{n});
            end
            testCase.createSidecars()   % Add JSON sidecars
        end
    end

    methods (Test)
        function testMergeNii(testCase)
            % Test merging regular .nii files without cleanup

            % Prepare inputs
            inputFiles = testCase.NiftiFiles;
            outputFile = fullfile(testCase.TempDir, 'merged_regular.nii');
            nrinputs   = length(testCase.NiftiFiles);

            % Execute function
            V4 = qb.utils.spm_file_merge_gz(inputFiles, outputFile, [], false);

            % Verify outputs
            testCase.assertTrue(isscalar(V4), 'Output should be a single volume struct');
            testCase.assertTrue(isfile(outputFile), 'Output file should exist');
            testCase.assertEqual(V4.dt, 2, 'Output datatype should be 2 (UINT8)');

            % Verify output dimensions (4D with nrinputs volumes)
            outputVol = qb.utils.spm_vol(outputFile);
            testCase.assertEqual(length(outputVol), nrinputs, "Output should have " + nrinputs + "volumes");

            % Verify JSON sidecar was created
            [pth, nm] = fileparts(outputFile);
            jsonOutput = fullfile(pth, [nm '.json']);
            testCase.assertTrue(isfile(jsonOutput), 'JSON sidecar should exist');
            metadata = jsondecode(fileread(jsonOutput));
            testCase.assertTrue(isfield(metadata, 'MagneticFieldStrength'), 'MagneticFieldStrength field should exist');

            % Verify that the input files still exist
            for inputFile = inputFiles
                testCase.assertTrue(isfile(inputFile{1}), 'Input NIfTI file should still exist');
                [pth, nm] = fileparts(inputFile{1});
                jsonSidecar = fullfile(pth, [nm '.json']);
                testCase.assertTrue(isfile(jsonSidecar), 'Input JSON file should still exist');
            end
        end

        function testMergeNiiGz(testCase)
            % Test merging .nii.gz files with cleanup

            nrinputs = length(testCase.NiftiFiles);

            % Prepare gzipped inputs
            for i = 1:nrinputs
                niifile         = testCase.NiftiFiles{i};
                gzippedFiles{i} = [niifile '.gz'];
                gzip(niifile, fileparts(niifile));
                delete(niifile)
            end
            outputFile = fullfile(testCase.TempDir, 'merged_gzipped.nii.gz');

            % Execute function
            V4 = qb.utils.spm_file_merge_gz(gzippedFiles, outputFile, [], true);

            % Verify outputs
            testCase.assertTrue(isscalar(V4), 'Output should be a single volume struct');
            testCase.assertTrue(isfile(outputFile), 'Output file should exist');

            % Verify output is gzipped
            testCase.assertTrue(endsWith(V4.fname, '.gz'), 'Output should be gzipped');
            testCase.assertTrue(isfile(V4.fname), 'Output file should exist');
            testCase.assertEqual(V4.dt, 64, 'Output datatype should be 64 (float32)');

            % Verify JSON sidecar was created
            [pth,nm,ext] = fileparts(outputFile);
            if strcmp(ext,'.gz')
                [pth,nm] = fileparts(fullfile(pth,nm)); % strip .nii
            end
            jsonOutput = fullfile(pth, [nm '.json']);
            testCase.assertTrue(isfile(jsonOutput), 'JSON sidecar should exist');

            % Verify input files were deleted
            for niftiFile = testCase.NiftiFiles
                testCase.assertFalse(isfile(niftiFile{1}), 'Input NIfTI files should be deleted');
                [pth, nm] = fileparts(niftiFile{1});
                jsonSidecar = fullfile(pth, [nm '.json']);
                testCase.assertFalse(isfile(jsonSidecar), 'Input JSON files should be deleted');
            end
        end

        function testMergeMetafields(testCase)
            % Test merging with specific metadata field aggregation

            % Prepare inputs
            Vin        = qb.utils.spm_vol(char(testCase.NiftiFiles));
            outputFile = fullfile(testCase.TempDir, 'merged_meta.nii');
            nrinputs   = length(testCase.NiftiFiles);

            % Test with only one metafield
            metafields = {'EchoTime', 'RepetitionTime'};

            % Execute function
            qb.utils.spm_file_merge_gz(Vin, outputFile, metafields);

            % Verify JSON sidecar
            [pth, nm] = fileparts(outputFile);
            jsonOutput = fullfile(pth, [nm '.json']);
            testCase.assertTrue(isfile(jsonOutput));

            metadata = jsondecode(fileread(jsonOutput));
            for metafield = metafields
                testCase.assertTrue(isfield(metadata, metafield{1}), metafield + " field should exist");
                testCase.assertEqual(length(metadata.(metafield{1})), nrinputs, "EchoTime should have " + nrinputs + " values");
            end
            testCase.assertTrue(isfield(metadata, 'MagneticFieldStrength'));
            testCase.assertTrue(isscalar(metadata.MagneticFieldStrength));

            % Verify input files were deleted
            for niftiFile = testCase.NiftiFiles
                testCase.assertFalse(isfile(niftiFile{1}), 'Input NIfTI files should be deleted');
                [pth, nm] = fileparts(niftiFile{1});
                jsonSidecar = fullfile(pth, [nm '.json']);
                testCase.assertFalse(isfile(jsonSidecar));
            end
        end
    end

    methods (Access = private)

        function createSidecars(testCase)
            % Create JSON sidecar files for testing metadata propagation

            for i = 1:length(testCase.NiftiFiles)
                niftiFile = testCase.NiftiFiles{i};
                [pth, nm] = fileparts(niftiFile);
                jsonFile  = fullfile(pth, [nm '.json']);

                % Create BIDS-style metadata
                metadata = struct();
                metadata.EchoTime = 0.01 * i; % Different values for each file
                metadata.RepetitionTime = 2.0 + 0.1 * (i-1);
                metadata.MagneticFieldStrength = 3.0;
                metadata.PhaseEncodingDirection = 'j';

                % Write JSON file
                fid = fopen(jsonFile, 'w');
                fprintf(fid, '%s', jsonencode(metadata));
                fclose(fid);
            end
        end
    end
end

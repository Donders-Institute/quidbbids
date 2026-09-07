classdef BaseTest < matlab.unittest.TestCase

    properties
        BidsExamplesRepo = fullfile(tempname, 'quidbbids_test_bids_examples')   % Path to the cloned bids-examples repository
    end

    methods(TestClassSetup)
        function addPathDeps(testCase)
            qb.addpath_deps()
        end
        function setupOnce(testCase)
            warning('off', 'MATLAB:graphics:HardwareUnavailable')
        end
    end
end

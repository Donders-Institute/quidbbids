classdef BaseTest < matlab.unittest.TestCase
    methods(TestClassSetup)
        function addPathDeps(testCase)
            qb.addpath_deps()
        end
        function setupOnce(testCase)
            warning('off', 'MATLAB:graphics:HardwareUnavailable')
        end
    end
end

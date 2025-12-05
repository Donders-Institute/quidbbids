classdef BaseTest < matlab.unittest.TestCase
    methods(TestClassSetup)
        function addPathDeps(testCase)
            qb.addpath_deps()
        end
    end
end

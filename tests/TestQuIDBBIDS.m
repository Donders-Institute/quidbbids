classdef TestQuIDBBIDS < matlab.unittest.TestCase

    methods(TestClassSetup)
        % Shared setup for the entire test class
    end
    
    methods(TestMethodSetup)
        % Setup for each test
    end

    methods(Test)

        function test_constructor(testCase)
            % Test basic object construction
            obj = qb.QuIDBBIDS('.');
            testCase.verifyClass(obj, 'qb.QuIDBBIDS');
        end
    
    end
    
end

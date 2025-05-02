classdef TestVersion < matlab.unittest.TestCase
    
    methods(TestClassSetup)
        % Shared setup for the entire test class
    end
    
    methods(TestMethodSetup)
        % Setup for each test
    end
    
    methods(Test)
        
        function test_version(testCase)
            % Test if version() returns a string matching SemVer format (X.Y.Z)
            ver = qb.version();

            % Verify it's a string/char array
            testCase.verifyNotEmpty(ver, 'QuIDBBIDS version string must not be empty');
            testCase.verifyClass(ver, 'char', 'QuIDBBIDS version must be a string/char array');

            % Verify SemVer format (X.Y.Z, optionally with -prerelease or +build)
            pattern = '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$';
            testCase.verifyMatches(ver, pattern, 'QuIDBBIDS version must follow SemVer pattern (X.Y.Z with optional -prerelease or +build)');
        end
        
    end
    
end

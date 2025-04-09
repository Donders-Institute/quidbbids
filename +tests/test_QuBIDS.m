classdef test_version < matlab.unittest.TestCase
    % Test class for QuBIDS
    
    methods (Test)
        function testReturnsSemVerString(testCase)
            % Test if version() returns a string matching SemVer format (X.Y.Z)
            ver = QuBIDS.version();
            
            % Verify it's a string/char array
            testCase.verifyNotEmpty(ver, 'Version string must not be empty');
            testCase.verifyClass(ver, 'char', 'Version must be a string/char array');
            
            % Verify SemVer format (X.Y.Z, optionally with -prerelease or +build)
            pattern = '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$';
            testCase.verifyMatches(ver, pattern, 'Version must follow SemVer pattern (X.Y.Z with optional -prerelease or +build)');
        end
    end
end

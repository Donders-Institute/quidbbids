function [status, output] = run_command(command, silent)
%RUN_COMMAND Execute a shell command and display its output.
%
%   [STATUS, OUTPUT] = RUN_COMMAND(COMMAND) prints the specified shell 
%   COMMAND to the console, executes it using SYSTEM(), and returns the 
%   STATUS and OUTPUT.
%
%   If the command fails (i.e., STATUS ~= 0), an error is raised with
%   a message containing the exit status and the command's output.
%
%   Inputs:
%       COMMAND - A string containing the shell command to execute.
%       SILENT  - (Optional) If true, suppress output unless there is an error.
%                 Default is false.%
%   Outputs:
%       STATUS  - Exit code returned by the SYSTEM command.
%       OUTPUT  - Command-line output returned by the SYSTEM command.

if nargin < 2
    silent = false;
end

if ~silent
    fprintf('$ %s\n', command);
end

[status, output] = system(command);

% Check for error
if status ~= 0
    error('Command failed with status %d\nOutput:\n%s', status, output);
elseif ~silent && ~isempty(output)
    fprintf('%s\n', output);
end

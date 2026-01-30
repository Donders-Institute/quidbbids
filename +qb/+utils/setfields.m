function s = setfields(s, varargin)
%SETFIELDS Set multiple fields of a struct
%
%   S = SETFIELDS(S, 'field1', value1, 'field2', value2, ...)
%   sets multiple fields of the struct S to the specified values.
%   If a field does not exist, it is created.
%
%   Example:
%       s = struct('a', 1, 'b', 2);
%       s = setfields(s, 'a', 10, 'c', 30);
%       % Result: s = struct('a', 10, 'b', 2, 'c', 30);
%
%   Inputs:
%       S - Input struct
%       'field1', value1, 'field2', value2, ... - Field-value pairs to set
% 
%   See also: setfield

if mod(length(varargin), 2) ~= 0
    error('QuIDBBIDS:setfields:InvalidInput', 'Field-value pairs must be provided in pairs')
end

for k = 1:2:length(varargin)
    s.(varargin{k}) = varargin{k+1};
end

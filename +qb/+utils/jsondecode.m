function S = jsondecode(jsonText)
    % JSONDECODE Decode JSON text into MATLAB struct with row vectors
    %
    % S = qb.utils.jsondecode(jsonText) decodes the JSON text in JSONTEXT
    % and converts any vectors to row vectors in the resulting struct S.
    %
    % This is a wrapper around the built-in JSONDECODE function that ensures
    % that all vectors in the resulting struct are row vectors, which is
    % often more convenient to work with in MATLAB.
    %
    % Example:
    %   jsonText = '{"name": "example", "values": [1; 2; 3]}';
    %   S = qb.utils.jsondecode(jsonText);
    %   disp(S.values);  % Displays: 1 2 3 (row vector)
    %
    % See also: jsondecode

    % Convert vectors to row vectors
    S = make_rows(jsondecode(jsonText));
end


function Srow = make_rows(S)
    % Recursively convert JSON vectors to rows

    Srow = struct();
    for key = fieldnames(S)'
        val = S.(char(key));
        if isstruct(val)
            Srow.(char(key)) = make_rows(val);
        elseif iscolumn(val)
            Srow.(char(key)) = val';
        else
            Srow.(char(key)) = val;
        end
    end
end

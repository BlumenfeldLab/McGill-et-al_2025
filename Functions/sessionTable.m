%{
Date Created: 2/29/2024
Description: This function constructs a standardized session table. Each 
row in the table represents a single behavioral session and includes the 
core identifying metadata required to uniquely specify that session for a 
given animal. This core information is stored within the columns labeled
'animalName', 'sessionDate', and 'sessionNumber'.
%}


function sessionTable = sessionTable(varargin)
    % SESSIONTABLE  Create an empty or preallocated session-level metadata 
    %   table.
    %
    %   sessionTable = SESSIONTABLE() returns a 1-row table with the 
    %   required columns that define a behavioral session: 'animalName', 
    %   'sessionDate', and 'sessionNumber'.
    %
    %   sessionTable = SESSIONTABLE('numSessions', N) preallocates a 
    %   session table with N rows and the same set of required variables, 
    %   which can then be populated with session metadata.
    %
    %   This function ensures that all session tables used in the analysis
    %   pipeline share a consistent format, allowing downstream functions 
    %   to reliably interpret and manipulate session-level data.
    %
    %   See also isSessionnTable, sessionTableFun, trialTable.

    % A session table is a table where each row represents a single session
    % conducted for some behavioral experiment. To uniquely identify each
    % session, the table must contain: the animal name, the session date,
    % and the ordinal session number for that date (e.g., the first or
    % second session conducted).
    requiredColumnsNames = {'animalName', ...
        'sessionDate', ...
        'sessionNumber'};
    requiredColumnsTypes = {'string', ...
        'datetime', ...
        'double'};
    numRequiredColumns = numel(requiredColumnsNames);

    % parse and validate inputs
    p = inputParser;
    p.addOptional('numSessions',1,@isnumeric)
    p.parse(varargin{:})

    % Create the session table with the required schema.
    sessionTable = table(...
        'Size', [p.Results.numSessions numRequiredColumns],...
        'VariableNames', requiredColumnsNames, ...
        'VariableTypes', requiredColumnsTypes);

end
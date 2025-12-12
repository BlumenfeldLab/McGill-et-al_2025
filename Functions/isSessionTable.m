%{
Date Created: 2/29/2024
Description: This function checks whether a given variable satisfies the 
structural requirements for being a valid session table. A valid session
table is a table which contains the core identifyin columns of 
'animalName', 'sessionDate', and 'sessionNumber'. This together represents
the minimal amount of information needed to uniquely identify a session.
%}

function TF = isSessionTable(A)
    % ISSESSIONTABLE  Validate whether an input is a well-formed session 
    %   table.
    %   
    %   TF = ISSESSIONTABLE(A) returns true if A is a table that represents
    %   session-level metadata for this project. A valid session table must
    %   contain, at minimum, the columns 'animalName', 'sessionDate', and
    %   'sessionNumber', which together uniquely identify each behavioral
    %   session for an individual animal.
    %
    %   This function is used by utilities such as sessionTableFun to 
    %   validate their inputs and ensure that preprocessing functions 
    %   operate on consistently structured session metadata.
    %
    %   See also sessionTable, sessionTableFun, isTrialTable.

    % A session table is a table where each row corresponds to a single
    % behavioral session. To uniquely identify each session, the table must
    % contain: the animal name, the session date, and the ordinal session
    % number for that date (e.g., the first or second session conducted).
    requiredColumnsNames = {'animalName', ...
        'sessionDate', ...
        'sessionNumber'};

    TF = istable(A) && ...
        all(ismember(requiredColumnsNames, A.Properties.VariableNames));

end


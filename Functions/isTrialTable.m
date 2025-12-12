%{
Date Created: 2/29/2024
Description: This function checks whether a given variable satisfies the 
structural requirements for being a valid trial table. A valid trial table 
is a table which contains the core identifying columns  of 'animalName', 
'sessionDate', 'sessionNnumber', and 'trialNumber'. This together 
represents the minimal amount of information needed to uniquely identify a 
trial.
%}

function TF = isTrialTable(A)
    % ISTRIALTABLE  Validate whether an input is a well-formed trial table.
    %   
    %   TF = ISTRIALTABLE(A) returns true if A is a table that represents
    %   trial-level behavioral data for this project. A valid trial table 
    %   must contain, at minimum, the columns 'animalName', 'sessionDate',
    %   'sessionNumber', and 'trialNumber', which together uniquely 
    %   identify each trial within the dataset.
    %
    %   This function is used by utilities such as trialTableFun to 
    %   validate their inputs and ensure that downstream preprocessing 
    %   operates on consistently structured trial metadata.
    %
    %   See also trialTable, trialTableFun, isSessionTable.

    % A trial table is a table where each row represents a single trial
    % conducted in a behavioral session. To uniquely identify each trial,
    % the table must contain the following columns: the name of the animal
    % performing the trial, the session date, the ordinal session number
    % for that date, and the trial number within that session.
    requiredColumnsNames = {'animalName', ...
        'sessionDate', ...
        'sessionNumber',...
        'trialNumber'};

    TF = istable(A) && ...
        all(ismember(requiredColumnsNames, A.Properties.VariableNames));

end
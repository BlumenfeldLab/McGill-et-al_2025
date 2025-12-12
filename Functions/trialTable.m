%{
Date Created: 2/29/2024
Description: This function constructs a standardized trial table. Each 
row represents a single behavioral trial and contains the core
metadata fields necessary to uniquely identify a trial within a session.
This core information is stored within the columns labeled 'animalName',
'sessionDate', 'sessionNumber', and 'trialNumber'.
%}

function trialTable = trialTable(varargin)
    % TRIALTABLE  Create an empty or preallocated trial-level metadata 
    %   table. 
    %   
    %   trialTable = TRIALTABLE() returns a 1-row table containing the 
    %   required metadata fields for defining a behavioral trial: 
    %   'animalName', 'sessionDate', 'sessionNumber', and 'trialNumber'.
    %
    %   trialTable = TRIALTABLE('numTrials', N) preallocates a trial table 
    %   with N rows using the same standardized variable schema.
    %
    %   Trial tables produced by this function serve as the core structural
    %   units for downstream processing, including trial parsing, event 
    %   timing, LFP extraction, and spectrogram computation. Maintaining a 
    %   consistent schema ensures compatibility with functions such as 
    %   trialTableFun and the preprocessing pipeline in 
    %   PreprocessAllExperimentalGroups.m.
    %
    %   See also isTrialTable, sessionTable, trialTableFun.

    % A trial table is a table where each row represents a single trial
    % conducted in a behavioral session. To uniquely identify each trial,
    % the table must include: the animal name, the session date, the
    % ordinal session number for that date, and the trial number within
    % that session.
    requiredColumnsNames = {'animalName', ...
        'sessionDate', ...
        'sessionNumber',...
        'trialNumber'};
    requiredColumnsTypes = {'string', ...
        'datetime', ...
        'double', ...
        'double'};
    numRequiredColumns = numel(requiredColumnsNames);

    % parse and validate inputs
    p = inputParser;
    p.addOptional('numTrials',1,@isnumeric)
    p.parse(varargin{:})

    % Create the trial table
    trialTable = table(...
        'Size', [p.Results.numTrials numRequiredColumns],...
        'VariableNames', requiredColumnsNames, ...
        'VariableTypes', requiredColumnsTypes);
    
end
%{
Date Created: 4/7/2023
Description: Construct a trial-level table from a session-level table by 
reading the behavioral results files for each session. Each row in the 
output table represents a single trial and includes both session metadata 
and trial-specific information (e.g., trial type, sound, volume, 
responses).
%}

function trialTableOut = getTrialTable(sessionTable, varargin)
    % GETTRIALTABLE  Build a trial table from a session table and results 
    %   files.
    %   
    %   trialTableOut = GETTRIALTABLE(sessionTable) takes a session table 
    %   sessionTable that conforms to isSessionTable and, for each session, 
    %   opens the associated behavioral results file (resultsFile) to 
    %   construct a trial-level table. The output sessionTable has one row
    %   per trial and includes core trial metadata such as trial type, 
    %   sound identity and volume, and lick response, along with the 
    %   identifying session information.
    %
    %   trialTableOut = GETTRIALTABLE(sessionTable, 'JoinInput', tf) 
    %   controls whether the session metadata columns are horizontally 
    %   appended to the generated trial table. When tf is true (default), 
    %   each trial row contains both trial-level data and the corresponding
    %   session-level fields. When tf is false, only the trial-level fields
    %   are returned, without joining back to the session table.
    %
    %   This function assumes that sessionTable contains a resultsFile 
    %   column specifying the path or identifier of the behavioral results
    %   file for each session, and that these results files can be opened 
    %   with opennResults. It is a key bridge between session-centric 
    %   metadata and trial-centric analyses in the preprocessing pipeline.
    %
    %   See also sessionTable, trialTable, openResults, isTrialTable.

    % Parse and validate inputs.
    % - sessionTable must be a valid session table (passes isSessionTable).
    % - JoinInput controls whether per-session metadata is joined back onto
    %   the per-trial data.
    p = inputParser;
    p.addRequired('sessionTable',@isSessionTable);
    p.addOptional('JoinInput',true,@islogical); % Horizontally append output to sessionTable, instead of keeping it as a separate table
    p.parse(sessionTable,varargin{:})
    
    % Create a cell array to hold per-session trial tables. A cell array is
    % used here because we do not assume that the session table alone
    % provides enough information to preallocate the final trial table size.
    numSessions = size(sessionTable,1);
    trialTableCell = cell(numSessions,1);
    
    for i=1:numSessions
       
        % Open the behavioral results file associated with this session.
        try
            sessionResults = openResults(sessionTable.resultsFile(i));
        catch
            warning(strcat("Unable to open the results file of ", ...
                sessionTable.animalName(i), " ", ...
                string(sessionTable.sessionDate(i)), " session ", ...
                string(sessionTable.sessionNumber(i)), ...
               ". Skipping."));            
            continue
        end
        
        % Instantiate a trial table for all trials in this session.
        numTrials = size(sessionResults,1);
        sessTrialTable = trialTable(numTrials);
        sessTrialTable.trialType = strings(numTrials,1);
        sessTrialTable.soundPlayed = strings(numTrials,1);
        sessTrialTable.soundVolume = -1*ones(numTrials,1);
        sessTrialTable.lickResponse = strings(numTrials,1);
        sessTrialTable.punishmentGiven = false(numTrials,1);
        
        % Fill in the session-identifying metadata for all trials.
        sessTrialTable.animalName(:) = repmat(sessionTable.animalName(i),[numTrials 1]);
        sessTrialTable.sessionDate(:) = repmat(sessionTable.sessionDate(i),[numTrials 1]);
        sessTrialTable.sessionNumber(:) = repmat(sessionTable.sessionNumber(i),[numTrials 1]);
        
        % Fill in trial-level data derived from the results file.
        sessTrialTable.trialNumber(:) = sessionResults.trial_number(:);
        sessTrialTable.trialType(:) = sessionResults.trial_type(:);
        sessTrialTable.soundPlayed(:) = sessionResults.stimulusphase_sound(:);
        sessTrialTable.soundVolume(:) = sessionResults.stimulusphase_sound_volume(:);
        
        % Optional lick response column, if present in the results table.
        if any(strcmp("lickallowedphase_response",sessionResults.Properties.VariableNames))
            sessTrialTable.lickResponse(:) = sessionResults.lickallowedphase_response(:);
        end
        
        % Optional punishment flag, if present in the results table.
        if any(strcmp("lickallowedphase_punish_given",sessionResults.Properties.VariableNames))
            sessTrialTable.punishmentGiven(:) = sessionResults.lickallowedphase_punish_given(:);
        end
        
        % Join the trial table to the session table row if requested.
        % When JoinInput is true, each trial inherits all columns from
        % sessionTable(i,:) in addition to the trial fields defined above.
        if p.Results.JoinInput
            sessTrialTable = join(sessTrialTable,sessionTable(i,:));
        end
        
        trialTableCell{i} = sessTrialTable;
        
    end
    
    trialTableOut = vertcat(trialTableCell{:});
    
end


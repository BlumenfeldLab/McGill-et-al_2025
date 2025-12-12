%{
Date Created: 3/8/2024
Description: Identifies the onset and offset times of auditory stimuli 
within each trial of a behavioral session by detecting deviations in the 
audio channel of the corresponding Spike2 recording. When no stimulus can 
be detected for a given trial, the function falls back to a heuristic based
on an expected stimulus lag and duration.
%}

function [stimulusStart,stimulusEnd] = trialStimulusTimes(resultsFile, spike2File, tSessStart, tSessEnd, tStimPeriodStart, tStimPeriodEnd, varargin)
    % TRIALSTIMULUSTIMES  Find per-trial stimulus onset and offset times.
    %
    %   [stimulusStart, stimulusEnd] = TRIALSTIMULUSTIMES(resultsFile, spike2File, tSessStart, tSessEnd, tStimPeriodStart, tStimPeriodEnd)
    %   determines stimulus onset and offset times (in seconds) for each 
    %   trial stimuli in a behavioral session.
    %
    %   Inputs:
    %       resultsFile   
    %           - Either a string path to a trial-level results file (read 
    %           via openResults), or an existing results table with one row
    %           per trial.
    %
    %       spike2File
    %           - Either a string path to a Spike2 .smrx/.s2rx file, or an
    %           open CEDS64 file handle.
    %
    %     tSessStart
    %           - Numeric scalar; session start time (seconds) in the 
    %           Spike2 recording frame.
    %
    %     tSessEnd
    %           - Numeric scalar; session end time (seconds).
    %
    %     tStimPeriodStart
    %           - Numeric vector or cell array; per-trial stimulus period
    %           start times (seconds) for each trial.
    %
    %     tStimPeriodEnd
    %           - Numeric vector or cell array; per-trial stimulus period 
    %           end times (seconds) for each trial.
    %
    %   Name–value pairs:
    %       'AudioChannel' (default 13)
    %           - Index of the audio channel in the Spike2 file to inspect 
    %           for stimulus-evoked deviations.
    %
    %       'MinStimulusLength' (default 0.03)
    %
    %       'MaxStimulusLength' (default 0.07)
    %           - Minimum and maximum duration (seconds) for a detected 
    %           deviation to be considered a valid stimulus candidate.
    %
    %       'ExpectedStimulusLag' (default 0.1193)
    %           - Heuristic lag (seconds) between the trial stimulus-period 
    %           start time and the expected onset of the audio stimulus, 
    %           used when no stimulus can be detected for a trial.
    %
    %       'StimulusLength' (default 0.0495)
    %           - Expected duration (seconds) of the stimulus, used 
    %           together with ExpectedStimulusLag to generate a fallback 
    %           estimate.
    %
    %       'ResultsFileStimulusVolumeColumn' 
    %           (default 'stimulusphase_sound_volume')
    %           - Name of the column in resultsFile indicating the stimulus
    %           volume per trial. This is used to decide whether a trial is
    %           expected to have a stimulus.
    %
    %   Outputs:
    %       stimulusStart, stimulusEnd
    %           Column cell arrays of length NTRIALS. Each cell contains
    %           either NaN (no identifiable stimulus) or one or more 
    %           start/end times (seconds) corresponding to stimuli 
    %           occurring within the specified per-trial stimulus period.
    %
    %   Notes:
    %       - Stimulus candidates are detected by calling
    %       findRecordinngDeviations on the specified audio channel over
    %       the session interval [tSessStart, tSessStart], and then 
    %       assigning detected events to trials based on stimulusStart 
    %       / stimulusEnd.
    %       - If a trial's stimulus volume indicates that a stimulus should
    %       have been played but none is detected within its stimulus 
    %       period, a heuristic fallback is used (ExpectedStimulusLag + 
    %       StimulusLength).
    %
    %   See also findRecordingDeviations, openRessults.

    % Validate and parse inputs
    p = inputParser;
    p.addRequired('resultsFile',@(x) isstring(x) | istable(x));
    p.addRequired('spike2File', @(x) isstring(x) | isnumeric(x) | islogical(x));
    p.addRequired('tSessStart', @isnumeric);
    p.addRequired('tSessEnd', @isnumeric);
    p.addRequired('tStimPeriodStart', @(x) isnumeric(x) | iscell(x));
    p.addRequired('tStimPeriodEnd', @(x) isnumeric(x) | iscell(x));

    % Channel and stimulus detection parameters.
    p.addParameter('AudioChannel',13,@isnumeric);
    p.addParameter('MinStimulusLength',0.03,@isnumeric);
    p.addParameter('MaxStimulusLength',0.07,@isnumeric);

    % Heuristic timing parameters for missing stimuli.
    p.addParameter('ExpectedStimulusLag',0.1193,@isnumeric);
    p.addParameter('StimulusLength',0.0495,@isnumeric);

    % Column in results file specifying stimulus volume.
    p.addParameter('ResultsFileStimulusVolumeColumn','stimulusphase_sound_volume',@ischar)

    p.parse(resultsFile, spike2File, tSessStart, tSessEnd, tStimPeriodStart, tStimPeriodEnd, varargin{:})

    % Extract parsed values for readability.
    % In some calling patterns, tStimPeriodStart / end may be stored in
    % cell arrays; converting to numeric arrays simplifies indexing.
    if iscell(p.Results.tStimPeriodStart)
        tStimPeriodStart = cell2mat(tStimPeriodStart);
    end

    if iscell(p.Results.tStimPeriodEnd)
        tStimPeriodEnd = cell2mat(tStimPeriodEnd);
    end

    % Initialize default outputs (single NaN by default)
    stimulusStart = NaN;
    stimulusEnd = NaN;

    % Open or assign the results table
    % If resultsFile is a string, treat it as a file path and open via
    % openResults. Otherwise, treat it directly as a table of trials.
    if isstring(p.Results.resultsFile)
        try
            resultsTable = openResults(p.Results.resultsFile);
        catch
            warning( ...
                strcat( ...
                    "(trialStimulusTimes) Unable to open results file """, ...
                    p.Results.resultsFile, ...
                    """. Returning default values.") ...
                );
    
            return
        end
    else
        resultsTable = p.Results.resultsFile;
    end

    % Prepare per-trial output containers
    numTrials = size(resultsTable,1);
    stimulusStart = num2cell(NaN(numTrials,1));
    stimulusEnd = num2cell(NaN(numTrials,1));

    % Validate trial alignment with stimulus-period arrays
    % We require that tStimPeriodStart and tStimPeriodEnd have the same
    % number of rows as the results table, so that each trial’s stimulus
    % period is unambiguously defined.
    if numTrials ~= size(tStimPeriodStart,1) | numTrials ~= size(tStimPeriodEnd,1)
        warning( ...
            strcat( ...
                "(trialStimulusTimes) The number of trials in """, ...
                p.Results.resultsFile, ...
                """ is unequal to the number of trials in tStimPeriodStart or tStimPeriodEnd End. Returning default values.") ...
            );
        return
    end

    % Open or assign the Spike2 file handle
    openedSpike2File = false;
    if isstring(p.Results.spike2File)
        % Open the Spike2 file given by path.
        session1401Recording = CEDS64Open(convertStringsToChars(p.Results.spike2File));
        openedSpike2File = true;
    else
        % Use an existing file handle.
        session1401Recording = p.Results.spike2File;
    end

    % Validate that the Spike2 file has been opened.
    if session1401Recording == -1 || session1401Recording == 0

        warning( ...
            strcat( ...
                "(trialStimulusTimes) Unable to open the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

        return
    end

    % Detect all candidate stimuli in the audio channel (over the session)
    % We first identify all segments on the audio channel that look like
    % stimulus events, using findRecordingDeviations as a generic detector.
    [allStimStartTimes, allStimEndTimes] = findRecordingDeviations(...
        session1401Recording, p.Results.AudioChannel,...
        p.Results.tSessStart, p.Results.tSessEnd,...
        'ClusterThreshold',0.02,...
        'MinClusterSize',p.Results.MinStimulusLength,...
        'MaxClusterSize',p.Results.MaxStimulusLength);

    % Assign detected stimuli to individual trials
    for i = 1:numTrials
        % Identify which detected stimulus segments fall within the
        % per-trial stimulus period [tStimPeriodStart(i), tStimPeriodEnd(i)).
        stimuliThisTrial = ...
            allStimStartTimes >= tStimPeriodStart(i) ...
            & allStimEndTimes < tStimPeriodEnd(i);

        % If a stimulus was expected during this trial but none was
        % detected (or if the trial’s volume is recorded as zero, per the
        % current logic), fall back on a heuristic estimate based on the
        % per-trial stimulus period, ExpectedStimulusLag, and 
        % StimulusLength.
        if (resultsTable.(p.Results.ResultsFileStimulusVolumeColumn)(i) > 0 ...
                && sum(stimuliThisTrial) == 0) ...
                || resultsTable.(p.Results.ResultsFileStimulusVolumeColumn)(i) == 0

            stimulusStart{i} = tStimPeriodStart(i) ...
                + p.Results.ExpectedStimulusLag;
            stimulusEnd{i} = stimulusStart{i} ...
                + p.Results.StimulusLength;

        end
        
        % If at least one detected stimulus falls within the trial’s
        % stimulus period, use its start time(s).
        if ~isempty(allStimStartTimes(stimuliThisTrial))
            stimulusStart{i} = allStimStartTimes(stimuliThisTrial);
        end

        % Similarly, assign the corresponding end time(s).
        if ~isempty(allStimEndTimes(stimuliThisTrial))
            stimulusEnd{i} = allStimEndTimes(stimuliThisTrial);
        end
    end

    % Close the Spike2 file if this function opened it
    if openedSpike2File
        CEDS64Close(session1401Recording);
    end

end


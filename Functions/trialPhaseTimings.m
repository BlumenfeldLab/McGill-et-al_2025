%{
Date Created: 3/7/2024
Description: Extracts per-trial phase timings from a Spike2 recording and
behavioral results file.

This function uses a digital "signal output" channel (SigOut) in the Spike2
recording to segment a behavioral session into consecutive phases, and then
maps those phases onto trials according to the behavioral session type.

For each trial, it returns the start and end times (in seconds) of:
    - the trial itself
    - intertrial interval
    - stimulus period
    - post-stimulus delay
    - lickport engage / disengage periods
    - lick-allowed period
    - punishment period (if present)

Supported session types include:
    - "Passive_Listening_Task"
    - "Simple_Auditory_Session_Stage_1" (with early and later variants)
    - other "Simple_Auditory_Session_*" and Go/No-Go style sessions
    (handled by a generic 7-phase template).

Notes:
    - resultsFile may be either a path to a text results file (opened with
    OPENRESULTS) or an already-loaded results table.
    - spike2File may be a Spike2 file path or an open CEDS64 file handle.
    - tStart and tEnd define the overall session time window, in seconds,
    within the Spike2 recording.
    - minIntertrialInterv is currently accepted as a parameter but not used
    in the implementation (retained for backward compatibility / future 
    use).
%}

function [trialStart, trialEnd, ...
    intertrialIntervalStart, intertrialIntervalEnd, ...
    stimulusPeriodStart, stimulusPeriodEnd, ...
    postStimDelayStart, postStimDelayEnd, ...
    lickportEngageStart, lickportEngageEnd, ...
    lickAllowedStart, lickAllowedEnd, ...
    lickportDisengageStart, lickportDisengageEnd, ...
    punishmentStart, punishmentEnd] ...
    = trialPhaseTimings(resultsFile , spike2File, tStart, tEnd, varargin)
    % TRIALPHASETIMINGS  Compute phase start/end times for each trial.
    %
    %   [trialStart, trialEnd, intertrialIntervalStart, ...
    %   intertrialIntervalEnd, stimulusPeriodStart, stimulusPeriodEnd, ...
    %   postStimDelayStart, postStimDelayEnd, lickportEngageStart, ...
    %   lickportEngageEnd, lickAllowedStart, lickAllowedEnd, ...
    %   lickportDisengageStart, lickportDisengageEnd, punishmentStart, ...
    %   punishmentEnd] = TRIALPHASETIMINGS(resultsFile, spike2File, ...
    %   tStart, tEnd, ...) returns vectors of phase timings for each trial 
    %   in resultsFile, aligned to the spike2File recording.
    %
    %   Required Inputs:
    %       resultsFile
    %           Either:
    %               * string: path to a text results file produced by the
    %               behavioral system, parsed by OPENRESULTS, or
    %               * table: a pre-loaded results table with at least 
    %               Session_Type, Animal_Name, and Session_Date fields.
    %       spike2File
    %           Either:
    %               * string: path to a Spike2 .smrx file to be opened via
    %               CEDS64Open, or
    %               * numeric/logical: an existing CEDS64 file handle.
    %       tStart, tEnd
    %           - Scalar start and end times (seconds), defining the 
    %           session time window within the Spike2 recording.
    %
    %   Name–Value Pair Arguments:
    %       'minIntertrialInterv' (numeric, default = 4)
    %           Minimum intertrial interval in seconds. (Currently not used
    %           in the phase assignment logic, but retained for 
    %           compatibility.)
    %
    %       'sigOutChan' (numeric, default = 15)
    %           Channel index of the digital signal output used to encode
    %           phase boundaries (e.g., TTL pulses marking phase 
    %           transitions).
    %
    %       'rewardChan' (numeric, default = 11)
    %           Channel index of the reward valve (unused in this function
    %           but retained for compatibility with other analysis code).
    %
    %       'lightChan' (numeric, default = 12)
    %           Channel index of the punishment light signal. Used to 
    %           distinguish actual punishment trains from neutral events 
    %           when assigning the punishment phase.
    %
    %   All outputs are double vectors of length NUMTRIALS, with NaN values
    %   for phases that do not occur for a given trial or session type.
    %
    %   See also: openResults, findRecordingDeviations.

    % Validate and parse inputs
    p = inputParser;
    p.addRequired('resultsFile',@(x) isstring(x) | istable(x));
    p.addRequired('spike2File', @(x) isstring(x) | isnumeric(x) | islogical(x));
    p.addRequired('tStart', @isnumeric);
    p.addRequired('tEnd', @isnumeric);
    p.addParameter('minIntertrialInterv',4);
    p.addParameter('sigOutChan',15,@isnumeric);
    p.addParameter('rewardChan',11,@isnumeric);
    p.addParameter('lightChan',12,@isnumeric);
    p.parse(resultsFile, spike2File, tStart, tEnd, varargin{:})

    % Initialize default outputs (scalar NaNs; resized later after we know
    % the number of trials from the results file)
    trialStart = NaN;
    trialEnd = NaN;
    intertrialIntervalStart = NaN;
    intertrialIntervalEnd = NaN;
    stimulusPeriodStart = NaN;
    stimulusPeriodEnd = NaN;
    postStimDelayStart = NaN;
    postStimDelayEnd = NaN;
    lickportEngageStart = NaN;
    lickportEngageEnd = NaN;
    lickAllowedStart = NaN;
    lickAllowedEnd = NaN;
    lickportDisengageStart = NaN;
    lickportDisengageEnd = NaN;
    punishmentStart = NaN;
    punishmentEnd = NaN;

    % Load the behavioral results table
    % If RESULTSFILE is a string, treat it as a path to a text results file
    % and open it with OPENRESULTS. Otherwise, assume it is already a 
    % table.
    if isstring(p.Results.resultsFile)
        try
            resultsTable = openResults(p.Results.resultsFile);
        catch
            warning( ...
                strcat( ...
                    "(trialPhaseTimings) Unable to open results file """, ...
                    p.Results.resultsFile, ...
                    """. Returning default values.") ...
                );
    
            return
        end
    else
        resultsTable = p.Results.resultsFile;
    end

    % Resize outputs to have one row per trial, initialized to NaN
    numTrials = size(resultsTable,1);
    trialStart = NaN(numTrials,1);
    trialEnd = NaN(numTrials,1);
    intertrialIntervalStart = NaN(numTrials,1);
    intertrialIntervalEnd = NaN(numTrials,1);
    stimulusPeriodStart = NaN(numTrials,1);
    stimulusPeriodEnd = NaN(numTrials,1);
    postStimDelayStart = NaN(numTrials,1);
    postStimDelayEnd = NaN(numTrials,1);
    lickportEngageStart = NaN(numTrials,1);
    lickportEngageEnd = NaN(numTrials,1);
    lickAllowedStart = NaN(numTrials,1);
    lickAllowedEnd = NaN(numTrials,1);
    lickportDisengageStart = NaN(numTrials,1);
    lickportDisengageEnd = NaN(numTrials,1);
    punishmentStart = NaN(numTrials,1);
    punishmentEnd = NaN(numTrials,1);

    % Open Spike2 recording (if a path is provided) or reuse existing 
    % handle
    openedSpike2File = false;
    if isstring(p.Results.spike2File)
        session1401Recording = CEDS64Open(convertStringsToChars(p.Results.spike2File));
        openedSpike2File = true;
    else
        session1401Recording = p.Results.spike2File;
    end

    % Validate that the Spike2 file has been opened successfully
    if session1401Recording == -1 || session1401Recording == 0

        warning( ...
            strcat( ...
                "(trialPhaseTimings) Unable to open the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

        return
    end
 
    % Detect phase boundaries from the SigOut channel
    % findRecordingDeviations is used here to detect short deflections on
    % the digital signal output channel that mark phase transitions.
    % Only the first output (start times) is used, and we treat each
    % adjacent pair of times as a phase [start, end).
    phaseTimes = findRecordingDeviations(session1401Recording, p.Results.sigOutChan, ...
        p.Results.tStart, p.Results.tEnd, 'ClusterThreshold',0.0015, ...
        'MinClusterSize',0.002,'MaxClusterSize',-1);

    % Pad with session start and end so that every adjacent pair of entries
    % in phaseTimes defines a contiguous phase window.
    phaseTimes=[p.Results.tStart; phaseTimes; p.Results.tEnd];

    % Assign phase windows to trials, depending on session type
    trialNum=1; % index of current trial
    phaseNum=1; % index of phase within a trial (depends on session type)
    if resultsTable.session_type(1) == "Passive_Listening_Task"
        
        % Passive Listening paradigm
        %   Phases per trial:
        %     1) Intertrial interval
        %     2) Stimulus period
        %     3) Post-stimulus delay

        i = 1;
        while i <= (length(phaseTimes)-1)

            if trialNum > numTrials
                warning("(trialPhaseTimings) More phases were detected than the number of trials allows. Returning output as-is.");
                break
            end

            switch phaseNum

                case 1 % Intertrial Interval

                    trialStart(trialNum) = phaseTimes(i);
                    intertrialIntervalStart(trialNum) = phaseTimes(i);
                    intertrialIntervalEnd(trialNum) = phaseTimes(i+1);

                    phaseNum = phaseNum + 1;

                case 2 % Stimulus Phase

                    stimulusPeriodStart(trialNum) = phaseTimes(i);
                    stimulusPeriodEnd(trialNum) = phaseTimes(i+1);

                    phaseNum = phaseNum + 1;
                    
                case 3 % Post-Stimulus Phase

                    postStimDelayStart(trialNum) = phaseTimes(i);
                    postStimDelayEnd(trialNum) = phaseTimes(i+1);
                    trialEnd(trialNum) = phaseTimes(i+1);

                    phaseNum = 1;
                    trialNum = trialNum + 1;
            end

            i = i + 1;
            
        end

        % Ensure the last trial end time is defined
        if trialNum <= numTrials
            trialEnd(trialNum) = phaseTimes(end);
        else
            trialEnd(trialNum-1) = phaseTimes(end);
        end
    
    elseif resultsTable.session_type(1) == "Simple_Auditory_Session_Stage_1"
        % Simple Auditory Session Stage 1
        %   Early version (<= 06-Feb-2023 or specific animal/date):
        %     1) Intertrial interval
        %     2) Stimulus
        %     3) Lick allowed
        %
        %   Later version (> 06-Feb-2023):
        %     1) Stimulus
        %     2) Lick allowed
        
        if ((resultsTable.Animal_Name(1) == "Drogskol Reaver" && ...
            resultsTable.Session_Date(1) == datetime("06-Feb-2023")) || ...
            resultsTable.Session_Date(1) <= datetime("06-Feb-2023"))
        
            % ----------------- Early Stage 1 mapping -------------------
            i = 1;
            while i <= (length(phaseTimes)-1)

                if trialNum > numTrials
                    warning("(trialPhaseTimings) More phases were detected than the number of trials allows. Returning output as-is.");
                    break
                end

                switch phaseNum

                    case 1 % Intertrial Interval

                        trialStart(trialNum) = phaseTimes(i);
                        intertrialIntervalStart(trialNum) = phaseTimes(i);
                        intertrialIntervalEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = phaseNum + 1;

                    case 2 %Stimulus Phase

                        trialStart(trialNum) = phaseTimes(i);
                        stimulusPeriodStart(trialNum) = phaseTimes(i);
                        stimulusPeriodEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = phaseNum + 1;

                    case 3 %Lick Allowed Phase 

                        lickAllowedStart(trialNum) = phaseTimes(i);
                        lickAllowedEnd(trialNum) = phaseTimes(i+1);
                        trialEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = 1;
                        trialNum = trialNum + 1;
                end

                i = i + 1;
            end

            if trialNum <= numTrials
                trialEnd(trialNum) = phaseTimes(end);
            else
                trialEnd(trialNum-1) = phaseTimes(end);
            end
            
        else

            % ----------------- Later Stage 1 mapping -------------------
            % No explicit intertrial interval phase is recorded here.
            i = 1;
            while i <= (length(phaseTimes)-1)

                if trialNum > numTrials
                    warning("(trialPhaseTimings) More phases were detected than the number of trials allows. Returning output as-is.");
                    break
                end

                switch phaseNum
                    case 1 % Stimulus Phase

                        trialStart(trialNum) = phaseTimes(i);
                        stimulusPeriodStart(trialNum) = phaseTimes(i);
                        stimulusPeriodEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = phaseNum + 1;

                    case 2 % Lick Allowed Phase 

                        lickAllowedStart(trialNum) = phaseTimes(i);
                        lickAllowedEnd(trialNum) = phaseTimes(i+1);
                        trialEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = 1;
                        trialNum = trialNum + 1;
                end

                i = i + 1;
            end

            % Ensure last trial end is defined
            if trialNum <= numTrials
                trialEnd(trialNum) = phaseTimes(end);
            else
                trialEnd(trialNum-1) = phaseTimes(end);
            end
            
        end
        
    else
        % General case for more complex sessions (e.g., Go/No-Go)
        %
        % Assumed phase order per trial:
        %   1) Intertrial interval
        %   2) Stimulus period
        %   3) Post-stimulus delay
        %   4) Lickport engage
        %   5) Lick allowed
        %   6) Lickport disengage
        %   7) Punishment (optional; validated via light channel)
    
        i = 1;
        while i <= (length(phaseTimes)-1)

            if trialNum > numTrials
                warning("(trialPhaseTimings) More phases were detected than the number of trials allows. Returning output as-is.");
                break
            end
            
            switch phaseNum
                case 1 % Intertrial Interval
                    
                    trialStart(trialNum) = phaseTimes(i);
                    intertrialIntervalStart(trialNum) = phaseTimes(i);
                    intertrialIntervalEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 2 % Stimulus Period
                    
                    stimulusPeriodStart(trialNum) = phaseTimes(i);
                    stimulusPeriodEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 3 % Post-Stim Delay
                    
                    postStimDelayStart(trialNum) = phaseTimes(i);
                    postStimDelayEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 4 % Lickport Engage
                    
                    lickportEngageStart(trialNum) = phaseTimes(i);
                    lickportEngageEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 5 % Lick Allowed
                    
                    lickAllowedStart(trialNum) = phaseTimes(i);
                    lickAllowedEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 6 % Lickport Disengage
                    
                    lickportDisengageStart(trialNum) = phaseTimes(i);
                    lickportDisengageEnd(trialNum) = phaseTimes(i+1);
                    
                    phaseNum = phaseNum + 1;
                    i = i + 1;
                    
                case 7 % Punishment Phase (optional)

                    % Use the light channel to determine whether this phase
                    % actually contains a punishment light train.
                    [lightDeflectionsStart,~] = findRecordingDeviations(session1401Recording,p.Results.lightChan,phaseTimes(i),phaseTimes(i+1),"zScoreWindow",30,'SignificanceThreshold',2);
                    
                    % Check whether we see a ~5 Hz light train:
                    % spacing ~0.2 s, at least ~15 pulses.
                    if ~isempty(lightDeflectionsStart) && (sum(abs(0.2-diff(lightDeflectionsStart)) < 0.05) >= 15)
                       
                        punishmentStart(trialNum) = phaseTimes(i);
                        punishmentEnd(trialNum) = phaseTimes(i+1);
                        trialEnd(trialNum) = phaseTimes(i+1);

                        phaseNum = 1;
                        trialNum = trialNum + 1;
                        i = i + 1;
                        
                    else

                        % No punishment train detected: treat this boundary
                        % as the end of the trial without punishment and
                        % reuse the same phaseTimes(i) as the start of the
                        % next trial's intertrial interval.
                        trialEnd(trialNum) = phaseTimes(i);
                        
                        phaseNum = 1;
                        trialNum = trialNum + 1;

                        % Note: i is not incremented here on purpose.
                    end
                    
            end
            
        end
        
        % Ensure the last trial end is defined
        if trialNum <= numTrials
            trialEnd(trialNum) = phaseTimes(end);
        else
            trialEnd(trialNum-1) = phaseTimes(end);
        end
    
    end

    % Close the Spike2 file if we opened it in this function
    if openedSpike2File
        CEDS64Close(session1401Recording);
    end

end


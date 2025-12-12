%{
Date Created: 7/2/2024
Description:
    This Script extracts peristimulus and intertrial-interval LFP traces 
    for each experimental group and saves them to disk.

    This script implements the main preprocessing pipeline for the
    behavioral/LFP dataset. It:

      1) Initializes the CEDS64 ML library so Spike2 (.smrx/.s2rx) files
         can be accessed from MATLAB.
      2) Builds a behavioral session table and a trial table from raw
         results files, Spike2 recordings, Excel datasheets, and
         pupillometry recordings using getBehavioralSessionTable and
         getTrialTable.
      3) Defines experimental groups based on combinations of:
           - animalName
           - sessionType
           - trialType
           - soundVolume
           - lickResponse
         and on electrode/channel identity and placement.
      4) Uses trialTableFun with sessionStartEndtime, trialPhaseTimings,
         and trialStimulusTimes to annotate trials with trial- and
         phase-level timing information (e.g., intertrial interval,
         stimulus period, post-stimulus delay).
      5) Extracts:
           - intertrial-interval baseline traces (pre-stimulus),
           - peristimulus LFP traces around each stimulus,
         for each experimental group using trialSliceRecordingBetween and
         trialSliceRecordinngWindow.
      6) Normalizes traces relative to the intertrial-interval baseline and
         saves one .mat file per experimental group containing the
         group-specific trial table (EXPERIMENTALGROUPTRIALTABLE), plus an
         overall experimentalGroupTable summarizing all groups.

    Prerequisites:
      - CEDS64 ML library installed and on the MATLAB path.
      - Helper functions on the MATLAB path:
          initCEDS64ML, getBehavioralSessionTable, getTrialTable,
          trialTableFun, sessionStartEndTime, trialPhaseTimings,
          trialStimulusTimes, trialSliceRecordingBetween,
          trialSliceRecordingWindow, openResults.
      - results folders listed in resultsFolders must exist and contain
        the expected behavioral / Spike2 / Excel / video files.

    Outputs:
      - One .mat file per experimental group containing
        experimentalGroupTrialTable with peristimulus and intertrial
        traces and metadata.
      - A single experimentalGroupTable.MAT summarizing all experimental
        groups and pointing to the saved trial tables.
%}

%% Initialize the CEDS64 ML library
% This is necessary to call any of the functions provided by Cambridge
% Electronic Design (CED) for analysis of Spike2 files (.smrx and .s2rx)
% within MATLAB. This function loads the CEDS64 API so the CEDS64* functions
% (e.g., CEDS64Open, CEDS64ReadWaveF) are available.
initCEDS64ML();

%% Create the behavioral session table and trial table
% These tables allow convenient manipulation of session- and trial-level
% metadata.
%
%   - Each row of a session table represents a single behavioral session.
%   - Each row of a trial table represents a single trial within a
%     session.
%
% The helper functions:
%   - getBehavioralSEssionTable discovers sessions and associates each with
%     results files, Spike2 recordings, Excel datasheets, and pupillometry
%     recordings.
%   - getTrialTable expands the session table into a trial-level table by
%     reading each results file.

% Define the folders containing all of the data associated with each
% cohort. These paths must be updated if the data are moved.
resultsFolders = "..\Data\";

% Obtain a session table for each result folder
sessionTables = cell(numel(resultsFolders),1);
for i=1:numel(resultsFolders)
    sessionTables{i} = getBehavioralSessionTable(resultsFolders(i));
end

% Vertically concatenate all cohort-specific session tables into a single
% "sandbox" session table
sandboxSessionTable = vertcat(sessionTables{:});

% Create the trial table from the session table. Each row corresponds to
% one behavioral trial across all sessions/cohorts.
sandboxTrialTable = getTrialTable(sandboxSessionTable);

% Clear unnecessary variables
clear( ...
    "i", ...
    "resultsFolders", ...
    "sessionTables", ...
    "sandboxSessionTable");



%% Define experimental groups
% Experimental groups are defined by combinations of:
%   - animalName
%   - electrode location / channel
%   - sessionType
%   - trialType
%   - soundVolume
%   - lickResponse
%
% Not every combination exists in the data. We only create groups that
% actually appear in sandboxTrialTable, which reduces empty groups and
% wasted computation.

% The list of all mice. Each element of this array corresponds to a single
% row of allChannelEachMouse and allChannelEachMouseInCorrectLocation.
% This array should not be modified.
allMice = ["Alluring Siren"; ...
    "Ambassador Oak"; ...
    "Breathless Knight"; ...
    "Charmbreaker Devil"; ...
    "Cramped Bunker"; ...
    "Cunning Lethemancer"; ...
    "Downhill Charge"; ...
    "Drogskol Reaver"; ...
    "Fart Mouse"; ...
    "Filigree Familiar"; ...
    "Gearshift Ace"; ...
    "Geyserfield Stalker"; ...
    "Grim Flayer"; ...
    "Harvest Season"; ...
    "Humble Budoka"; ...
    "Impelled Giant"; ...
    "Jade Guardian"; ...
    "Jirana Kudro"; ...
    "Kessig Naturalist"; ...
    "Killer Service"; ...
    "Lathnu Hellion"; ...
    "Lore Drakkis"; ...
    "Molten Tributary"; ...
    "Neurok Transmuter"; ...
    "Oakgnarl Warrior"; ...
    "Phantasmagorian"; ...
    "Reliquary Tower"; ...
    "Serum Sovereign"; ...
    "Setessan Skirmisher"; ...
    "Simic Fluxmage"; ...
    "Tangled Kelp"; ...
    "Voldaren Thrillseeker"];

% allChannelEachMouse: which electrodes are present for each mouse.
% Rows correspond to allMice, columns correspond to allChannnelNames.
% true indicates that a given mouse has an electrode in that channel.
% This array should not be modified.
allChannelEachMouse = [ ...
    true, true, false, true;  ... % Alluring Siren
    true, true, false, true;  ... % Ambassador Oak
    true, true, false, true;  ... % Breathless Knight
    true, true, false, true;  ... % Charmbreaker Devil
    true, true, true,  false; ... % Cramped Bunker
    true, true, true,  false; ... % Cunning Lethemancer
    true, true, true,  false; ... % Downhilll Charge
    true, true, true,  false; ... % Drogskol Reaver
    true, true, true,  false; ... % Fart Mouse
    true, true, false, true;  ... % Filigree Familiar
    true, true, true,  false; ... % Gearshift Ace
    true, true, true,  false; ... % Geyserfield Stalker
    true, true, false, true;  ... % Grim Flayer 
    true, true, false, true;  ... % Harvest Season
    true, true, true,  false; ... % Humble Budoka
    true, true, true,  false; ... % Impelled Giant
    true, true, true,  false; ... % Jade Guardian
    true, true, false, true;  ... % Jirana Kudro
    true, true, true,  false; ... % Kessig Naturalist
    true, true, false, true;  ... % Killer Service
    true, true, false, true;  ... % Lathnu Hellion
    true, true, true,  false; ... % Lore Drakkis
    true, true, false, true;  ... % Molten Tributary
    true, true, false, true;  ... % Neurok Transmuter
    true, true, true,  false; ... % Oakgnarl Warrior
    true, true, true,  false; ... % Phantasmagorian
    true, true, false, true;  ... % Reliquary Tower
    true, true, true,  false; ... % Serum Sovereign
    true, true, false, true;  ... % Setessan Skirmisher
    true, true, true,  false; ... % Simic Fluxmage
    true, true, false, true;  ... % Tangled Kelp
    true, true, true,  false];    % Voldaren Thrillseeker
numChannelsEachMouse = max(sum(allChannelEachMouse,2));

% allChannelEachMouseInCorrectLocation: whether each electrode was
% implanted in the intended target region.
% true indicates the electrode is in the correct anatomical location.
% This array should not be modified.
allChannelEachMouseInCorrectLocation = [ ...
    true,  false, false, false; ... % Alluring Siren
    true,  true,  false, true;  ... % Ambassador Oak
    true,  true,  false, false; ... % Breathless Knight
    true,  true,  false, false; ... % Charmbreaker Devil
    true,  true,  true,  false; ... % Cramped Bunker
    true,  false, true,  false; ... % Cunning Lethemancer
    true,  true,  true,  false; ... % Downhilll Charge
    false, true,  true,  false; ... % Drogskol Reaver
    true,  false, true,  false; ... % Fart Mouse
    true,  false, false, true;  ... % Filigree Familiar
    false, true,  true,  false; ... % Gearshift Ace
    false, false, true,  false; ... % Geyserfield Stalker
    true,  true,  false, true;  ... % Grim Flayer 
    false, true,  false, true;  ... % Harvest Season
    true,  true,  true,  false; ... % Humble Budoka
    false, true,  true,  false; ... % Impelled Giant
    false, false, true,  false; ... % Jade Guardian
    true,  false, false, true;  ... % Jirana Kudro
    true,  false, true,  false; ... % Kessig Naturalist
    true,  false, false, true;  ... % Killer Service
    true,  false, false, true;  ... % Lathnu Hellion
    true,  false, false, false; ... % Lore Drakkis
    false, false, false, true;  ... % Molten Tributary
    true,  true,  false, true;  ... % Neurok Transmuter
    true,  true,  true,  false; ... % Oakgnarl Warrior
    true,  true,  true,  false; ... % Phantasmagorian
    false, true,  false, true;  ... % Reliquary Tower
    false, false, false, false; ... % Serum Sovereign
    true,  false, false, true;  ... % Setessan Skirmisher
    true,  false, true,  false; ... % Simic Fluxmage
    true,  true,  false, true;  ... % Tangled Kelp
    false, false, true,  false];    % Voldaren Thrillseeker

% List of channel names and channel numbers.
% These correspond to the channels of Spike2 files on which each LFP
% recording was made.
allChannelNames = [ ...
    "Auditory Cortex"; ...
    "Centrolateral Thalamic Nucleus"; ...
    "Frontal Association Region"; ...
    "Visual Cortex"];
allChannelNumber = [ ...
    1; ...
    3; ...
    2; ...
    2];

% Names of session types used in the behavioral code, and their human-
% readable labels (used when constructing group names).
allSessionTypes = ["Passive_Listening_Task", ...
    "Simple_Auditory_Session_Stage_0", ...
    "Simple_Auditory_Session_Stage_1", ...
    "Simple_Auditory_Session_Stage_2", ...
    "Simple_Auditory_Session_Stage_3", ...
    "Simple_Auditory_Session_Stage_4"];
allSessionTypeNames = ["Passive Listening Task", ...
    "Go No-Go Stage 0", ...
    "Go No-Go Stage 1", ...
    "Go No-Go Stage 2", ...
    "Go No-Go Stage 3", ...
    "Go No-Go Stage 4"];

% Possible lick responses and their human-readable labels
allLickResponses = ["", ...
    "None", ...
    "R"];
allLickResponseNames = ["",...
    "No Lick", ...
    "Lick"];

% Define the columns of the trial table used to categorise trials into
% experimental groups. The experimentalGroupTable will share these columns.
experimentalGroupIdentifierColumns = ...
    ["animalName", ...
    "sessionType", ...
    "trialType", ...
    "soundVolume", ...
    "lickResponse"];
numExperimentalGroupIdentifiers = ...
    numel(experimentalGroupIdentifierColumns);

% Get the set of unique groups present in the trial table based on the
% identifier columns. Each row corresponds to a unique combination of
% animal/sessionType/trialType/soundVolume/lickResponse that actually
% appears in the data.
groupsInTrialTable = unique(sandboxTrialTable(:,experimentalGroupIdentifierColumns),'rows');
numGroupsInTrialTable = size(groupsInTrialTable,1);

% Determine the datatype of each identifier column so we can correctly
% initialize the experimental group table.
experimentalGroupIdentifierColumnsDataTypes = cell(numExperimentalGroupIdentifiers,1);
for iIdentifier=1:numExperimentalGroupIdentifiers
    experimentalGroupIdentifierColumnsDataTypes{iIdentifier} = ...
        class(groupsInTrialTable.(experimentalGroupIdentifierColumns(iIdentifier))(1));
end
    
% Define the experimentalGroupTable
% Each row of EXPERIMENTALGROUPTABLE describes one experimental group /
% channel combination.
numGroups = numGroupsInTrialTable ...
    * numChannelsEachMouse;
experimentalGroupTable = table();
experimentalGroupTable.groupName = strings(numGroups,1);
experimentalGroupTable.channelName = strings(numGroups,1);
experimentalGroupTable.channel = zeros(numGroups,1);
experimentalGroupTable.channelInCorrectLocation = false(numGroups,1);

% Initialize the group identifier columns with appropriate default values
for iIdentifier=1:numExperimentalGroupIdentifiers
    if strcmp(experimentalGroupIdentifierColumnsDataTypes{iIdentifier}, 'cell')
        experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier)) = ...
            cell(numGroups,1);
    elseif strcmp(experimentalGroupIdentifierColumnsDataTypes{iIdentifier}, 'string')
        experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier)) = ...
            strings(numGroups,1);
    elseif strcmp(experimentalGroupIdentifierColumnsDataTypes{iIdentifier},'double')
        experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier)) = ...
            zeros(numGroups,1);
    end
end


% Populate experimentalGroupTable by iterating over each unique group in
% the trial table and each possible channel for that mouse.
iGroup = 1;
for iGroupInTrialTable=1:numGroupsInTrialTable
    for iChannel=1:numChannelsEachMouse
        
        % Copy identifier values from groupsInTrialTable into the current
        % row of experimentalGroupTable.
        for iIdentifier=1:numExperimentalGroupIdentifiers
            if strcmp(experimentalGroupIdentifierColumnsDataTypes{iIdentifier}, 'cell')
                experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier)){iGroup} = ...
                    groupsInTrialTable.(experimentalGroupIdentifierColumns(iIdentifier)){iGroupInTrialTable};
            else
                experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier))(iGroup) = ...
                    groupsInTrialTable.(experimentalGroupIdentifierColumns(iIdentifier))(iGroupInTrialTable);
            end
        end

        % Set channelName, channelNumber, and channelInCorrectLocation
        % based on mouse identity and channel index.
        if ismember("animalName",experimentalGroupIdentifierColumns)
            iAnimal = find(strcmp(groupsInTrialTable.animalName(iGroupInTrialTable),allMice));
            channelColumn = find(allChannelEachMouse(iAnimal,:));
            channelColumn = channelColumn(iChannel);
    
            experimentalGroupTable.channelName(iGroup) = ...
                allChannelNames(channelColumn);
    
            experimentalGroupTable.channel(iGroup) = ...
                allChannelNumber(channelColumn);

            experimentalGroupTable.channelInCorrectLocation(iGroup) = ...
                allChannelEachMouseInCorrectLocation(iAnimal,channelColumn);
        end

        % Construct a human-readable groupName for plotting and file naming.
        groupName = "";
        if ismember("animalName",experimentalGroupIdentifierColumns)
            groupName=strcat(groupName,experimentalGroupTable.animalName(iGroup));
        end
        if experimentalGroupTable.channelName(iGroup)~=""
            groupName=strcat(groupName,"_", experimentalGroupTable.channelName(iGroup));
        end
        if ismember("sessionType",experimentalGroupIdentifierColumns)
            sessionTypeNameIndex = allSessionTypes==experimentalGroupTable.sessionType(iGroup);
            groupName=strcat(groupName,"_",allSessionTypeNames(sessionTypeNameIndex));
        end
        if ismember("trialType",experimentalGroupIdentifierColumns)
            groupName=strcat(groupName,"_",experimentalGroupTable.trialType(iGroup));
        end
        if ismember("soundVolume",experimentalGroupIdentifierColumns)
            groupName=strcat(groupName,"_",string(experimentalGroupTable.soundVolume(iGroup))," Volume");
        end
        if ismember("lickResponse",experimentalGroupIdentifierColumns)
            if experimentalGroupTable.lickResponse(iGroup)~=""
                lickResponseNameIndex = allLickResponses==experimentalGroupTable.lickResponse(iGroup);
                groupName=strcat(groupName,"_", allLickResponseNames(lickResponseNameIndex));
            end
        end
        if ~(groupName=="")
            experimentalGroupTable.groupName(iGroup) = groupName;
        end

        % Move to the next experimental group row
        iGroup = iGroup + 1;

    end
end

% Define parameters of the experimentalGroupTable that will be filled out
% once per group during trace extraction.
experimentalGroupTable.experimentalGroupTrialTable = strings(numGroups,1);
experimentalGroupTable.numTrials = zeros(numGroups,1);

% Clear unnecessary variables
clear("allMice", ...
    "allChannelEachMouse", ...
    "numChannelsEachMouse", ...
    "allChannelEachMouseInCorrectLocation", ...
    "allChannelNames", ...
    "allChannelNumber", ...
    "allSessionTypes", ...
    "allSessionTypeNames", ...
    "groupsInTrialTable", ...
    "numGroupsInTrialTable", ...
    "experimentalGroupIdentifierColumnsDataTypes", ...
    "numGroups",...
    "iGroupInTrialTable",...
    "iIdentifier",...
    "iGroupInTrialTable",...
    "iChannel",...
    "groupName",...
    "channelColumn",...
    "sessionTypeNameIndex",...
    "allLickResponses", ...
    "allLickResponseNames", ...
    "lickResponseNameIndex",...
    "iAnimal",...
    "iGroup");

%% Preprocess the table of all trials
% At this stage, sandboxTrialTable holds metadata for all trials. We now:
%   1) Add session start/end times from the Spike2 recordings.
%   2) Add trial phase timings (intertrial interval, stimulus, etc.).
%   3) Remove sessions/trials where we cannot identify key phases reliably.
%   4) Add stimulus onset/offset times.

% By default, don't run in parallel
% Change this variable to true to allow for parallel processing
% This may be unstable on some systems
runParallel = false;

% For each session, obtain the start and end times from the Spike2 file.
% sessionStartEndTime uses the signal output channel to identify session
% boundaries.
[sandboxTrialTable, ~] = trialTableFun( ...
    @(x) sessionStartEndTime(x), ...
    sandboxTrialTable, ...
    "Parallelize", runParallel, ...
    "CallOncePerSession",...
        true, ...
    "InputVariableNames",...
        "spike2Recording", ...
    "OutputVariableNames",...
        {'sessionStart','sessionEnd'});

% Remove any sessions for which the session start and/or end time could not
% be identified. We drop entire sessions to keep subsequent logic simple.
targetTrials = ~isnan(sandboxTrialTable.sessionStart) ...
    & ~isnan(sandboxTrialTable.sessionEnd);
sessionsToRemove = unique(sandboxTrialTable(~targetTrials,["animalName","sessionDate","sessionNumber"]));
targetTrials = ~(ismember(sandboxTrialTable.animalName,sessionsToRemove.animalName) ...
    & ismember(sandboxTrialTable.sessionDate,sessionsToRemove.sessionDate) ...
    & ismember(sandboxTrialTable.sessionNumber,sessionsToRemove.sessionNumber));
sandboxTrialTable = sandboxTrialTable(targetTrials,:);

% For each trial, obtain the timing of all trial phases (intertrial
% interval, stimulus period, post-stimulus delay, lick window, etc.) using
% trialPhaseTimings.
[sandboxTrialTable, ~] = trialTableFun( ...
    @(x,y,z,a) trialPhaseTimings(x,y,z,a), ...
    sandboxTrialTable, ...
    "Parallelize", runParallel, ...
    "CallOncePerSession", ...
        true, ...
    "InputVariableNames",...
        ["resultsFile", "spike2Recording", "sessionStart", "sessionEnd"],...
    "OutputVariableNames",...
        {'trialStart','trialEnd','intertrialIntervalStart', ...
        'intertrialIntervalEnd','stimulusPeriodStart', ...
        'stimulusPeriodEnd','postStimDelayStart','postStimDelayEnd', ...
        'lickportEngageStart','lickportEngageEnd','lickAllowedStart', ...
        'lickAllowedEnd','lickportDisengageStart', ...
        'lickportDisengageEnd','punishmentStart','punishmentEnd'}, ...
    "OutputVariablesRowsCorrespondToTrials", ...
        [true, true, true, true, true, true, true, true, true, true, ...
            true, true, true, true, true, true]);

% Filter out any sessions in which a full intertrial interval, stimulus
% period, and post stimulus delay cannot be discerned. Again, we remove
% entire sessions rather than single trials, to keep alignment with
% trialStimulusTimes and other per-session logic.
targetTrials = ~isnan(sandboxTrialTable.intertrialIntervalStart) ...
    & ~isnan(sandboxTrialTable.intertrialIntervalEnd) ...
    & ~isnan(sandboxTrialTable.stimulusPeriodStart) ...
    & ~isnan(sandboxTrialTable.postStimDelayEnd);
sessionsToRemove = unique(sandboxTrialTable(~targetTrials,["animalName","sessionDate","sessionNumber"]));
targetTrials = ~(ismember(sandboxTrialTable.animalName,sessionsToRemove.animalName) ...
    & ismember(sandboxTrialTable.sessionDate,sessionsToRemove.sessionDate) ...
    & ismember(sandboxTrialTable.sessionNumber,sessionsToRemove.sessionNumber));
sandboxTrialTable = sandboxTrialTable(targetTrials,:);

% For each trial, obtain stimulus onset and offset times using
% trialStimulusTimes. This uses the audio channel of the Spike2 recording
% plus trial-specific stimulus-period boundaries.
[sandboxTrialTable, ~] = trialTableFun( ...
    @(x,y,z,a,b,c) trialStimulusTimes(x,y,z,a,b,c), ...
    sandboxTrialTable, ...
    "Parallelize", runParallel, ...
    "CallOncePerSession", ...
        true, ...
    "InputVariableNames", ...
        ["resultsFile", "spike2Recording", "sessionStart", "sessionEnd", "stimulusPeriodStart", "postStimDelayEnd"], ...
    "InputVariablesRowsCorrespondToTrials", ...
        [false, false, false, false, true, true], ...
    "OutputVariableNames", ...
        {'stimulusStart', 'stimulusEnd'}, ...
    "OutputVariablesRowsCorrespondToTrials", ...
        [true true]);

% In rare cases, multiple stimuli may be detected during the nominal
% stimulus period due to low SNR in the audio channel. For robust analysis,
% we remove trials where multiple distinct stimulus segments are detected.
if iscell(sandboxTrialTable.stimulusStart(1))
    multipleStimuli = rowfun(@(x) numel(x{:}) > 1, sandboxTrialTable, "InputVariables","stimulusStart","OutputFormat","uniform");
else
    multipleStimuli = rowfun(@(x) numel(x(:)) > 1, sandboxTrialTable, "InputVariables","stimulusStart","OutputFormat","uniform");
end
if any(multipleStimuli)
    sandboxTrialTable = sandboxTrialTable(~multipleStimuli,:);

    holdingVariable = vertcat(sandboxTrialTable.stimulusStart{:});
    sandboxTrialTable.stimulusStart = [];
    sandboxTrialTable.stimulusStart = holdingVariable;

    holdingVariable = vertcat(sandboxTrialTable.stimulusEnd{:});
    sandboxTrialTable.stimulusEnd = [];
    sandboxTrialTable.stimulusEnd = holdingVariable;

end

% Clear unnecessary variables
clear("targetTrials",...
    "sessionsToRemove",...
    "holdingVariable",...
    "multipleStimuli");

%% Set the location where the data will be saved
% Define the directory where the experimental group trial tables will be
% saved. One .mat file per experimental group will be written here, plus a
% summary experimentalGroupTable.mat file.
experimentalGroupTrialTableDirectory = "..\Processed Data\";
if ~exist(experimentalGroupTrialTableDirectory, 'dir')
   mkdir(experimentalGroupTrialTableDirectory);
end

%% Trace Extraction Settings
% Change these parameters to change the peristimulus window used for trace
% extraction. The chosen windows are somewhat larger than the intended
% plotting window to avoid edge effects in later spectrogram calculations.
peristimulusWindowLeft = 3;
peristimulusWindowRight = 3;

%% Obtain the peristimulus and intertrial interval traces
% For each experimental group:
%   - Filter sandboxTrialTable to obtain the group's trials.
%   - Extract intertrial-interval (baseline) traces.
%   - Extract peristimulus traces centered on stimulus onset.
%   - Discard trials where valid traces are not available.
%   - Normalize traces based on the intertrial-interval distribution.
%   - Save the group-specific trial table to disk and record its path in
%     experimentalGroupTable.
numGroups = size(experimentalGroupTable,1);
for iGroup=1:numGroups


    % Report to terminal the current group being processed
    disp("Processing group " + string(iGroup) + " of " + string(numGroups) + "...");
    tic;


    % Filter sandboxTrialTable to create the experimental group trial
    % table. Only keep columns required downstream for trace extraction.
    experimentalGroupTrials = true(size(sandboxTrialTable,1),1);
    for iIdentifier=1:numExperimentalGroupIdentifiers
        experimentalGroupTrials = experimentalGroupTrials ...
            & (...
                experimentalGroupTable.(experimentalGroupIdentifierColumns(iIdentifier))(iGroup) ...
                == ...
                sandboxTrialTable.(experimentalGroupIdentifierColumns(iIdentifier))...
            );
    end

    % Skip if there are no trials in this group
    if sum(experimentalGroupTrials) == 0

        % Report to terminal that no trials were found
        disp("No trials in the sandbox trial table were found in the current experimental group. Skipping.");

        continue
    end

    % Create the experimental group trial table by slicing
    % sandboxTrialTable and keeping only essential columns.
    experimentalGroupTrialTable = sandboxTrialTable(experimentalGroupTrials,...
        ["animalName","sessionDate","sessionNumber","trialNumber", ...
        "spike2Recording","intertrialIntervalStart","intertrialIntervalEnd",...
        "stimulusStart","stimulusEnd"]);

    % Clear unnecessary variables
    clear("experimentalGroupTrials", ...
        "iIdentifier");


    % Extract the intertrial interval traces
    % Here we define the intertrial-interval baseline as the 2 seconds
    % immediately preceding the stimulus onset.
    [experimentalGroupTrialTable, ~] = trialTableFun( ...
        @(x,y) trialSliceRecordingBetween(x,experimentalGroupTable.channel(iGroup),y-2,y), ...
        experimentalGroupTrialTable, ...
        "Parallelize", runParallel, ...
        "CallOncePerSession", ...
            true, ...
        "InputVariableNames", ...
            ["spike2Recording","stimulusStart"],...
        "InputVariablesRowsCorrespondToTrials", ...
            [false, true, true], ...
        "OutputVariableNames",...
            {'intertrialIntervalTrace','intertrialIntervalTraceTimes'}, ...
        "OutputVariablesRowsCorrespondToTrials", ...
            [true true]);

    % Extract the peristimulus trial traces
    % For each trial, extract an LFP window around stimulus onset using
    % trialSliceRecordingWindow. The window is defined as:
    %   [stimulusStart - peristimulusWindowLeft,
    %    stimulusStart + peristimulusWindowRight].
    [experimentalGroupTrialTable, ~] = trialTableFun( ...
        @(x,y) trialSliceRecordingWindow(x,experimentalGroupTable.channel(iGroup),y,'windowSizeLeft',peristimulusWindowLeft,'windowSizeRight',peristimulusWindowRight), ...
        experimentalGroupTrialTable, ...
        "Parallelize", runParallel, ...
        "CallOncePerSession", ...
            true, ...
        "InputVariableNames", ...
            ["spike2Recording","stimulusStart"], ...
        "InputVariablesRowsCorrespondToTrials", ...
            [false, true], ...
        "OutputVariableNames", ...
            {'peristimulusTrace','peristimulusTraceTimes'}, ...
        "OutputVariablesRowsCorrespondToTrials", ...
            [true true]);


    % Remove trials that do not have valid intertrial and peristimulus traces
    if iscell(experimentalGroupTrialTable.intertrialIntervalTrace)
        invalidTrials = cellfun(@(x) isempty(x) || isnan(x(1)), experimentalGroupTrialTable.intertrialIntervalTrace);
    else
        invalidTrials = any(isnan(experimentalGroupTrialTable.intertrialIntervalTrace),2);
    end

    if iscell(experimentalGroupTrialTable.peristimulusTrace)
        invalidTrials = invalidTrials | cellfun(@(x) isempty(x) || isnan(x(1)), experimentalGroupTrialTable.peristimulusTrace);
    else
        invalidTrials = invalidTrials | any(isnan(experimentalGroupTrialTable.peristimulusTrace),2);
    end
    
    % If all trials in this group are invalid, skip this group entirely.
    if all(invalidTrials)

        % Report to terminal that none of the trials in the current group
        % had both intertrial interval traces and peristimulus trial
        % traces.
        disp("No trials were found in the current group with both intertrial interval and peristimulus traces. Skipping to next group.");

        continue
    elseif any(invalidTrials)
        experimentalGroupTrialTable = experimentalGroupTrialTable(~invalidTrials,:);
    end

    clear("invalidTrials");


    % Normalize peristimulus time axis relative to stimulus onset
    % Convert peristimulusTraceTimes into a time axis relative to stimulus
    % onset, with 0 aligned to the stimulus.
    [experimentalGroupTrialTable, ~] = trialTableFun( ...
        @(x) x-min(x)-peristimulusWindowLeft, ...
        experimentalGroupTrialTable, ...
        "Parallelize", runParallel, ...
        "CallOncePerSession", ...
            true, ...
        "InputVariableNames", ...
            "peristimulusTraceTimes", ...
        "OutputVariableNames", ...
            {'peristimulusTraceTimesRelativeStimulus'});


    % Normalize traces based on the intertrial interval trace distribution
    % First, z-score the intertrial-interval traces individually.
    [experimentalGroupTrialTable, ~] = trialTableFun( ...
        @(x) (x-mean(x))/std(x), ...
        experimentalGroupTrialTable, ...
        "Parallelize", runParallel, ...
        "InputVariableNames", ...
            "intertrialIntervalTrace", ...
        "OutputVariableNames", ...
            {'intertrialIntervalTraceNormalized'});

    % Then, z-score each peristimulus trace using the mean and std of the
    % corresponding intertrial-interval trace.
    [experimentalGroupTrialTable, ~] = trialTableFun( ...
        @(x,y) (x-mean(y))/std(y), ...
        experimentalGroupTrialTable, ...
        "Parallelize", runParallel, ...
        "InputVariableNames", ...
            ["peristimulusTrace","intertrialIntervalTrace"], ...
        "OutputVariableNames", ...
            {'peristimulusTraceNormalized'});


    % Save the experimental group trial table
    filePathName = strcat(...
        experimentalGroupTrialTableDirectory, ...
        experimentalGroupTable.groupName(iGroup), ...
        ".mat");
    save(filePathName, 'experimentalGroupTrialTable', '-v7.3')

    % Store the file path and number of trials in experimentalGroupTable
    experimentalGroupTable.experimentalGroupTrialTable(iGroup) = ...
        filePathName;
    experimentalGroupTable.numTrials(iGroup) = ...
        size(experimentalGroupTrialTable,1);

    % Report completion of processing the experimental group to the
    % terminal.
    disp("Done. Finished in " + string(toc) + " seconds.");

end

% Remove any experimental groups that did not produce a trial table (e.g.,
% no valid trials after filtering) from experimentalGroupTable.
hasExperimentalGroupTrialTable = ~(experimentalGroupTable.experimentalGroupTrialTable == "");
experimentalGroupTable = experimentalGroupTable(hasExperimentalGroupTrialTable,:);

% Save the experimental group table
filePathName = strcat(...
    experimentalGroupTrialTableDirectory, ...
    "experimentalGroupTable.mat");
save(filePathName, 'experimentalGroupTable', '-v7.3')

% Final cleanup of temporary variables
clear("experimentalGroupIdentifierColumns", ...
    "experimentalGroupTrials", ...
    "experimentalGroupTrialTable", ...
    "filePathName", ...
    "hasExperimentalGroupTrialTable", ...
    "iGroup", ...
    "numGroups", ...
    "iIdentifier", ...
    "numExperimentalGroupIdentifiers", ...
    "sandboxTrialTable");
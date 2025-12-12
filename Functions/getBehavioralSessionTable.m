%{
Date Created: 4/7/2023
Description: This funnction scans a directory tree for behavioral 
session–related files (results text, Spike2 recordings, Excel datasheets, 
and pupillometry videos) and assembles a session-level summary table. Each
row in the output table represents a single behavioral session with 
associated file paths and metadata.
%}

function behavSessionTable = getBehavioralSessionTable(directory, varargin)
    % GETBEHAVIORALSESSIONTABLE  Build a behavioral session summary table.
    %
    %   behavSessionTable = GETBEHAVIORALSESSIONTABLE(directory, ...) scans
    %   directory for files associated with behavioral experiments and
    %   aggregates them into a session table. Each row in behavSessionTable
    %   corresponds to one behavioral session and includes (as available):
    %       - animalName
    %       - sessionDate
    %       - sessionNumber
    %       - sessionType (if resolvable)
    %       - resultsFile (behavioral results .txt)
    %       - spike2Recording (.smrx)
    %       - excelDataSheet (animal datasheet .xlsx)
    %       - pupillometryRecording (.avi)
    %
    %   Required Input:
    %       directory   
    %           - Path to the root folder containing behavioral data. This
    %           folder is searched for matching files.
    %
    %   Name–Value Pair Arguments:
    %       'Recursive' 
    %           - Logical flag indicating whether to search directory
    %           recursively (default = true). If true, all subfolders are
    %           searched; otherwise only the top-level directory is 
    %           scanned.
    %
    %   Output:
    %     behavSessionTable 
    %       - A sessionTable-style table in which each row represents a 
    %           single behavioral session and columns store associated file
    %           paths and inferred metadata (session type where possible).
    %
    %   File naming assumptions:
    %       - Behavioral results:
    %           <AnimalName>_<MM-dd-yy>_session_results[_...].txt
    %       - Spike2 recordings:
    %           <AnimalName>_<MM-dd-yy>[_sN].smrx
    %       - Excel datasheets:
    %           <...>_Data Sheets.xlsx (animal name in second token)
    %       - Pupillometry recordings:
    %           <AnimalName>_<MM-dd-yy>[_sN]_Pupillometry
    %           Recording[_...].av
    %
    %   The function attempts to match files across modalities (results,
    %   Spike2, Excel, pupillometry) based on (animalName, sessionDate,
    %   sessionNumber), and then infers sessionType from the results text 
    %   file where available, or from the Excel datasheet as a fallback.
    %
    %   See also sessionTable, openResults.

    % Parse and validate inputs
    p = inputParser;
    p.addRequired('directory',@isfolder)
    p.addOptional('Recursive',true,@islogical)
    p.parse(directory,varargin{:})
    
    % Collect all file paths within directory (optionally recursively)
    % Use dir with fullfile; avoid changing the current working directory.
    if p.Results.Recursive
        fileStruct = dir(fullfile(directory,"**\*.*"));
    else
        fileStruct = dir(directory);
    end
    fileNames = strcat({fileStruct.folder},"\",{fileStruct.name});
    
    
    % Classify files by type based on filename patterns
    % Results files: behavioral session results text
    resultsFiles = fileNames(~cellfun(@isempty,regexp(fileNames,"[\/\\]{1,2}[\w\s-]+_session_results([\w\s-]+)?.txt$")));

    % Spike2 recordings: .smrx files
    spike2Recordings = fileNames(~cellfun(@isempty,regexp(fileNames,"[\/\\]{1,2}[\w\s-]+.smrx$")));

    % Excel datasheets: per-animal "Data Sheets" workbooks
    excelDataSheets = fileNames(~cellfun(@isempty,regexp(fileNames,"[\/\\]{1,2}[\w\s-]+_Data Sheets.xlsx$")));

    % Pupillometry videos: AVI files with specific suffix
    pupillometryRecordings = fileNames(~cellfun(@isempty,regexp(fileNames,"[\/\\]{1,2}[\w\s-]+_Pupillometry Recording([\w\s-]+)?.avi$")));
    
    % Preallocate the session table based on an upper bound on sessions
    % Upper bound: count of all candidate session-related files.
    maxNumSessions = length(resultsFiles) + length(spike2Recordings) + length(excelDataSheets) + length(pupillometryRecordings);

    % Create a sessionTable with enough rows, then add file-path columns.
    behavSessionTable = sessionTable(maxNumSessions);
    behavSessionTable.sessionType = strings(maxNumSessions,1);
    behavSessionTable.resultsFile = strings(maxNumSessions,1);
    behavSessionTable.spike2Recording = strings(maxNumSessions,1);
    behavSessionTable.excelDataSheet = strings(maxNumSessions,1);
    behavSessionTable.pupillometryRecording = strings(maxNumSessions,1);
    
    % Populate rows based on behavioral results files
    % Each results file defines at least one session entry.
    for i=1:length(resultsFiles)
        
        % Parse filename into components:
        %   <folder>/<AnimalName>_<MM-dd-yy>_... .txt
        fileName = split(resultsFiles(i),["/","\"]);
        fileName = split(fileName(end), [".","_"]);
        
        behavSessionTable.animalName(i) = fileName(1);
        behavSessionTable.sessionDate(i) = datetime(fileName(2),'InputFormat','MM-dd-yy');

        % Session number: parse "sN" style suffix if present, otherwise 1.
        if isempty(regexp(fileName(end-1),"^s?[0-9]+$",'ONCE'))
            behavSessionTable.sessionNumber(i) = 1;
        else
            behavSessionTable.sessionNumber(i) = str2double(strip(fileName(end-1),'s'));
        end
        behavSessionTable.resultsFile(i) = resultsFiles(i);
        
    end
    % Index pointing to the next unfilled row in behavSessionTable
    sessionTableIndex = i+1;
    
    % Associate Spike2 recordings with existing or new sessions
    for i=1:length(spike2Recordings)
        
        fileName = split(spike2Recordings(i),["/","\"]);
        fileName = split(fileName(end), [".","_"]);
        
        animalName = fileName(1);
        sessionDate = datetime(fileName(2),'InputFormat','MM-dd-yy');

        % Session number: parse "sN" suffix if present, otherwise 1.
        if isempty(regexp(fileName(end-1),"^s[0-9]+$",'ONCE'))
            sessionNumber = 1;
        else
            sessionNumber = str2double(strip(fileName(end-1),'s'));
        end
        
        % Attempt to match this recording to an existing session row.
        matchedSessions = strcmp(behavSessionTable.animalName,animalName) & ...
            (behavSessionTable.sessionDate == sessionDate) & ...
            (behavSessionTable.sessionNumber == sessionNumber);
        
        numMatchedSessions = sum(matchedSessions);
        if numMatchedSessions == 0
            
            % New session: create a new row.
            behavSessionTable.animalName(sessionTableIndex) = animalName;
            behavSessionTable.sessionDate(sessionTableIndex) = sessionDate;
            behavSessionTable.sessionNumber(sessionTableIndex) = sessionNumber;
            behavSessionTable.spike2Recording(sessionTableIndex) = spike2Recordings(i);
            
            sessionTableIndex = sessionTableIndex + 1;
            
        elseif numMatchedSessions == 1
            
            % Existing session: fill in spike2Recording field.
            behavSessionTable.spike2Recording(matchedSessions) = spike2Recordings(i);
            
        else

            % Multiple matches: ambiguous mapping, so skip this recording.
            warning("The Spike2 recording " + resultsFiles(i) + " matches more than one entry in the session table. Skipping.")
        end
        
    end
    
    % Attach Excel datasheets by animal name
    % Excel datasheets are per-animal; associate them with all sessions
    % for that animal.
    for i=1:length(excelDataSheets)
        
        fileName = split(excelDataSheets(i),["/","\"]);
        fileName = split(fileName(end), [".","_"]);
        
        % In this naming convention the animal name is taken from the
        % second token in the base filename.
        animalName = fileName(2);
        
        behavSessionTable.excelDataSheet(strcmp(behavSessionTable.animalName,animalName)) = excelDataSheets(i);
    end
    
    % Associate pupillometry recordings with sessions
    for i=1:length(pupillometryRecordings)
        
        fileName = split(pupillometryRecordings(i),["/","\"]);
        fileName = split(fileName(end), [".","_"]);
        
        animalName = fileName(1);
        sessionDate = datetime(fileName(2),'InputFormat','MM-dd-yy');
        if isempty(regexp(fileName(end-1),"^s[0-9]+$",'ONCE'))
            sessionNumber = 1;
        else
            sessionNumber = str2double(strip(fileName(end-1),'s'));
        end 
        
        matchedSessions = strcmp(behavSessionTable.animalName,animalName) & ...
            (behavSessionTable.sessionDate == sessionDate) & ...
            (behavSessionTable.sessionNumber == sessionNumber);
        
        numMatchedSessions = sum(matchedSessions);
        if numMatchedSessions == 0
            
            % New session inferred from pupillometry alone.
            behavSessionTable.animalName(sessionTableIndex) = animalName;
            behavSessionTable.sessionDate(sessionTableIndex) = sessionDate;
            behavSessionTable.sessionNumber(sessionTableIndex) = sessionNumber;
            behavSessionTable.pupillometryRecording(sessionTableIndex) = pupillometryRecordings(i);
            
            sessionTableIndex = sessionTableIndex + 1;
            
        elseif numMatchedSessions == 1
            
            % Existing session: attach the pupillometry file.
            behavSessionTable.pupillometryRecording(matchedSessions) = pupillometryRecordings(i);
            
        else

            % Multiple matching sessions: ambiguous mapping.
            warning("The pupillometry recording " + resultsFiles(i) + " matches more than one entry in the session table. Skipping.")
        end
        
    end
    
    % Trim unused preallocated rows
    behavSessionTable = behavSessionTable(1:sessionTableIndex-1,:);
    
    % Infer session type where possible
    % For each row, try to determine the behavioral session type using the
    % results file first, and if that fails, use the Excel datasheet.
    for i=1:size(behavSessionTable,1)
        
        % Attempt to infer session type from the results .txt file
        try
            sessionResultsTable = openResults(behavSessionTable.resultsFile(i));
            behavSessionTable.sessionType(i) = sessionResultsTable.session_type(1);
            continue
        catch
            warning(strcat("Unable to open the results file for ", ...
                behavSessionTable.animalName(i), " ", ...
                string(behavSessionTable.sessionDate(i)), " session ", ...
                string(behavSessionTable.sessionNumber(i)), ...
               " while attempting to identify session type. Continuing with alternate method."));
        end
        
        % Attempt to infer session type from the Excel datasheet
        stageNumberTypeKeys = [
            "Passive Listening 1", ...
            "Go/No-Go 0",...
            "Go/No-Go 1", ...
            "Go/No-Go 2", ...
            "Go/No-Go 3", ...
            "Go/No-Go 4"];

        sessionTypeStrings = ["Passive Listening Task", ...
            "Simple_Auditory_Session_Stage_0", ...
            "Simple_Auditory_Session_1", ...
            "Simple_Auditory_Session_2", ...
            "Simple_Auditory_Session_3", ...
            "Simple_Auditory_Session_4"];

        sessionTypeKeyStringMap = containers.Map(stageNumberTypeKeys,sessionTypeStrings);

        try
            
            % Open the behavioral datasheet for this animal as a table.
            warning('off','MATLAB:table:ModifiedAndSavedVarnames')
            excelSheet = readtable(behavSessionTable.excelDataSheet(i),'Sheet','Behavioral Session Data');
            
            % Identify rows corresponding to this session date.
            dateMatchedTrials = excelSheet.Date == behavSessionTable.sessionDate(i);

            % Extract the candidate stage numbers and session types.
            possibleStageNumbers = unique(excelSheet.Stage(dateMatchedTrials));
            possibleSessionTypes = unique(string(excelSheet.SessionType{dateMatchedTrials}));
            
            % Only assign a session type if the mapping is unambiguous.
            if length(possibleStageNumbers) == 1 && ~isnan(possibleStageNumbers) && ...
                    length(possibleSessionTypes) == 1 && ~ismissing(possibleSessionTypes)
                sessionTypeKey = strcat(string(possibleSessionTypes)," ",string(possibleStageNumbers));
                behavSessionTable.sessionType(i) = sessionTypeKeyStringMap(sessionTypeKey);
            else

            warning(strcat("Unable to identify the session type of ", ...
                behavSessionTable.animalName(i), " ", ...
                string(behavSessionTable.sessionDate(i)), " session ", ...
                string(behavSessionTable.sessionNumber(i)), ...
               ". Skipping."));
            end
            
        catch
            warning(strcat("Unable to identify the session type of ", ...
                behavSessionTable.animalName(i), " ", ...
                string(behavSessionTable.sessionDate(i)), " session ", ...
                string(behavSessionTable.sessionNumber(i)), ...
               ". Skipping."));
        end
        
        
    end
        
end


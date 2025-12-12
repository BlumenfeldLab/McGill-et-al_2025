%{
Date Created: 3/1/2024
Description: Idenntifies the start and end times of a behavioral session 
from a Spike2 recording using the digital/analog signal output channel. 
This function is used early in the preprocessing pipeline to define the 
temporal bounds of each session before trial- and event-level parsing.
%}

function [sessionStart,sessionEnd] = sessionStartEndTime(spike2File, varargin)
    % SESSIONSTARTENDTIME  Determine session start and end times from 
    %   Spike2 data.
    %
    %   [sessionStart, sessionEnd] = SESSIONSTARTENDTIME(spike2File) uses 
    %   the default signal output channel (SigOutChan = 15) in the Spike2 
    %   recording specified by spike2File to estimate the start and end 
    %   times of the behavioral session.
    %
    %   spike2File may be either:
    %     - a string path to a Spike2 file (.smrx/.s2rx), in which case the
    %       file is opened via CEDS64OPEN and closed internally
    %     - an existing CEDS64 file handle, which will be used directly and
    %       not closed by this function.
    %
    %   [sessionStart, sessionEnd] = SESSIONSTARTENDTIME(spike2File, 'SigOutChan', N) 
    %   uses channel N as the signal output channel from which to infer the
    %   session boundaries. Internally, this function calls findSignal to 
    %   detect message or marker blocks on the output channel and uses 
    %   their timing to set sessionStart and sessionEnd. If the session 
    %   boundaries cannot be determined, both outputs are returned as NaN.
    %
    %   See also findSignal, CEDS64Open, CEDS64Close.

    % Parse and validate inputs. Allow spike2File to be a path (string) or
    % a pre-opened file handle. SigOutChan specifies the signal output
    % channel used to detect the session boundaries.
    p = inputParser;
    p.addRequired('spike2File', @(x) isstring(x) | isnumeric(x) | islogical(x));
    p.addOptional('SigOutChan', 15, @isnumeric);
    p.parse(spike2File,varargin{:});

    % Set default output values (used if the recording cannot be opened or
    % the session boundaries cannot be identified).
    sessionStart = NaN;
    sessionEnd = NaN;

    % If spike2File is a string path, open it. Otherwise, treat it as an
    % existing CEDS64 file handle.
    openedSpike2File = false;
    if isstring(p.Results.spike2File)
        session1401Recording = CEDS64Open(convertStringsToChars(p.Results.spike2File));
        openedSpike2File = true;
    else
        session1401Recording = p.Results.spike2File;
    end

    % Validate that the Spike2 file has been opened successfully.
    if session1401Recording == -1 || session1401Recording == 0

        warning( ...
            strcat( ...
                "(sessionStartEndTime) Unable to open the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

        return
    end

    % Identify the start and end of the session using findSignal on the
    % designated signal output channel. The convention used here is to take
    % the end of the first detected message block as the session start and
    % the start of the second detected message block as the session end.
    try
        [tMessagesStart,tMessagesEnd] = findSignal(session1401Recording,p.Results.SigOutChan);
        sessionStart = tMessagesEnd(1); 
        sessionEnd = tMessagesStart(2);
    catch
        
        warning( ...
            strcat( ...
                "(sessionStartEndTime) Unable to identify the session start and end time for the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

    end

    % Close the opened Spike2 file to free up memory, if this function
    % opened it.
    if openedSpike2File
        CEDS64Close(session1401Recording);
    end
    
end
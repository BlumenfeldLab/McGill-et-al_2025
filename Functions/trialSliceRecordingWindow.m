%{
Date Created: 3/8/2024
Description: Extracts one or more time-windowed segments from a single 
channel in a Spike2 recording, centered on specified time points. Each 
window extends a configurable duration to the left and right of the center
time, with zero-padding applied when windows partially exceed the recording
bounds.
%}

function [traces, times, sIntervSecs] = trialSliceRecordingWindow(spike2File,iChan,tWindowCenter,varargin)
    % TRIALSLICERECORDINGWINDOW  Extract fixed-size windows around center 
    %   times.
    %
    %   [traces, times, sIntervSecs] = TRIALSLICERECORDINGWINDOW(spike2File, iChan, tWindowCenter, ...)
    %   extracts one or more waveform segments from channel iChan of a 
    %   Spike2 recording. Each segment is defined as a time window that 
    %   extends a fixed interval to the left and right of a specified 
    %   center time.
    %
    %   Inputs:
    %       spike2File
    %           - String path to a Spike2 .smrx/.s2rx file, or an open
    %           CEDS64 file handle.
    %
    %       iChan
    %           - Numeric index of the channel to extract from.
    %
    %       tWindowCenter
    %           - Numeric scalar or vector, or a cell array of numeric 
    %           values. Each element specifies the center time of a desired
    %           window (in seconds, relative to the recording).
    %
    %   Name–Value Pairs:
    %       'windowSizeLeft'
    %           - Scalar, number of seconds to include to the left (i.e.
    %           towards the past) of each center time (default = 1).
    %
    %       'windowSizeRight'
    %           - Scalar, number of seconds to include to the right (i.e.
    %           twoards the future) of each center time (default = 1).
    %
    %   Outputs:
    %     traces
    %           - If a single window is requested, a numeric vector
    %           containing the extracted samples (with potential 
    %           zero-padding). If multiple windows are requested, a column
    %           cell array where each cell contains the samples for one 
    %           window.
    %
    %     times
    %           - Time stamps (seconds) corresponding to TRACES. For a 
    %           single window, a numeric vector. For multiple windows, a
    %           cell array of numeric vectors (one per window).
    %
    %     sIntervSecs
    %           - Sampling interval (seconds per sample) of channel iChan
    %           in the Spike2 recording.
    %
    %   Notes:
    %     - If tWindowCenter is provided as a cell array, it is converted
    %       to a numeric array.
    %     - If a requested window extends beyond the available recording,
    %       the returned trace is zero-padded on the left and/or right to
    %       preserve the requested time extent.
    %     - If a center time is empty or NaN, the corresponding output
    %       window is empty.
    %
    %   See also CEDS64ChanDiv, CEDS64TicksToSecs, 
    %   trialSliceRecordingBetween.

    % Parse and validate inputs
    p = inputParser;
    p.addRequired('spike2File', @(x) isstring(x) | isnumeric(x) | islogical(x));
    p.addRequired('iChan',@isnumeric);
    p.addRequired('tWindowCenter',@(x) isnumeric(x) | iscell(x));
    p.addOptional('windowSizeLeft',1,@isnumeric);
    p.addOptional('windowSizeRight',1,@isnumeric);
    p.parse(spike2File,iChan,tWindowCenter,varargin{:});

    % Normalize tWindowCenter: convert cell input to numeric if needed
    % For downstream indexing logic it is simpler to treat the center times
    % as a numeric array.
    if iscell(p.Results.tWindowCenter)
        tWindowCenter = cell2mat(tWindowCenter);
    end

    % Initialize default outputs
    numTraces = size(tWindowCenter,1);
    traces = num2cell(NaN(numTraces,1));
    times = num2cell(NaN(numTraces,1));
    sIntervSecs = NaN;

    % Open or assign the Spike2 file handle
    openedSpike2File = false;
    if isstring(p.Results.spike2File)
        % spike2File is a path; open a new CEDS64 recording handle.
        session1401Recording = CEDS64Open(convertStringsToChars(p.Results.spike2File));
        openedSpike2File = true;
    else
        % spike2File is assumed to be an existing CEDS64 handle.
        session1401Recording = p.Results.spike2File;
    end

    % Validate that the Spike2 file has been opened successfully.
    if session1401Recording == -1 || session1401Recording == 0

        warning( ...
            strcat( ...
                "(trialSliceRecordingWindow) Unable to open the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

        return
    end

    % Get sampling interval and full waveform for the requested channel
    % sIntervTicks: number of ticks between consecutive samples.
    % sIntervSecs:  seconds between consecutive samples.
    sIntervTicks = CEDS64ChanDiv(session1401Recording,iChan);
    sIntervSecs = CEDS64TicksToSecs(session1401Recording, sIntervTicks);
    
    % Read the entire waveform from channel iChan. This serves as the
    % source for extracting all requested windows.
    endTick = CEDS64ChanMaxTime(session1401Recording,iChan);
    iN = round((endTick/sIntervTicks)+1);
    [~,elecWaveform,~] = CEDS64ReadWaveF(session1401Recording, iChan, iN, 0, endTick);
    elecWaveform = elecWaveform';
    
    % Convert center times and window sizes to index bounds
    % For each center time, we compute indices corresponding to:
    %   [center - windowSizeLeft, center + windowSizeRight]
    % in sample units. Rounding is used intentionally to avoid small
    % floating-point differences causing off-by-one inconsistencies.
    windowLowerIndex = round(tWindowCenter/sIntervSecs) - round(p.Results.windowSizeLeft/sIntervSecs);
    windowUpperIndex = round(tWindowCenter/sIntervSecs) + round(p.Results.windowSizeRight/sIntervSecs);
    
    % Slice behavior depends on number of requested windows
    numberSlices = numel(tWindowCenter);
    
    % Single-window mode: return numeric vectors
    % When only one window is requested, TRACES and TIMES are returned as
    % plain numeric vectors (or empty vectors), rather than cell arrays.
    if numberSlices == 1
        
        % Determine the slice mode:
        %   bit 0 (1): lower index is in bounds
        %   bit 1 (2): upper index is in bounds
        %   bit 2 (4): empty or NaN center time
        sliceMode = (windowLowerIndex >= 1) + ...
            2 * (windowUpperIndex <= length(elecWaveform)) + ...
            4*(isempty(tWindowCenter) | isnan(tWindowCenter));

        switch sliceMode

            % Case 0: both indices out of bounds
            % zero-pad both sides
            case 0
                numMissingIndicesLeft = -1 * windowLowerIndex + 1;
                numMissingIndicesRight = windowUpperIndex - length(elecWaveform);
                traces = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex) zeros(1,numMissingIndicesRight)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
             % Case 1: upper in bounds, lower out of bounds
             % zero-pad left
            case 1
                numMissingIndicesLeft = -1 * windowLowerIndex + 1;
                traces = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);

            % Case 2: lower in bounds, upper out of bounds
            % zero-pad right
            case 2
                numMissingIndicesRight = windowUpperIndex - length(elecWaveform);
                traces = [elecWaveform(windowLowerIndex:length(elecWaveform)) zeros(1,numMissingIndicesRight)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
            % Case 3: both indices in bounds 
            % standard slice
            case 3
                traces = elecWaveform(windowLowerIndex:windowUpperIndex);
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
            % Default: empty or NaN center time -> empty outputs
            otherwise
                traces = [];
                times = [];
        end
    
    % Multi-window mode: return cell arrays
    % When more than one window is requested, traces and times are column
    % cell arrays; each cell holds one window and its time vector.
    elseif numberSlices > 1
        
        % Instantiate the output cell arrays
        traces = cell(numberSlices,1);
        times = cell(numberSlices,1);
        
        % Iterate over each center time
        for i=1:numberSlices
            
            % Determine slice mode for this specific window.
            sliceMode = (windowLowerIndex(i) >= 1) + ...
                2 * (windowUpperIndex(i) <= length(elecWaveform)) + ...
                4*(isnan(tWindowCenter(i)));

            switch sliceMode

                % Case 0: both indices out of bounds
                % zero-pad both sides
                case 0
                    numMissingIndicesLeft = -1 * windowLowerIndex(i) + 1;
                    numMissingIndicesRight = windowUpperIndex(i) - length(elecWaveform);
                    traces{i} = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex(i)) zeros(1,numMissingIndicesRight)];
                    times{i} = (windowLowerIndex(i)*sIntervSecs):sIntervSecs:(windowUpperIndex(i)*sIntervSecs);

                % Case 1: upper in bounds, lower out of bounds
                % zero-pad left
                case 1
                    numMissingIndicesLeft = -1 * windowLowerIndex(i) + 1;
                    traces{i} = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex(i))];
                    times{i} = (windowLowerIndex(i)*sIntervSecs):sIntervSecs:(windowUpperIndex(i)*sIntervSecs);

                % Case 2: lower in bounds, upper out of bounds
                % zero-pad right
                case 2
                    numMissingIndicesRight = windowUpperIndex(i) - length(elecWaveform);
                    traces{i} = [elecWaveform(windowLowerIndex(i):length(elecWaveform)) zeros(1,numMissingIndicesRight)];
                    times{i} = (windowLowerIndex(i)*sIntervSecs):sIntervSecs:(windowUpperIndex(i)*sIntervSecs);

                % Case 3: both indices in bounds 
                % standard slice
                case 3
                    traces{i} = elecWaveform(windowLowerIndex(i):windowUpperIndex(i));
                    times{i} = (windowLowerIndex(i)*sIntervSecs):sIntervSecs:(windowUpperIndex(i)*sIntervSecs);

                % Default: empty or NaN center time -> empty outputs
                otherwise
                    traces{i} = [];
                    times{i} = [];
            end
            
        end
        
    end

    % Close the Spike2 file if this function opened it
    if openedSpike2File
        CEDS64Close(session1401Recording);
    end

end


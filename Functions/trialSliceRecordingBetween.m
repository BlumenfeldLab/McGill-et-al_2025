%{
Date Created: 3/8/2024
Description: This function extracts one or more time-windowed segments from
a single channel in a Spike2 recording, returning the waveform slices and 
corresponding time vectors. Supports scalar or vector inputs for 
tStart/tEnd and will zero-pad segments when requested windows extend beyond
the available recording.
%}

function [traces, times, sIntervSecs] = trialSliceRecordingBetween(spike2File,iChan,tStart,tEnd)
    % TRIALSLICERECORDINGBETWEEN  Extract channel segments between time bounds.
    %
    %   [traces, times, sIntervSecs] = TRIALSLICERECORDINGBETWEEN(spike2File, iChan, tStart, tEnd)
    %   extracts one or more waveform segments from channel ICHAN of a 
    %   Spike2 recording.
    %
    %   Inputs:
    %       spike2File
    %           - Either a string path to a Spike2 .smrx/.s2rx file or an 
    %           open CEDS64 file handle.
    %
    %       iChan
    %           - Numeric index of the channel to extract from.
    %
    %       tStart
    %           - Numeric scalar or vector, or a cell array of numeric
    %           times (seconds). Each element specifies the start time of a
    %           desired segment in the recording frame.
    %
    %       tEnd        
    %           - Numeric scalar or vector, or a cell array of numeric
    %           times (seconds). Each element specifies the end time of a 
    %           desired segment, corresponding element-wise to tStart.
    %
    %   Outputs:
    %       traces      
    %           - If a single segment is requested, a numeric vector 
    %           containing the extracted samples (with potential 
    %           zero-padding). If multiple segments are requested, a column
    %           cell array where each cell contains the samples for one 
    %           segment.
    %
    %     times
    %           - Time stamps (seconds) corresponding to traces. For a 
    %           single segment, a numeric vector. For multiple segments, a
    %           cell array of numeric vectors.
    %
    %     sIntervSecs
    %       - Sampling interval (seconds per sample) of channel iChan in 
    %       the Spike2 recording.
    %
    %   notes:
    %       - If tStart/tEnd are provided as cell arrays, they are 
    %       converted to numeric arrays.
    %       - If a requested [tStart, tEnd] window falls partially outside
    %       the range of the recording, the returned segment is zero-padded
    %       on the left and/or right to match the requested time window.
    %       - If tStart or tEnd for a given window is empty or NaN, that
    %       window yields an empty trace and time vector.
    %
    %   See also CEDS64ChanDiv, CEDS64TickstoSecs, 
    %   trialSlicerecordingWindow.

    % Validate and parse inputs
    p = inputParser;
    p.addRequired('spike2File', @(x) isstring(x) | isnumeric(x) | islogical(x));
    p.addRequired('iChan', @isnumeric);
    p.addRequired('tStart', @(x) isnumeric(x) | iscell(x));
    p.addRequired('tEnd', @(x) isnumeric(x) | iscell(x));
    p.parse(spike2File, iChan, tStart, tEnd)


    % Normalize tStart/tEnd: handle cell inputs by converting to numeric
    % In some call patterns, TSTART/TEND may be stored in cell arrays. For
    % slicing logic it is simpler to work with numeric arrays.
    if iscell(p.Results.tStart)
        tStart = cell2mat(tStart);
    end

    if iscell(p.Results.tEnd)
        tEnd = cell2mat(tEnd);
    end


    % Initialize default outputs
    numTraces = size(tStart,1);
    traces = num2cell(NaN(numTraces,1));
    times = num2cell(NaN(numTraces,1));
    sIntervSecs = NaN;

    % Open or assign the Spike2 file handle
    openedSpike2File = false;
    if isstring(p.Results.spike2File)
        % SPIKE2FILE is a path; open a new recording handle.
        session1401Recording = CEDS64Open(convertStringsToChars(p.Results.spike2File));
        openedSpike2File = true;
    else
        % SPIKE2FILE is assumed to be an existing CEDS64 handle.
        session1401Recording = p.Results.spike2File;
    end

    % Validate that the Spike2 file has been opened successfully.
    if session1401Recording == -1 || session1401Recording == 0

        warning( ...
            strcat( ...
                "(trialSliceRecordingBetween) Unable to open the spike2 recording file """, ...
                p.Results.spike2File, ...
                """. Returning default values." ...
                ) ...
            );

        return
    end

    % Get sampling interval and full waveform for the requested channel
    % sIntervTicks: number of ticks between consecutive sampes.
    % sIntervSecs:  seconds between consecutive samples.
    sIntervTicks = CEDS64ChanDiv(session1401Recording,iChan);
    sIntervSecs = CEDS64TicksToSecs(session1401Recording, sIntervTicks);
    
    % Read the entire waveform from channel iChan. We use this as the
    % source from which we extract per-window slices.
    endTick = CEDS64ChanMaxTime(session1401Recording,iChan);
    iN = round((endTick/sIntervTicks)+1);
    [~,elecWaveform,~] = CEDS64ReadWaveF(session1401Recording, iChan, iN, 0, endTick);
    elecWaveform = elecWaveform';
    
    % Convert requested [tStart, tEnd] windows to sample indices
    windowLowerIndex = ceil(tStart ./ sIntervSecs);
    windowUpperIndex = floor(tEnd ./ sIntervSecs);

    % Slice behavior depends on how many windows we are requested to 
    % extract
    numberSlices = numel(tStart);
    
    % Single-slice mode: TRACES and TIMES must be numeric, not cell arrays
    % When only a single segment is requested, the function returns numeric
    % vectors directly, instead of wrapping them in cells.
    if numberSlices == 1
        
        % Determine the slice mode:
        %   bit 0 (1): lower index is in bounds
        %   bit 1 (2): upper index is in bounds
        %   bit 2 (4): NaN/empty tStart/tEnd
        sliceMode = (windowLowerIndex >= 1) + ...
            2 * (windowUpperIndex <= length(elecWaveform)) + ...
            4*(isempty(tStart) | isempty(tEnd) | isnan(tStart) | isnan(tEnd));

        switch sliceMode

            % Case 0: both indices out of bounds
            % Zero-pad both sides
            case 0
                numMissingIndicesLeft = -1 * windowLowerIndex + 1;
                numMissingIndicesRight = windowUpperIndex - length(elecWaveform);
                traces = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex) zeros(1,numMissingIndicesRight)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
            % Case 1: upper in bounds, lower out of bounds
            % Zero-pad left
            case 1
                numMissingIndicesLeft = -1 * windowLowerIndex + 1;
                traces = [zeros(numMissingIndicesLeft,1) elecWaveform(1:windowUpperIndex)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);

            % Case 2: lower in bounds, upper out of bounds 
            % Zero-pad right
            case 2
                numMissingIndicesRight = windowUpperIndex - length(elecWaveform);
                traces = [elecWaveform(windowLowerIndex:length(elecWaveform)) zeros(1,numMissingIndicesRight)];
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
            % Case 3: both indices in bounds
            % standard slice
            case 3
                traces = elecWaveform(windowLowerIndex:windowUpperIndex);
                times = (windowLowerIndex*sIntervSecs):sIntervSecs:(windowUpperIndex*sIntervSecs);
                
            % Default: missing/NaN tStart or tEnd: return empty outputs
            otherwise
                traces = [];
                times = [];
        end
    
    % Multi-slice mode: traces and times are cell arrays
    % When more than one segment is requested, outputs are column cell
    % arrays; each cell holds one segment and its time vector.
    elseif numberSlices > 1
        
        % Instantiate the output cell arrays
        traces = cell(numberSlices,1);
        times = cell(numberSlices,1);
        
        % Iterate over each [tStart, tEnd] pair
        for i=1:numberSlices
            
            % Determine slice mode for this specific window.
            sliceMode = (windowLowerIndex(i) >= 1) + ...
                2 * (windowUpperIndex(i) <= length(elecWaveform)) + ...
                4*(isnan(tStart(i)) | isnan(tEnd(i)));

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

                % Default: missing/NaN for this pair: empty slice
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


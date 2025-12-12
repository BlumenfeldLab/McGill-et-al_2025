%{
Date Created: 6/3/2022
Description: This function detects contiguous low-voltage signal blocks on
a specified Spike2 channel and returns their start times, end times, and 
corresponding waveforms. Short pulses below a minimum duration are 
excluded. This helper is used to identify message-like segments on digital
or analog "signal out” channels.
%}

function [startTimes,endTimes,signalWaveforms] = findSignal(fHand,iChan,varargin)
    % FINDSIGNAL  Find contiguous low-voltage signal blocks on a Spike2 
    %   channel.
    %   
    %   [startTimes, endTimes, signalWaveforms] = FINDSIGNAL(fHand, iChan) 
    %   scans the waveform on channel iChan of the open CEDS64 file handle 
    %   fHand to identify contiguous blocks where the signal is low 
    %   (below a simple midpoint threshold). 
    % 
    %   The function returns:
    %       startTimes  - start times (seconds) of each detected block
    %       endTimes    - end times (seconds) of each detected block
    %       signalWaveforms   - cell array of waveform segments 
    %           corresponding to each
    %           block (raw values from CEDS64ReadWaveF)
    %
    %   [startTimes, endTimes, signalWaveforms] = FINDSIGNAL(fHand, iChan, tStartWindow, tEndWindow) 
    %   restricts the search to a time window from tStartWindow to 
    %   tEndWindow (seconds). Outside this window, the channel is ignored.
    %
    %   Detection proceeds by:
    %     1) Converting the requested time window to tick indices via CED
    %        channel division and tick-to-second conversion.
    %     2) Reading the waveform and thresholding it at the midpoint 
    %        between its minimum and maximum values to create a logical 
    %        vector indicating low-voltage samples.
    %     3) Using findConsecutive to locate contiguous runs of low-voltage
    %        samples.
    %     4) Merging nearby runs into longer "superblocks” when the gap 
    %        between them is below a fixed distance threshold.
    %     5) Discarding short pulses (blocks below a minimum duration) and
    %        returning the remaining blocks as candidate signal segments.
    %
    %   This function is typically used in conjunction with 
    %   sessionStartEndTime to identify message-like output on a signal 
    %   channel that encode session boundaries or other events.
    %
    %   See also findConsecutive, sessionStartEndTime, CEDS64ReadWaveF.

    % parse and validate input
    p = inputParser;

    p.addRequired('fHand',@CEDS64IsOpen);
    p.addRequired('iChan',@isnumeric);
    p.addOptional('tStart',0,@isnumeric);
    p.addOptional('tEnd',intmax,@isnumeric);
    p.parse(fHand,iChan,varargin{:});

    % Get important conversion factors for calculating time
    sIntervalTicks = CEDS64ChanDiv(fHand,iChan);
    sIntervalSecs = CEDS64TicksToSecs(fHand, sIntervalTicks);
    tickRate = sIntervalTicks/sIntervalSecs;

    % Extract waveform
    startTick = round(p.Results.tStart*tickRate);
    endTick = min(round(p.Results.tEnd*tickRate),intmax);
    iN = ((endTick-startTick)/sIntervalTicks)+1;
    [~,waveform,~] = CEDS64ReadWaveF(fHand, iChan, iN, startTick, endTick);
    
    % Turn the waveform into a binary array where 0 indicates a hi voltage
    % occured and 1 indicates a low voltage. note that hi is the default.
    waveform = waveform < (min(waveform) + max(waveform))/2;
    
    % Find the set of consecutive true values in the waveform
    [signalBlockStartIndices,signalBlockEndIndices,signalBlockLengths] = findConsecutive(waveform);
    
    % iterate over signal_block_indices and signal_block_lengths, chunking
    % signals together into superblocks based on their distance from
    % each other.
    maxChunkingDistance = 0.1/sIntervalSecs;
    
    chunkedSignalBlockStartIndices = zeros(length(signalBlockStartIndices),1);
    chunkedSignalBlockLengths = zeros(length(signalBlockLengths),1);
    chunkedSignalsIndex = 1;
    chunkedSignalBlockStartIndices(1) = signalBlockStartIndices(1);
    chunkedSignalBlockLengths(1) = signalBlockLengths(1);
    for index=2:length(signalBlockStartIndices)
        
        signalBlockDistance = signalBlockStartIndices(index) - signalBlockEndIndices(index-1) - 1;
        
        if  signalBlockDistance <= maxChunkingDistance
            
            chunkedSignalBlockLengths(chunkedSignalsIndex) = chunkedSignalBlockLengths(chunkedSignalsIndex) + signalBlockDistance + signalBlockLengths(index);
            
        else
            
            chunkedSignalsIndex = chunkedSignalsIndex + 1;
            chunkedSignalBlockStartIndices(chunkedSignalsIndex) = signalBlockStartIndices(index);
            chunkedSignalBlockLengths(chunkedSignalsIndex) = signalBlockLengths(index);
        end
    end
    
    % remove zero elements
    chunkedSignalBlockStartIndices = chunkedSignalBlockStartIndices(1:chunkedSignalsIndex);
    chunkedSignalBlockLengths = chunkedSignalBlockLengths(1:chunkedSignalsIndex);
    
    % created a list of signal block end indices. Used for extracting the
    % waveforms
    chunkedSignalBlockIndices = chunkedSignalBlockStartIndices + chunkedSignalBlockLengths - ones(length(chunkedSignalBlockStartIndices),1);
    
    % convert the block indices and lengths to times (in seconds)
    startTimes = (chunkedSignalBlockStartIndices-1) * sIntervalSecs;
    signalLengths = (chunkedSignalBlockLengths-1) * sIntervalSecs;
    endTimes = startTimes + signalLengths; 

    % Remove any pulses from the list of signal blocks
    pulseMaxLength = 0.2;
    nonPulseSignalBlocks = signalLengths>pulseMaxLength;
    startTimes = startTimes(nonPulseSignalBlocks);
    endTimes = endTimes(nonPulseSignalBlocks);
    chunkedSignalBlockStartIndices = chunkedSignalBlockStartIndices(nonPulseSignalBlocks);
    chunkedSignalBlockIndices = chunkedSignalBlockIndices(nonPulseSignalBlocks);
    
    % Convert to ticks
    chunkedSignalBlockStartIndices = (chunkedSignalBlockStartIndices-1) * sIntervalTicks;
    chunkedSignalBlockIndices = (chunkedSignalBlockIndices-1) * sIntervalTicks;
    
    % get a list of the signal waveforms
    signalWaveforms = cell(length(chunkedSignalBlockStartIndices),1);
    for index=1:length(chunkedSignalBlockStartIndices)
        i64From = chunkedSignalBlockStartIndices(index);
        i64To = chunkedSignalBlockIndices(index);
        iN = ((i64To - i64From) / sIntervalTicks) + 1;
        [~, signalWaveforms{index}, ~] = CEDS64ReadWaveF(fHand, iChan, iN, i64From, i64To);
    end
    
end


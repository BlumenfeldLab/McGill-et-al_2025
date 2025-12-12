%{
Date Created: 6/9/2022
Description:
Detect time intervals in a Spike2 recording where the signal deviates
strongly from baseline, using a z-score–based threshold and simple
temporal clustering. These intervals can reflect artifacts, recording
instabilities, or other atypical events that should be flagged or
excluded in downstream analyses.
%}

function [startTimes,endTimes] = findRecordingDeviations(fHand, iChan, varargin)
    % FINDRECORDINGDEVIATIONS  Find significant deviations in a Spike2 
    %   channel.
    %
    %   [startTimes, endTimes] = FINDRECORDINGDEVIATIONS(fHand, iChan) 
    %   searches the waveform on channel iChan of the open CEDS64 file 
    %   handle fHand for segments where the signal departs substantially 
    %   from its baseline distribution. Detected deviations are reported as
    %   start and end times (in seconds).
    %
    %   [startTimes, endTimes] = FINDRECORDINGDEVIATIONS(fHand, iChan, tStartWindow, tEndWindow)
    %   restricts the search to the interval [tStartWindow, tEndWindow] 
    %   (in units of seconds).
    %
    %   FINDRECORDINGDEVIATIONS(..., zScoreWindow) optionally specifies a
    %   larger window (in seconds) from which to estimate baseline mean and
    %   standard deviation for z-score computation. If zScoreWindow <= 0 or
    %   zScoreWindow <= (tEndWindow - tStartWindow), the baseline is 
    %   estimated only over the requested search window. If zScoreWindow is
    %   larger, the function reads a broader window centered on the search
    %   interval and extracts the relevant portion for deviation detection.
    %
    %   Name–value parameters:
    %       'SignificanceThreshold' (default 3.5)
    %           Minimum absolute z-score required for a sample to be
    %           considered significant. Effective threshold is 
    %           max(SignificanceThreshold, MinThresholdValue / sigma), 
    %           where sigma is the baseline standard deviation.
    %
    %       'MinThresholdValue' (default 4)
    %           Minimum absolute raw-signal deviation enforced through
    %           MinThresholdValue / sigma in z-score units. This guards 
    %           against overly small thresholds when sigma is tiny.
    %
    %       'Plot' (default false)
    %           When true, generates a diagnostic plot of the z-scored 
    %           waveform, highlighting significant samples and marking 
    %           detected deviation intervals.
    %
    %       'ClusterThreshold' (default 0.01)
    %           Maximum temporal gap (seconds) between adjacent significant
    %           samples to be grouped into the same cluster.
    %
    %       'MinClusterSize' (default 0.02)
    %           Minimum cluster duration (seconds). Clusters shorter than 
    %           this are discarded.
    %
    %       'MaxClusterSize' (default -1)
    %           Maximum cluster duration (seconds). If negative, no upper 
    %           bound is enforced. Otherwise, clusters longer than this are
    %           discarded.
    %
    %   Output:
    %       startTimes, endTimes  - column vectors of start and end times 
    %           (seconds) for each detected recording deviation within the 
    %           search interval
    %
    %   This function is useful for identifying important events or 
    %   excluding artifactual segments such as amplifier saturations
    %   in continuous LFP or analog recordings prior to spectral or ERP 
    %   analyses.
    %
    %   See also CEDS64ReadWaveF, CEDS64ChandDiv, CEDS64TicksToSecs.


    % parse varargin input
    p = inputParser;

    % FHAND must be an open CEDS64 file handle.
    p.addRequired('fHand',@CEDS64IsOpen);

    % Channel index to analyze.
    p.addRequired('iChan',@isnumeric);

    % Search time window [tStart, tEnd] in seconds.
    p.addOptional('tStart',0,@isnumeric);
    p.addOptional('tEnd',intmax,@isnumeric);

    % Optional baseline window for z-score estimation (seconds).
    p.addOptional('zScoreWindow',0,@isnumeric);

    % Z-score and amplitude thresholds.
    p.addParameter('SignificanceThreshold',3.5,@isnumeric);
    p.addParameter('MinThresholdValue',4,@isnumeric);

    % Plotting and clustering parameters. Useful for verification of
    % output results.
    p.addParameter('Plot',false,@islogical);
    p.addParameter('ClusterThreshold',0.01,@isnumeric);
    p.addParameter('MinClusterSize',0.02,@isnumeric);
    p.addParameter('MaxClusterSize',-1,@isnumeric);

    p.parse(fHand,iChan,varargin{:});

    % get conversion factors for calculating time
    sIntervTicks = CEDS64ChanDiv(fHand,iChan);
    sIntervSecs = CEDS64TicksToSecs(fHand, sIntervTicks);
    tickRate = sIntervTicks/sIntervSecs;
    
    % get waveforms
    % Case 1: zScoreWindow is not specified or is smaller than the search
    % interval. In this case estimate baseline from the same window used 
    % for detection.
    if p.Results.zScoreWindow <= 0 || p.Results.zScoreWindow <= p.Results.tEnd-p.Results.tStart
       targetStartTick = round(p.Results.tStart * tickRate);
       targetEndTick = min(round(p.Results.tEnd * tickRate),intmax);
       iN = ((targetEndTick-targetStartTick)/sIntervTicks)+1;
       [~,waveform,~] = CEDS64ReadWaveF(fHand, iChan, iN, targetStartTick, targetEndTick);
       
       targetStartIndex = 1;
       targetEndIndex = length(waveform);
       
    % Case 2: zScoreWindow is specified and larger than the search
    % interval. In this case read a larger window around the search 
    % interval for more stable baseline estimation, then extract the 
    % relevant portion for detection.
    else
        % Center a larger window around the midpoint of [tStart, tEnd],
        % respecting a lower bound of 0 and an upper bound of intmax.
        windowStartTime = max(0.5*(p.Results.tStart + p.Results.tEnd) - 0.5 * p.Results.zScoreWindow,0);
        windowEndTime = min(0.5*(p.Results.tStart + p.Results.tEnd) + 0.5 * p.Results.zScoreWindow,intmax);
        windowStartTick = round(windowStartTime * tickRate);
        windowEndTick = min(round(windowEndTime * tickRate),intmax);
        iN = ((windowEndTick-windowStartTick)/sIntervTicks)+1;
        [~,waveform,~] = CEDS64ReadWaveF(fHand, iChan, iN, windowStartTick, windowEndTick);
        
        % Map [tStart, tEnd] into indices within the broader waveform.
        targetStartIndex = max(round(abs(p.Results.tStart - windowStartTime)/sIntervSecs)+1,1);
        targetEndIndex = min(targetStartIndex + round((p.Results.tEnd-p.Results.tStart)/sIntervSecs),length(waveform));
        
    end
    
    % Identify samples that exceed z-score / amplitude thresholds
    % Compute baseline mean and standard deviation.
    mu = median(waveform);
    sigma = std(waveform);

    % Compute z-scores and restrict to the detection window.
    zScoreWaveform = (waveform - mu)/sigma;
    zScoreWaveform = zScoreWaveform(targetStartIndex:targetEndIndex);

    % Calculate the indices (within zScoreWaveform) of samples exceeding 
    % the threshold.
    sigSamples = find(abs(zScoreWaveform) > max(p.Results.SignificanceThreshold,p.Results.MinThresholdValue/sigma));
    
    % Cluster significant samples in time
    % Cluster contiguous or near-contiguous significant samples into
    % deviation events, based on a maximum allowed gap.
    sigSampleClusters = ones(length(sigSamples),1);
    clusterNum = 1;
    clusterThreshIndexCount = p.Results.ClusterThreshold / sIntervSecs;
    for i=2:length(sigSamples)
        % If the gap between consecutive significant samples is small
        % enough, treat them as part of the same cluster.
         if sigSamples(i)-sigSamples(i-1) <= clusterThreshIndexCount
             sigSampleClusters(i) = clusterNum;
         else
             clusterNum = clusterNum + 1;
             sigSampleClusters(i) = clusterNum;
         end
    end
    
    % Identify the first and last index of each cluster.
    firstIndices = sigSamples((sigSampleClusters - circshift(sigSampleClusters,1))~=0);
    lastIndices = sigSamples((sigSampleClusters - circshift(sigSampleClusters,-1))~=0);
    
    % Apply cluster size constraints
    % Remove clusters that do not meet the minimum size criterion.
    if p.Results.MinClusterSize >= 0
        validClusters = (lastIndices-firstIndices)*sIntervSecs>=p.Results.MinClusterSize;
        firstIndices = firstIndices(validClusters);
        lastIndices = lastIndices(validClusters);
    end
        
    % Remove clusters that exceed the maximum size criterion (if enabled).
    if p.Results.MaxClusterSize >= 0
        validClusters = (lastIndices-firstIndices)*sIntervSecs<=p.Results.MaxClusterSize;
        firstIndices = firstIndices(validClusters);
        lastIndices = lastIndices(validClusters);
    end
    
    % Convert cluster indices to times (seconds)
    startTimes = (firstIndices-1)*sIntervSecs + p.Results.tStart;
    endTimes = (lastIndices)*sIntervSecs + p.Results.tStart;
    
    % Optional diagnostic plot
    if p.Results.Plot
        figure
        hold on

        % Time axis for the z-scored waveform within the detection window.
        times = (0:length(zScoreWaveform)-1)*sIntervSecs + p.Results.tStart;
        
        % Plot z-scored waveform and highlight significant samples.
        plot(times, zScoreWaveform);   
        scatter(times(sigSamples),zScoreWaveform(sigSamples),5,'Yellow');
        
        % Mark cluster start (green) and end (red) times.
        for i=1:length(startTimes)
           line([startTimes(i) startTimes(i)],[-30 30],'Color','Green');
        end
        
        for i=1:length(endTimes)
           line([endTimes(i) endTimes(i)],[-30 30],'Color','Red');
        end
        
        % Set reasonable y- and x-limits for inspection.
        ylim([floor(min(zScoreWaveform)*1.1),ceil(max(zScoreWaveform)*1.1)])
        xlim([min(times),min(times)+60])
        
    end
    
    
end


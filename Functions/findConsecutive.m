%{
Date Created: 6/9/2022
Description: This function identify contiguous runs of nonzero (or true) 
values in a 1-D vector. The function returns the start indices, 
end indices, and lengths of each consecutive block of active samples. The
primary purpose of this code is for use in signal detection logic.
%}

function [firstIndices,lastIndices,blockLengths] = findConsecutive(X)
    % FINDCONSECUTIVE  Find contiguous blocks of nonzero/true values in a 
    %   vector.
    %   
    %   [firstIndices, lastIndices, blockLengths] = FINDCONSECUTIVE(X) 
    %   scans the input vector X (typically logical or numeric) and 
    %   identifies contiguous runs of nonzero (or logical true) values. For
    %   each run, it returns the index of the first element (firstIndices),
    %   the index of the last element (lastIndices), and the number of 
    %   elements in that run (blockLengths).
    %
    %   X is assumed to be a 1-D vector, and any nonzero value is 
    %   interpreted as "active". The function assumes that each active 
    %   block is terminated by at least one zero/false sample before the 
    %   final element of X (or that X is appropriately padded with a 
    %   trailing zero/false).
    %
    %   This helper is used by event-detection routines (e.g., findSignal) 
    %   to group individual above-threshold samples into discrete events.
    %
    %   See also findSignal.

    % Preallocate output arrays with a conservative upper bound on the
    % number of possible blocks (no more than about half the number of
    % samples if blocks are separated by at least one inactive sample).
    firstIndices = zeros(round(size(X,1)/2),1);
    lastIndices = zeros(round(size(X,1)/2),1);
    blockLengths = zeros(round(size(X,1)/2),1);
    
    % State variables used while scanning through X.
    index = 1;
    blockStartIndexFound = false;
    currentBlockLength = 0;
    blockArrayIndex = 0;

    % Iterate through the vector and identify contiguous nonzero blocks.
    while index < length(X)

        if ~blockStartIndexFound
            
             % Not currently in a block: check if a new block starts here.
            if X(index)
                blockStartIndexFound = true;
                blockArrayIndex = blockArrayIndex + 1;
                firstIndices(blockArrayIndex) = index;
                currentBlockLength = currentBlockLength + 1;
            end
            
        else
            
            % Currently inside a block: extend or terminate it.
            if X(index)

                % Block continues.
                currentBlockLength = currentBlockLength + 1;

            else
                % Block ends at the previous index.
                blockLengths(blockArrayIndex) = currentBlockLength;
                lastIndices(blockArrayIndex) = index-1;
                currentBlockLength = 0;
                blockStartIndexFound = false;
            end
        end

        % increment to the next element.
        index = index + 1;
    end
    
    % Trim outputs to include only the detected blocks.
    firstIndices = firstIndices(1:blockArrayIndex);
    lastIndices = lastIndices(1:blockArrayIndex);
    blockLengths = blockLengths(1:blockArrayIndex);
    
end


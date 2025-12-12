%{
Date Created: 2/22/2025
Description:
    Loads LFP peristimulus traces for a given animal x channel x condition
    from the experimentalGroupTrialTable files referenced in a row (or
    rows) of the behavioral table.

    For each input row, this function:
        - Loads the referenced `experimentalGroupTrialTable` from disk.
        - Extracts the peristimulus LFP traces (`peristimulusTrace`) for
        all trials.
        - Rejects trials with extreme voltage excursions (|amplitude| > 
        500).
        - Optionally removes a fixed stimulus-artifact window and linearly
          interpolates across the gap.
        - Concatenates the resulting trial matrix into the output.

    Notes:
        - The number of time points is assumed to be NTIME = 3001
        (−1.5 s to +1.5 s at 1 kHz).
        - The low-pass filter `lpFilt` is defined but not applied in the
        current implementation; it is retained for compatibility with
        the original analysis code.
        - As in the original code, each file’s data are duplicated along
        the trial dimension via:
            all_matrix = cat(2, data_matrix_interp, data_matrix_interp);
            This behavior is preserved verbatim to match prior analyses.
%}


function all_matrix = loadAnimalChannelTable(row,data_dir,inspect_interp)
    % LOADANIMALCHANNELTABLE  Load and preprocess LFP traces for one row.
    %
    %   all_matrix = LOADANIMALCHANNELTABLE(row, data_dir, inspect_interp)
    %   loads peristimulus LFP data from the trial-table file(s) referenced
    %   in ROW (a subset of the behavioral table), returning a matrix of
    %   size NTIME x NTRIALS.
    %
    %   Required Inputs:
    %       row
    %           One or more rows from the behavioral metadata table
    %           (e.g., experimentalGroupTable). Each row must contain an
    %           `experimentalGroupTrialTable` field with a relative path or
    %           filename pointing to the corresponding trial-table .mat 
    %           file.
    %
    %       data_dir
    %           Root directory in which the trial-table .mat files are
    %           stored. The file path is constructed using:
    %               fullfile(data_dir, <cleaned filename from row>).
    %
    %       inspect_interp
    %           Logical flag indicating whether to visually inspect the
    %           interpolation performed by removeSoundAndInterp (if used).
    %           - Currently only used inside removeSoundAndInterp when
    %           removal/interpolation is enabled.
    %
    %   Output:
    %       all_matrix
    %           NTIME x NTRIALS matrix of peristimulus LFP traces. NTIME is
    %           fixed at 3001 samples. NTRIALS is the total number of
    %           retained trials (note that, by design, each file’s data are
    %           duplicated along the second dimension).
    %
    %   See also: removeSoundAndInterp.
    
    % User options and constants
    verbose = false; % Print number of retained trials
    remove_stim = false; % If true, remove stimulus artifact and interpolate

    % Low-pass filter (defined but not applied in the current code;
    % retained from original implementation).
    lpFilt = designfilt('lowpassfir','PassbandFrequency',0.5,'StopbandFrequency',14,'PassbandRipple',0.5,...
        'StopbandAttenuation',65,'DesignMethod','kaiserwin','SampleRate',1000) ;
    
    % Expected number of time points per trial (−1.5 to +1.5 s at 1 kHz)
    NTIME = 3001 ;
    
    % Helper to strip leading directory components
    removeDr = @(x) extractAfter(x,'Only\') ;
    
    % Initialize output
    all_matrix = [];

    % Main loop over input rows (each row points to a trial-table file)
    for itable = 1:height(row)

        % Load experimentalGroupTrialTable for this row
        data_table = load(fullfile(data_dir,removeDr(row.experimentalGroupTrialTable{itable})));
        data_table = data_table.experimentalGroupTrialTable;
    
        nrow = height(data_table) ;

        % Preallocate per-file data matrix [NTIME x NTRIALS]
        data_matrix = nan(NTIME,nrow);
    
        row_kept = 1 ;

        % Extract peristimulus traces and apply amplitude-based rejection
        for ir = 1:nrow
            curr_row = data_table.peristimulusTrace(ir,:);
    
            % Reject trials with extreme amplitudes (|voltage| > 500)
            if any(abs(curr_row) > 500)
                continue
            end
    
            data_matrix(:,row_kept) = curr_row ;
            row_kept = row_kept + 1 ;
    
        end
        
        % Optional: remove stimulus artifact and interpolate across gap
        if remove_stim
            data_matrix_interp = removeSoundAndInterp(data_matrix,inspect_interp) ;
        else
            data_matrix_interp = data_matrix ;
        end
    
        if verbose
            fprintf('keep %d out of %d trials \n',row_kept-1,nrow)
        end
        
        % Concatenate into output (original behavior preserved)
        all_matrix = cat(2,data_matrix_interp,data_matrix_interp);
    end
end
    
function interpolated_data = removeSoundAndInterp(in_data,inspect)
    % Helper function: removeSoundAndInterp
    % Removes a fixed stimulus-artifact window from each trial and linearly
    % interpolates across the removed region.
    % 
    % The artifact window is defined by:
    %     removal_period = 1501:1600;
    % 
    % If `inspect` is true, the function plots each trial before/after
    % interpolation and pauses for user inspection via keyboard.

    [ntime,ntr] = size(in_data);
    
    % Define the window to be removed and interpolated over
    removal_period = 1501:1600;
    
    % Keep a copy of the original data for inspection plots
    temp_data = in_data ;
    
    % Mark the removal region as NaN
    in_data(removal_period, :) = NaN;
    
    % Preallocate output
    interpolated_data = nan(size(in_data));
    
    % Interpolate each trial independently
    for itr = 1:ntr
    
        % Find indices of non-NaN values
        x = 1:ntime;
        v = in_data(:, itr);
    
        % If the entire trial is NaN, leave it as-is
        if all(isnan(v))
            interpolated_data(:, itr) = v ;
            continue
        end
        
        % Identify valid (non-NaN) samples
        x_non_nan = x(~isnan(v));
        v_non_nan = v(~isnan(v));
    
        % Linear interpolation across the NaN region
        interpolated_data(:, itr) = interp1(x_non_nan, v_non_nan, x, 'linear');
    
        % Optional visual inspection of interpolation
        if inspect
            figure;
            time_vec = linspace(-1.5,1.5,ntime) ;
            hold on
            plot(time_vec,temp_data(:,itr),'b')
            plot(time_vec(removal_period),interpolated_data(removal_period, itr),'r','LineWidth',4)
            keyboard
            close
        end
    end


end
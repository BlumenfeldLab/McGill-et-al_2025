%{
Date Created: 2/29/2024
Description: Applies a user-specified function to a trial table, either 
once per trial or once per session, and organize the outputs back into a 
trial-aligned table.

This utility provides a flexible wrapper for applying functions to
behavioral trial data stored in a trialTable. It supports:
  - calling the function once per trial or once per session
  - passing inputs that are either trial-wise (one row per trial) or
    session-wise (one value per session)
  - handling outputs that are either trial-wise or session-wise
  - optional parallelization of function calls
  - joining the resulting output columns back onto the original trialTable
%}

function [tableOut, newColumnNames]  = trialTableFun(func, trialTable, varargin)
    % TRIALTABLEFUN  Applies a function to trials/sessions in a trial 
    %   table.
    %
    %   tableOut = TRIALTABLEFUN(func, trialTable, ...) applies the 
    %   function handle func to the contents of trialTable and returns an
    %   output table tableOut containing the function outputs. The mapping 
    %   between rows of trialTable and calls to func is controlled via 
    %   several options.
    %
    %   [tableOut, newColumnNames] = TRIALTABLEFUN(...) also returns
    %   newColumnNames, a cell array listing which output variables are new
    %   (i.e., present in tableOut but not in trialTable) when columns are
    %   joined back onto the original trialTable.
    %
    %   Required Inputs:
    %       func
    %           - Function handle to be applied. It will be called as:
    %           [out1, out2, ...] = FUNC(in1, in2, ...)
    %       trialTable
    %           - A table validated by ISTRIALTABLE, where each row
    %           corresponds to one behavioral trial.
    %
    %   Name–Value Pair Arguments:
    %       'CallOncePerSession' (logical, default = false)
    %           - If false: func is called once per trial (one call per 
    %           row).
    %           - If true:  func is called once per session, where sessions
    %           are defined by unique (animalName, sessionDate, 
    %           sessionNumber).
    %
    %       'InputVariableNames' (string/char/cellstr or empty)
    %           - Names of the columns in trialTable to use as inputs to
    %           func. Each column corresponds to one positional argument to
    %           func.
    %
    %       'InputVariablesRowsCorrespondToTrials' (logical array or empty)
    %           - For CallOncePerSession = true, specifies, for each input
    %           variable, whether its rows correspond to individual trials.
    %           - If false: the input is treated as session-wise; one value
    %           (from the first trial in the session) is passed per
    %           session.
    %           - If true: the input is trial-wise; for each session, all 
    %           rows (trials) belonging to that session are passed together 
    %           (e.g., as a vector or matrix).
    %
    %       'OutputVariableNames' (string/char/cellstr or empty)
    %           - Names of the columns to use in TABLEOUT for the outputs
    %           of FUNC. The number of names should match the number of 
    %           outputs.
    %
    %       'OutputVariablesRowsCorrespondToTrials' (logical array or 
    %       empty)
    %           - For CallOncePerSession = true, specifies, for each output
    %           variable, whether its rows correspond to trials:
    %           - If false: the session-level output is replicated for each 
    %           trial in the session.
    %           - If true: the output is expected to contain one row per 
    %           trial in the session; these rows are distributed across the
    %           corresponding trials in tableOut.
    %
    %       'Parallelize' (logical, default = false)
    %           If true, calls to func across sessions/trials are executed
    %           using a parfor loop. If false, a standard for loop is used.
    %
    %       'Join' (logical, default = true)
    %           If true, tableOut is horizontally concatenated with 
    %           trialTable. Existing column names are overwritten by the 
    %           new values if there is a name collision. If false, tableOut
    %           contains only the outputs of func.
    %
    %   Outputs:
    %       tableOut 
    %           - Output table containing FUNC outputs, optionally joined
    %           with the original trialTable.
    %       newColumnNames 
    %           - Cell array of variable names in TABLEOUT that were not 
    %           present in TRIALTABLE prior to joining.
    %
    %   Notes:
    %       - Sessions are identified by the combination of animalName,
    %       sessionDate, and sessionNumber.
    %       - This function does not alter the contents of TRIALTABLE; it 
    %       only constructs and returns a new table based on FUNC outputs.
    %
    %   See also: isTrialTable, unique, sessionTableFun, parfor.

    % Parse and validate inputs
    p = inputParser;
    p.addRequired('func', @(f) isa(f,'function_handle'));
    p.addRequired('trialTable', @isTrialTable);
    p.addParameter('CallOncePerSession',false, @islogical);
    p.addParameter('InputVariableNames','',@(x) isempty(x) | isstring(x) | ischar(x) | iscellstr(x));
    p.addParameter('InputVariablesRowsCorrespondToTrials',logical.empty,@islogical);
    p.addParameter('OutputVariableNames',@(x) isempty(x) | isstring(x) | ischar(x) | iscellstr(x));
    p.addParameter('OutputVariablesRowsCorrespondToTrials',logical.empty,@islogical);
    p.addParameter('Parallelize',false,@islogical);
    p.addParameter('Join',true, @islogical)
    p.parse(func,trialTable, varargin{:});


    % Build the input argument matrix for func (funcInArgs)
    % Each row of funcInArgs corresponds to a single call to func.
    % Each column corresponds to a different input argument.

    % Number of input arguments to func
    numFuncArgs = numel(p.Results.InputVariableNames);

    % Determine how many times func will be called
    if p.Results.CallOncePerSession
        
        % Identify unique sessions by (animalName, sessionDate, 
        % sessionNumber)
        [~,firstInstanceEachSession,~] = ...
            unique(trialTable(:,["animalName","sessionDate","sessionNumber"]),"Rows");
        firstInstanceEachSession = sort(firstInstanceEachSession);
        numFuncCalls = numel(firstInstanceEachSession);

    else
        % One function call per trial
        numFuncCalls = size(trialTable,1);
    end
    
    % Preallocate funcInArgs
    funcInArgs = cell(numFuncCalls,numFuncArgs);
    
    % Populate funcInArgs based on calling mode and input-variable behavior
    if ~p.Results.CallOncePerSession
        
        % Mode 1: Call func once per trial
        % Simply pass each row of trialTable for the specified input
        % variables as separate calls.
        funcInArgs = table2cell(trialTable(:,p.Results.InputVariableNames));

    elseif isempty(p.Results.InputVariablesRowsCorrespondToTrials) | ~any(p.Results.InputVariablesRowsCorrespondToTrials)
        
        % Mode 2: Call func once per session, all inputs are session-wise.
        % Each input variable contributes a single value per session, taken
        % from the first trial of that session.
        if iscell(p.Results.InputVariableNames)
            for i=1:numFuncArgs
                funcInArgs(:,i) = table2cell(trialTable(firstInstanceEachSession,p.Results.InputVariableNames{i}));
            end
        else
            for i=1:numFuncArgs
                funcInArgs(:,i) = table2cell(trialTable(firstInstanceEachSession,p.Results.InputVariableNames(i)));
            end
        end

    else

        % Mode 3: Call FUNC once per session with a mix of trial-wise and
        % session-wise inputs.
        %
        % For each input variable:
        %   - if corresponding InputVariablesRowsCorrespondToTrials(i) is
        %     true, pass all rows (trials) for that session as an array.
        %   - otherwise, pass a single session-wise value, taken from the
        %     first trial of that session.
        if iscell(p.Results.InputVariableNames)
            for i=1:numFuncArgs
                if p.Results.InputVariablesRowsCorrespondToTrials(i)
                    % Trial-wise input: pass all rows for each session
                    for j=1:numFuncCalls
                        if j==numFuncCalls
                            funcInArgs(j,i) = {trialTable{firstInstanceEachSession(j):end,p.Results.InputVariableNames{i}}};
                        else
                            funcInArgs(j,i) = {trialTable{firstInstanceEachSession(j):firstInstanceEachSession(j+1)-1,p.Results.InputVariableNames{i}}};
                        end
                    end
                else
                    % Session-wise input: one value from first trial
                    funcInArgs(:,i) = table2cell(trialTable(firstInstanceEachSession,p.Results.InputVariableNames{i}));
                end
            end
        else
            for i=1:numFuncArgs
                if p.Results.InputVariablesRowsCorrespondToTrials(i)
                    % Trial-wise input for non-cell InputVariableNames
                    for j=1:numFuncCalls
                        if j==numFuncCalls
                            funcInArgs(j,i) = {trialTable{firstInstanceEachSession(j):end,p.Results.InputVariableNames(i)}};
                        else
                            funcInArgs(j,i) = {trialTable{firstInstanceEachSession(j):firstInstanceEachSession(j+1)-1,p.Results.InputVariableNames(i)}};
                        end
                    end
                else
                    % Session-wise input
                    funcInArgs(:,i) = table2cell(trialTable(firstInstanceEachSession,p.Results.InputVariableNames(i)));
                end
            end
        end

    end


    % Call func for each row of funcInArgs (trial-wise or session-wise)
    % Determine number of outputs produced by func
    if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames)
        numFuncOut = max(numel(p.Results.OutputVariableNames),1);
    else
        numFuncOut = 1;
    end

    % Preallocate output cell array
    funcOut = cell(numFuncCalls,numFuncOut);

    % Call func in serial or parallel
    if ~p.Results.Parallelize
        % Serial evaluation
        for i = 1:numFuncCalls
            temp = cell(1,numFuncOut);
            [temp{1:numFuncOut}] = func(funcInArgs{i,:});
            funcOut(i,:) = temp;
        end
    else
        % Parallel evaluation (session/trial calls distributed via parfor)
        parfor i = 1:numFuncCalls
                temp = cell(1,numFuncOut);
                [temp{1:numFuncOut}] = func(funcInArgs{i,:});
                funcOut(i,:) = temp;
        end
    end


    % Convert FUNC outputs into a table aligned to TRIALTABLE
    if ~p.Results.CallOncePerSession
        % Case A: FUNC was called once per trial
        % funcOut already has one row per trial, so we can convert 
        % directly.
        if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames) 
            tableOut = cell2table(funcOut, ...
                "VariableNames",...
                p.Results.OutputVariableNames);
        else
            tableOut = cell2table(funcOut, ...
                "VariableNames",...
                string(p.Results.OutputVariableNames));
        end

    elseif isempty(p.Results.OutputVariablesRowsCorrespondToTrials) | ~any(p.Results.OutputVariablesRowsCorrespondToTrials)
        % Case B: Call once per session, outputs are session-wise.
        % Expand each session-level output to cover all its trials by
        % replicating the corresponding row in funcOut.
        tableOut = cell([size(trialTable,1) numFuncOut]);

        for i=1:numFuncCalls
            trialsThisSession = ...
                trialTable.animalName(firstInstanceEachSession(i)) == trialTable.animalName ...
                & trialTable.sessionDate(firstInstanceEachSession(i)) == trialTable.sessionDate ...
                & trialTable.sessionNumber(firstInstanceEachSession(i)) == trialTable.sessionNumber;
            tableOut(trialsThisSession,:) = repmat(funcOut(i,:),[sum(trialsThisSession),1]);
        end

        if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames) 
            tableOut = cell2table(tableOut, ...
                "VariableNames",...
                p.Results.OutputVariableNames);
        else
            tableOut = cell2table(tableOut, ...
                "VariableNames",...
                string(p.Results.OutputVariableNames));
        end

    else
        % Case C: Call once per session, with mixture of trial-wise and
        % session-wise outputs per variable.
        %
        % For each output column:
        %   - if OutputVariablesRowsCorrespondToTrials(j) is false:
        %         replicate one session-level row for each trial in session.
        %   - if true:
        %         distribute rows of the session output across the trials.
        tableOut = cell([size(trialTable,1) numFuncOut]);
        
        for i=1:numFuncCalls
            trialsThisSession = ...
                trialTable.animalName(firstInstanceEachSession(i)) == trialTable.animalName ...
                & trialTable.sessionDate(firstInstanceEachSession(i)) == trialTable.sessionDate ...
                & trialTable.sessionNumber(firstInstanceEachSession(i)) == trialTable.sessionNumber;

            for j = 1:numFuncOut
                % Trial-wise output: one row per trial in this session.
                if p.Results.OutputVariablesRowsCorrespondToTrials(j)
                    numRows = size(funcOut{i,j},1);
                    numCols = size(funcOut{i,j},2);
                    if sum(trialsThisSession) == size(funcOut{i,j},1) & ~iscell(funcOut{i,j})
                        tableOut(trialsThisSession,j) = mat2cell(funcOut{i,j}, ones(numRows,1),numCols);
                    elseif sum(trialsThisSession) == size(funcOut{i,j},1)
                        tableOut(trialsThisSession,j) = funcOut{i,j};
                    elseif isempty(funcOut{i,j})
                        tableOut{trialsThisSession,j} = funcOut{i,j};
                    else
                        warning("(trialTableFun) Unexpected case encountered.");
                    end

                else
                    % Session-wise output: replicate per trial
                    tableOut(trialsThisSession,:) = repmat(funcOut(i,:),[sum(trialsThisSession),1]);
                end

            end

        end

        if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames) 
            tableOut = cell2table(tableOut, ...
                "VariableNames",...
                p.Results.OutputVariableNames);
        else
            tableOut = cell2table(tableOut, ...
                "VariableNames",...
                string(p.Results.OutputVariableNames));
        end

    end

    % Optionally join FUNC outputs back onto the original trialTable
    if p.Results.Join

        % Identify new vs existing columns by name
        isNewColumn = ~ismember(...
            tableOut.Properties.VariableNames, ...
            trialTable.Properties.VariableNames);
        newColumnNames = tableOut.Properties.VariableNames(isNewColumn);
        oldColumnNames = tableOut.Properties.VariableNames(~isNewColumn);
        
        % If all output columns are new, just append them.
        % Otherwise, allow the new values to overwrite existing columns
        % with the same names by removing those columns from trialTable
        % first.
        if all(isNewColumn)
            tableOut = [trialTable tableOut];
        else
            tableOut = [removevars(trialTable,oldColumnNames) tableOut];
        end

    else
        newColumnNames = tableOut.Properties.VariableNames;
    end

end
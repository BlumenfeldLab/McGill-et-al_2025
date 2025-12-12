%{
Date Created: 2/29/2024
Description: Applies a function handle row-wise to a session table and 
optionally merge the results back into the original table. This serves as 
a way to perform effiencit manipulations of session-level data and 
metadata across large numbers of sessions.
%}

function [tableOut, newColumnNames] = sessionTableFun(func, sessionTable, varargin)
    % SESSIONTABLEFUN  Apply a function row-wise to a session table.
    %
    %   tableOut = SESSIONTABLEFUN(func, sessionTable) applies the function 
    %   handle func to each row of the session table sessionTable. The 
    %   input variables to func are taken from the columns specified by the 
    %   'InputVariableNames' parameter, and the outputs from func are 
    %   collected into a new table tableOut.
    %
    %   [tableOut, newColumnNames] = SESSIONTABLEFUN(func, sessionTable, ...)
    %   also returns newColumnNames, a list of variable names corresponding
    %   to columns newly introduced into tableOut when Join is enabled.
    %
    %   SESSIONTABLEFUN(func, sessionTable, 'InputVariableNames', names) 
    %   specifies which columns of sessionTable are passed as inputs to 
    %   func. names may be a string, character vector, or cell array of 
    %   variable names.
    %
    %   SESSIONTABLEFUN(func, sessionTable, 'OutputVariableNames', names) 
    %   specifies the variable names to assign to the outputs of func. 
    %   names may be a string, character vector, or cell array; if omitted,
    %   a single output column is assumed.
    %
    %   SESSIONTABLEFUN(..., 'Join', tf) controls whether the output of 
    %   func is joined back to the original session table. When tf is true
    %   (default), any new columns produced by func are appended, and any 
    %   existing columns with the same names are overwritten. When tf is 
    %   false, only the table constructed from FUNC outputs is returned.
    %
    %   This utility provides a consistent way to run per-session 
    %   computations (e.g., computing file handles, summary metrics, or 
    %   timing information) while preserving the session table schema 
    %   used throughout the analysis code.
    %
    %   See also sessionTable, isSessionTable.

    % Parse and validate inputs.
    % - func must be a function handle.
    % - sessionTable must pass isSessionTable.
    % - InputVariableNames and OutputVariableNames control which columns are
    %   read and written, respectively.
    p = inputParser;
    p.addRequired('func', @(f) isa(f,'function_handle'));
    p.addRequired('sessionTable', @isSessionTable);
    p.addParameter('InputVariableNames','',@(x) isempty(x) | isstring(x) | ischar(x) | iscellstr(x));
    p.addParameter('OutputVariableNames',@(x) isempty(x) | isstring(x) | ischar(x) | iscellstr(x));
    p.addParameter('Join',true, @islogical)
    p.parse(func,sessionTable, varargin{:});

    % Calculate the number of times FUNC will be called (once per row).
    numFuncCalls = size(sessionTable,1);
    
    % Create the funcInArgs array, which carries the inputs to FUNC. Each
    % row corresponds to a function call, and each column to an input
    % variable drawn from the specified columns of the session table.
    funcInArgs = table2cell(sessionTable(:,p.Results.InputVariableNames));
    
    % Instantiate the output cell array. We collect the outputs from FUNC
    % into FUNCOUT as a cell array with one row per call and one column per
    % expected output variable.
    if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames)
        numFuncOut = max(numel(p.Results.OutputVariableNames),1);
    else
        numFuncOut = 1;
    end
    funcOut = cell(numFuncCalls,numFuncOut);

    % Call func in a simple for-loop, one row at a time.
    for i = 1:numFuncCalls
        [funcOut{i,:}] = func(funcInArgs{i,:});
    end

    % Create the output table from funcOut, assigning variable names based
    % on OutputVariableNames (or casting a single name to string).
    if isstring(p.Results.OutputVariableNames) | iscell(p.Results.OutputVariableNames) 
        tableOut = cell2table(funcOut, ...
            "VariableNames",...
            p.Results.OutputVariableNames);
    else
        tableOut = cell2table(funcOut, ...
            "VariableNames",...
            string(p.Results.OutputVariableNames));
    end

    % Optionally join tableOut and sessionTable, if Join is set to true.
    if p.Results.Join

        % Identify which, if any, of the columns in tableOut are new, and
        % obtain lists of new and existing column names.
        isNewColumn = ~ismember(...
            tableOut.Properties.VariableNames, ...
            sessionTable.Properties.VariableNames);
        newColumnNames = tableOut.Properties.VariableNames(isNewColumn);
        oldColumnNames = tableOut.Properties.VariableNames(~isNewColumn);
        
        % If all columns are new, simply concatenate the tables 
        % horizontally. Otherwise, drop any overlapping columns from S
        % sessionTable so that the columns produced here overwrite them.
        if all(isNewColumn)
            tableOut = [sessionTable tableOut];
        else
            tableOut = [removevars(sessionTable,oldColumnNames) tableOut];
        end

    else
        % When not joining back to the input table, consider all output
        % columns as "new" from the caller's perspective.
        newColumnNames = tableOut.Properties.VariableNames;
    end

end
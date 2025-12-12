%{
Date Created: 11/15/2021
Description: This funcntion loads a tab-delimited behavioral results text 
file into a MATLAB table with appropriately cast variable types. This 
helper furhter infers the animal name, session date, and session number 
from the filename and appends them as columns.
%}


function table = openResults(filename)
    % OPENRESULTS  Load and type-cast a behavioral results file into a 
    %   table.
    %
    %   table = OPENRESULTS(filename) reads a tab-delimited text file 
    %   specified by filename, interprets the first row as variable names, 
    %   and converts the remaining rows into a table with columns cast to 
    %   numeric, logical, or string types when possible.
    %
    %   Columns whose cells contain only the string 'N/A' (case-sensitive) 
    %   are treated as missing and converted to NaN before casting to 
    %   numeric or logical. Column type is inferred heuristically from the 
    %   first non-'N/A' cell: numeric patterns are cast to double, 
    %   'true'/'false' to logical, and all other content to string.
    %
    %   In addition, OPENRESULTS parses the filename to extract:
    %      - Animal_Name   (string)
    %      - Session_Date  (datetime, MM-dd-yy)
    %      - Session_Number (double; default 1 if not present)
    %   These are added as new columns to the output table.
    %
    %   This function is used by getTrialTable to construct trial-level
    %   metadata from raw behavioral log files.
    %
    %   See also getTrialTable, cell2table, datetime.
    
    % Nested helper to infer and apply an appropriate type cast for a
    % single column of cell data.
    function castedColumn = smartCast(column)
        
        % Identify the casting type by scanning for the first non-'N/A'
        % entry and inspecting its content.
        type = 'default';
        for i=2:size(column)
           
            % Skip placeholder entries marked as "N/A".
            if ~strcmp(column{i},"N/A")

                % Logical: matches 'true'/'false' (case-insensitive).
                if regexp(column{i},"(^[tT]rue$)|(^[fF]alse$)",'once')
                    type = 'bool';

                % Numeric: signed integer or floating-point with optional
                % exponent (e.g., -1, 3.14, 1e-3).
                elseif regexp(column{i},"^[-+]?\d+($|\.\d+)($|e[-+]?\d+)",'once')
                    type = 'num';

                % Otherwise treat as string.
                else
                    type = 'str';
                end
                    
                break;
            end
            
        end
        
        % Initialize output as a copy of the original column.
        castedColumn = column;
        
        if ~strcmp(type,'str')
            
            % Replace all instances of the string 'N/A' with NaNs to mark
            % missing values before numeric/logical casting.
            nan_locs = strcmp(castedColumn,'N/A');
            castedColumn(nan_locs) = {nan};
            
            if strcmp(type,'num')
            
                % Cast remaining non-NaN cells to double.
                for i=2:size(castedColumn)
                    if ~isnan(castedColumn{i})
                        castedColumn{i} = str2double(castedColumn{i});
                    end
                end
                
            elseif strcmp(type,'bool')
                
                % cast the remaining cells to numbers
                for i=2:size(castedColumn)
                    if ~isnan(castedColumn{i})
                        castedColumn{i} = strcmpi(castedColumn{i},'true') == 1;
                    end
                end
                
            end
          
        else

            % For string columns, convert all entries (except the header) to
            % string type explicitly.            
            for i = 2:size(castedColumn)
                castedColumn{i} = string(column{i});
            end
            
        end
        
    end
    
    % Open the text file as a single character vector.
    file = fileread(filename);
    
    % Split the file into lines by newline characters. Each element
    % corresponds to a row of the original text file.
    file = strip(file, newline);
    file = split(file, newline);
    
    % Strip leading/trailing delimiters from each line.
    file = strip(file,'both');

    % Split each line into fields using tab (or whitespace) delimiters.
    file = split(file);
    
    % Cast each column using the smartCast function to obtain a uniform
    % type within each column.
    for col=1:size(file,2)
        file(:,col) = smartCast(file(:,col));
    end
    
    % Convert the cell array containing the file data to a table. The first
    % row contains variable names; data starts from the second row.
    table = cell2table(file(2:end,:));
   
    % Set the names of the variables to the values listed in the first row
    % of the file, forcing lowercase for uniform naming.
    table.Properties.VariableNames = lower(file(1,:));
    
    % Extract the final path component (filename) and split by underscores
    % and periods to retrieve tokens.
    parsedFilename = split(filename,["\", "/"]);
    parsedFilename = parsedFilename(end);
    parsedFilename = split(parsedFilename,["_","."]);
    
    % Animal name token (first element).
    Animal_Name = parsedFilename(1);
    Animal_Name = repmat(Animal_Name,size(table,1),1);

    % Session date token (second element), interpreted as MM-dd-yy.
    Session_Date = datetime(parsedFilename(2),'InputFormat','MM-dd-yy');
    Session_Date = repmat(Session_Date,size(table,1),1);
    
    % Session number token: if present, use the penultimate token; 
    % otherwise default to 1.
    if length(parsedFilename) >= 6
        Session_Number = str2double(parsedFilename(end-1));
    else
        Session_Number = 1;
    end
    Session_Number = repmat(Session_Number,size(table,1),1);
    
    % Append the inferred metadata as additional variables in the table.
    table = addvars(table, Animal_Name);
    table = addvars(table, Session_Date);
    table = addvars(table, Session_Number);
end


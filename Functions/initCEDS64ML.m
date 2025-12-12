%{
Date Created: 5/31/2022
Description: This helper function initializes the CEDS64 MATLAB interface
(available for download here: https://ced.co.uk/upgrades/spike2matson) used
to read Spike2 recordings. It adds the CEDS64ML toolbox to the MATLAB path,
loads the CEDS64 shared library, annd sets the CEDS64ML environment 
variable. It should be run any time a new MATLAB sesssion is created and 
CED Matlab functions are needed for the analysis pipeline.
%}

function initCEDS64ML()
    % INITCEDS64ML  Initialize the CEDS64 MATLAB interface for Spike2 
    %   files. 
    %   
    %   INITCEDS64ML() adds the CEDS64ML MATLAB interface to the 
    %   path and loads the CEDS64 shared library, then sets the CEDS64ML 
    %   environment variable so that subsequent CEDS64* functions can 
    %   locate the library.
    %
    %   This function should be called once per MATLAB session before 
    %   running any preprocessing code that reads Spike2 (.smrx/.s2rx) data
    %   (for example, PreProcessAllExperimentalGroups).
    %
    %   The CEDS64ML directory is assumed to live in a subfolder named
    %   "CEDMATLAB\CEDS64ML" adjacent to this file on disk.
    %
    %   See also CEDS64LoadLib.

    cedpath = fileparts(mfilename( 'fullpath' )) + "\CEDMATLAB\CEDS64ML\";
    addpath( cedpath );
    CEDS64LoadLib( cedpath );

    if isempty(getenv('CEDS64ML'))
       setenv('CEDS64ML', cedpath);
    end

end
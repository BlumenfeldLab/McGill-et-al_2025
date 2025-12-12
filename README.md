# Code for "Auditory sensory processing induces cortical and thalamic event-related desynchronization in the mouse"



This repository contains the full codebase used to preprocess, analyze, and visualize the electrophysiology and behavioral data in the publication:



> McGill, S. H., Xin, Q., Yadav, T., Zhao, C. W., Paszkowski, P., Darby, F., Guha, M., Nguyen, T., Jin, D. S., Nir, Y., Liu, J., Sieu, L-A., \\\& Blumenfeld, H. (2025). Auditory sensory processing induces cortical and thalamic event-related desynchronization in the mouse. PLOS ONE, 20(10), e0334293. https://doi.org/10.1371/journal.pone.0334293



All datasets required to reproduce figures, including raw Spike2 recordings, behavioral results files, histology images, and metadata are available through the Dryad link below.

https://datadryad.org/dataset/doi:10.5061/dryad.jh9w0vtq9



---



## 1\. Repository Structure



The repository is organized as follows:



* **/Data/**
  Reserved for the raw data files. Users must download the files from the repository (located here: https://datadryad.org/dataset/doi:10.5061/dryad.jh9w0vtq9), uncompress the files, and place them in this folder. The files expected to be in this folder include the Spike2 recordings ('*.smrx','*.s2rx'), the behavioral results text files, and the excel datasheets associated with each subject mouse. Due to the size of the dataset, we chose not to host the files directly on GitHub.
* **/Functions/**
  This folder contains helper functions and utilities. These files include functions for parsing Spike2 recordings, detecting events, loading and organizainng behavioral and electrophysiological data, constructing session and trial data structures, and running the statistical procedures.
* **/Scripts/**
  The scripts folder contains the top-level scripts driving the analytical pipeline. This folder includes `ExtractPeristimulusIntertrialIntervalTraces.m`, which runs the main preprocessing pipeline, `aggBehavior.mlx`, which performs the primary behavioral and spectrographic analyses, `runSpatialTemporalPermOnSpectrogram.mlx`, which executes the cluster-based permutation tests on the spectrograms, and `plot\\\_psd\\\_script.m`, which performs the PSD analysis.
* **/Processed Data/**
  The processed data folder will contain the output of the preprocessing script. After running the script, the folder will contain a master index of experimental groups entitled `experimentalGroupTable.mat`, as well as a number of `\\\*.mat` files containing tables encapsulating peristimulus LFP traces and metadata organized in atomic fashion.
* **/Analysis Outputs/**
  This folder is normally empty, but will contain intermediate analytical products including spectrograms and PSD curve data, cluster-based permutation statistics, and PSD significance summaries when their associated analytical scripts are executed.
* **Figure Outputs/**  
  This folder contains the figures produced by the analytical pipeline. Saved figures produced by downstream analysis and plotting scripts. Please note that the figures featured in the paper are not the direct output of MATLAB scripts. Rather, the figures were created by importing the MATLAB figures into Adobe Illustrator and editing the figures to conform with the style guidelines of PLOS One.



---



## 2\. Dependencies



The pipeline is implemented in MATLAB and makes use of the following dependencies:



* MATLAB R2021a or later
* The CEDS64 MATLAB Interface Library (Available on their website at the following link: https://ced.co.uk/upgrades/spike2matson)
* The Signal Processing Toolbox
* The function shadedErrorBar created by Rob Campbell (Repository located here: https://github.com/raacampbell/shadedErrorBar)



Before running the Spike2-dependent scripts, you should ensure that the CEDS64 MATLAB Interface Library is located within the /Functions/ Folder. You will also need to execute the function initCEDS64ML() located within the /Functions/ folder to ensure that the library is initialized. The function shadedErrorBar only needs to be within the MATLAB path.



---



## 3\. Required Data



All data needed to rerun the pipeline originate from the Dryad dataset linked above. This dataset contains the raw electrophysiological recordings in Spike2 format, the behavioral text logs that describe each trial, the Excel spreadsheets documenting animal histories, implant locations, and behavioral progression, and the histology images used for electrode verification. After downloading these resources, the user should place them into the Data directory (or link them symbolically) with their original filenames intact so that the code can automatically detect and load them.



---



## 4\. High-Level Workflow



Conceptually, the analysis proceeds in four stages:



1. Preprocessing of raw behavioral and LFP data
   The first stage is preprocessing, driven by the script `ExtractPeristimulusIntertrialIntervalTraces.m`. During this stage, the code constructs MATLAB tables representing sessions and trials, loads and parses behavioral results files and Spike2 recordings, determines the timing of sessions and trial phases, extracts stimulus-related event times from the audio channel, and identifies each experimental group. It then extracts baseline and peristimulus LFP segments for every trial in every group, normalizes these traces using per-trial baseline statistics, removes trials that cannot be validly aligned, and writes a processed .mat file for each experimental group to the folder /Processed Data/ together with a master table summarizing all groups.
2. Spectrogram and PSD analysis
   The second stage involves computing spectrograms, PSD estimates, and volume–response relationships. This is carried out by the script `aggBehavior.mlx`, which loads the preprocessed LFP data, organizes trials by condition and channel, computes baseline-normalized spectrograms for every animal, estimates band-limited power in defined post-stimulus windows, and computes PSDs across selected time periods following the stimulus. It saves these results to the /Analysis Outputs/ folder.
3. Cluster-based permutation testing on spectrograms
   The third stage performs statistical comparisons of time–frequency representations using cluster-based permutation tests. The script `runSpatialTemporalPermOnSpectrogram.mlx` compares selected conditions (such as full-volume versus zero-volume trials) for each recording channel by constructing per-animal difference spectrograms and applying a spatio–temporal cluster permutation test over the time–frequency grid. The output of this step, which includes p-values, t-statistics, and detailed cluster information, is saved to a dedicated subdirectory within Analysis Outputs.
4. Plotting and significance visualization
   The final stage, implemented in `plot\\\_psd\\\_script.m`, creates all major figures. It loads both the raw spectrogram/PSD data and the permutation-test results, generates group-average spectrograms, produces condition-difference maps with and without significance masking, plots PSD curves with shaded standard errors, and compiles significance summaries across frequency bands. These figures are saved into the Figure Outputs directory, and accompanying significance summaries are stored in the Analysis Outputs/PSD Analysis directory.



---



## 5\. Explanation of the Preprocessing Pipeline



The preprocessing stage begins by constructing a session-level table. This table lists each recorded behavioral session, identifies the associated animal, date, and session number, and records the paths to all relevant files, including the behavioral results text file, the Spike2 recording, and the Excel datasheet. To build the trial-level table, the code parses each behavioral results file, which contains one row per trial and includes variables describing the trial type, sound volume, stimulus identity, and behavioral responses. The trial table merges this information with session metadata and thus provides a complete description of every trial in the dataset.

To determine the precise timing boundaries of each session, the script analyzes a designated Spike2 recording channel that contains long-duration signal blocks marking session start and end. Sessions whose boundaries cannot be unambiguously identified are removed from further analysis. For each remaining session, the script reconstructs the timing of individual trial phases. It infers these phases by analyzing transitions in the same signal channel and by taking into account the specific session type. This yields the timing of the intertrial interval, stimulus period, post-stimulus delay, and several lick-related phases. If a session fails to produce well-defined timings for its main phases, it is discarded.



Stimulus onset and offset times are then refined by analyzing activity in the audio channel of the Spike2 file. If exactly one stimulus-like event is detected within the expected trial window, its timing is used directly. If no stimulus is detected but the behavioral log indicates that one should have occurred, the code falls back to a heuristic estimate based on the known hardware latencies used in the experiment. Trials with multiple separate stimulus detections in the same period are removed entirely due to the ambiguity.



Once all usable session and trial timings have been determined, the script identifies the atomic experimental groups that actually occurred in the dataset. Groups are defined by the combination of the animal identity, the behavioral session type, the trial type, the stimulus amplitude, the animal’s behavioral response, and the recording channel. The script checks which groups contain data and constructs a unique name for each one. It also records whether the electrode was verified to be in the intended anatomical location.



For every valid trial in every group, the script next extracts LFP traces. It uses two complementary functions to perform this extraction: one that extracts a variable-length interval based on start and end times, and another that extracts a fixed-width window centered on a specified event. The baseline window is  defined as the two seconds preceding the stimulus, while the peristimulus window spans three seconds before and three seconds after stimulus onset. After ensuring that the extracted windows are valid, the script assigns a time axis to each peristimulus trace such that time zero corresponds to stimulus onset.

Normalization occurs on a per-trial basis. The baseline trace for each trial is transformed into z-scores using its own mean and standard deviation. The peristimulus trace is then normalized using the baseline’s distribution so that its values reflect changes relative to baseline. Trials with incomplete windows or invalid traces are removed at this stage.



Finally, the script gathers the per-trial traces, event timings, and identifying metadata into a MATLAB table and saves it to the Processed Data directory under a file name unique to the group. The set of all groups is summarized in the master file `experimentalGroupTable.mat`, which lists each group’s identity, channel information, data-validity flags, number of trials, and the path to its corresponding `.mat` file.



---



## 6\. Spectrogram and PSD Analysis



The next stage of analysis is driven by the script `aggBehavior.mlx`. This script loads the experimentalGroupTable and then, for each condition and channel, gathers LFP matrices across animals. It excludes any channels identified during visual inspection as unreliable. Once the data are organized, the script computes baseline-normalized spectrograms. These spectrograms are calculated at 1 kHz using a 250-sample window and an overlap chosen to match the parameters used in the original study. For each animal, the spectrogram is computed trial-by-trial, converted to log power, normalized by subtracting the mean baseline power at each frequency, and then averaged across trials. The result is a time–frequency representation for each animal that is aligned to stimulus onset.



After the spectrograms are generated, the script computes power within specific frequency bands over a defined post-stimulus window. This step produces volume–response relationships characterizing how gamma-band power changes as stimulus intensity increases. These relationships are saved to disk for later figure preparation.



The script also computes PSDs in several discrete time windows following the stimulus. These PSDs are normalized relative to a pre-stimulus baseline and stored along with the spectrogram data in Analysis Outputs. The computed spectrograms and PSDs form the basis for both the permutation tests and the final figures.



---



## 7\. Cluster-Based Permutation Tests



Statistical comparison between conditions is performed by `runSpatialTemporalPermOnSpectrogram.mlx`. This script creates time–frequency difference maps for each recording channel by subtracting the spectrograms of one condition from those of another (for example, full-volume trials minus zero-volume trials). It ensures that only animals present in both conditions are included in the comparison. Using the AB Modeling toolbox, the script defines a one-dimensional adjacency structure across frequency bins and then performs a cluster-based permutation test over the time–frequency grid. This procedure identifies clusters of contiguous time–frequency points whose condition differences exceed that expected by chance, according to a distribution formed from 5000 permutations. Each channel’s results—including p-values, cluster masses, and original t-statistics—are automatically saved into a dedicated subdirectory within Analysis Outputs.



---



## 8\. Plotting and PSD Significance



Once spectral and statistical results are available, the `plot\\\_psd\\\_script.m` script produces the figures used in the publication. It reconstructs group-average spectrograms for each condition and channel, generates condition-difference spectrograms, and applies the permutation-test results to create significance-masked versions in which only clusters surviving statistical testing remain visible. The script also constructs baseline-normalized PSD curves for selected time windows and displays them alongside shaded error ranges representing between-animal variability. Frequencies showing significant condition differences are extracted from the permutation results and stored for reference in a summary file within `Analysis Outputs/PSD Analysis`.



---



## 9\. Reproducing the Analysis



To reproduce the entire analysis pipeline, the user should begin by cloning this repository and adding it to the MATLAB path. The complete Dryad dataset must then be downloaded and placed inside the /Data/ directory. After verifying that the CEDS64 MATLAB library and any necessary toolboxes are available, the user may run the preprocessing script `ExtractPeristimulusIntertrialIntervalTraces.m`, which will populate the Processed Data directory with group-level outputs. With these in place, the next step is to execute `aggBehavior.mlx` to compute spectrograms, PSDs, and volume–response metrics. Following this, the user may run `runSpatialTemporalPermOnSpectrogram.mlx` to generate permutation-based significance tests, and finally plot\_psd\_script.m to produce all figures and PSD significance summaries.



---



## 10\. Contact and Licensing



Questions regarding the dataset, analysis code, or reproduction of results should be directed to the corresponding author listed in the PLOS ONE publication associated with this repository. All original code in this repository is available to reuse under a BSD 3-Clause License. This repository also contains portions of code derived from the Mass Univariate ERP Toolbox by David M. Groppe, which is distributed under the BSD 3-Clause License. In accordance with the terms of that license, the original copyright notices and licensing information have been preserved. For more information on licensing, see LICENSE.md.

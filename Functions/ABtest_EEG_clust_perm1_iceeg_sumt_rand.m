% function [pval, t_orig, clust_info, seed_state, est_alpha, mn_clust_mass] = ...
%     ABtest_EEG_clust_perm1_iceeg_sumt_rand(data,chan_hood,n_perm,fwer, ...
%                                            tail,thresh_p,verblevel, ...
%                                            seed_state,freq_domain)
%
% ABtest_EEG_clust_perm1_iceeg_sumt_rand
%       This function is a one-sample cluster-based permutation test using
%       the "cluster mass" statistic and a null hypothesis of a mean of 
%       zero. This function is derived from clust_perm1.m featured in the
%       Mass Univariate ERP Toolbox (David Groppe, Kutaslab; 
%       https://github.com/dmgroppe/Mass_Univariate_ERP_Toolbox) and has 
%       been adapted for datasets that may contain NaNs and channel-
%       specific numbers of observations.
%
%       As in clust_perm1.m, the test can handle multiple electrodes and
%       time points/frequencies, and implements a cluster-mass based
%       permutation test originally proposed for MRI data by Bullmore et
%       al. (1999) and for EEG/MEG analysis by Maris & Oostenveld (2007).
%
% -------------------------------------------------------------------------
% Required Inputs:
% -------------------------------------------------------------------------
%   data      
%       - 3D matrix of data (Channel x Time x Participant). This function 
%       assumes a one-sample test with a null hypothesis of mean(data) == 
%       0. NaNs are allowed and are treated as missing observations. For 
%       each channel, the effective N and degrees of freedom are computed 
%       based on non-NaN entries.
%
%   chan_hood 
%       - 2D symmetric binary matrix that indicates which channels are
%       considered neighbors of other channels. E.g., if chan_hood(2,10)=1,
%       then Channel 2 and Channel 10 are neighbors. You can produce a 
%       chan_hood matrix using the function spatial_neighbors.m from the
%       Mass Univariate ERP Toolbox, but it is not necessarily needed.
%
% -------------------------------------------------------------------------
% Optional Inputs:
% -------------------------------------------------------------------------
%   n_perm    
%       - Number of permutations {default=2000}. Manly (1997) suggests
%       using at least 1000 permutations for an alpha level of 0.05 and at
%       least 5000 permutations for an alpha level of 0.01.
%
%   fwer
%       - Desired family-wise error rate (i.e., alpha level) 
%       {default = .05}.
%
%   tail
%       - [1 | 0 | -1]
%       1  - upper-tailed test (mean(data) > 0)
%       0  - two-tailed test (mean(data) ≠ 0)
%       -1 - lower-tailed test (mean(data) < 0)
%       {default: 0}
%
%   thresh_p  
%       - Test-wise p-value threshold for cluster inclusion. If a
%       channel/time-point has a t-score whose uncorrected p-value exceeds
%       thresh_p, it is not considered for clustering (its t-value is set 
%       effectively below threshold). thresh_p automatically takes tail 
%       into account (you get appropriate positive/negative t-thresholds 
%       for two-tailed tests).
%
%   verblevel
%       - Verbosity level for command-line output:
%       0 - quiet (errors, warnings, EEGLAB reports only)
%       1 - minimal information
%       2 - standard information (default)
%       3 - detailed/debug information
%
%   seed_state 
%       - Initial state of the random number generator stream (see MATLAB 
%       documentation for "RandStream"). Pass in a state from a previous 
%       run to reproduce the same permutation sequence (subject to parallel
%       RNG behavior if parfor is used).
%
%   freq_domain 
%       - If 0, reports are given in temporal units (time points). 
%       Otherwise, reports are given in frequency units (frequencies). 
%       {default: 0}
%
% -------------------------------------------------------------------------
% Outputs:
% -------------------------------------------------------------------------
%   pval       
%       - Matrix of p-values at each time point and channel, corrected for
%       multiple comparisons via the cluster-based permutation test.
%
%   t_orig     
%       - Matrix of t-scores at each time point and channel for the
%       original (non-permuted) data.
%
%   clust_info 
%       - Struct with information about the clusters found. Depending on 
%       the tail of the test, it includes some or all of:
%       pos_clust_pval - p-values of positive clusters
%       pos_clust_mass - t-score mass of positive clusters
%       pos_clust_ids  - channel x time matrix of positive cluster IDs (0 =
%       not in any cluster)
%       neg_clust_pval - p-values of negative clusters
%       neg_clust_mass - t-score mass of negative clusters
%       neg_clust_ids  - channel x time matrix of negative cluster IDs (0 =
%       not in any cluster)
%
%   seed_state 
%       - Initial state of the random number generator used to generate the
%       permutations. Can be used to reproduce the permutation sequence 
%       (again, subject to parallel RNG considerations when parfor is 
%       used).
%
%   est_alpha  
%       - Estimated family-wise alpha level of the test. Because a finite
%       number of permutations yields a discrete set of possible p-values,
%       the achieved FWER may differ slightly from the requested fwer. This
%       output reports the observed FWER under the null distribution of 
%       cluster masses.
%
%   mn_clust_mass 
%       - 1 x n_perm vector of the most negative cluster mass observed on 
%       each permutation. This is the null distribution against which
%       observed cluster masses are compared. Note that this output is
%       modied from clust_perm1. clust_perm1 computes this internally but
%       does not expose it as an output.
%
% Changes from clust_perm1.m
%   Function name and outputs
%       - Function name changed from clust_perm1 to
%       ABtest_EEG_clust_perm1_iceeg_sumt_rand.
%       - mn_clust_mass added as an addditional output. This variable 
%       stores the null distribution of the most negative cluster mass 
%       across permutations. (In clust_perm1.m this vector was internal 
%       only and not returned.)
%
%   Handling of missing data and effective N
%       - This version is designed to tolerate NaNs in the data matrix by 
%       using nansum instead of sum when computing sums/SS across subjects.
%       The effective number of subjects is thus allowed to vary by
%       channel. The effective number of subjects is allowed to vary by
%       channel, and accordingly the t-statistic degrees of freedom are
%       computed per-channel rather than usinng a single global value for
%       all channels.
%
%   Permutation sign-flipping scheme
%       - In the the original clust_perm1.m, sn(1,1,1:n_subs) = 
%       (rand(1,n_subs)>.5)*2 - 1 and sn_mtrx = repmat(sn,[n_chan n_pts 1])
%       or in plain english each subject was assigned a single sign across
%       all channels and time points on each permutation. In this
%       implementation sn_test(1:n_chan,1:n_pts,1:n_subs) = 
%       (rand(n_chan,n_pts,n_subs)>.5)*2 - 1 and sn_mtrx = sn_test, i.e.
%       the sign is randomized independently for each channel-time-subject
%       sample. This change alters the structure of the null distribution 
%       relative to the subject-wise sign-flip used in clust_perm1.m and 
%       which will likely change the inferred cluster statistics and Type I
%       error characteristics of the function.
%
%   Parallelization
%       - The permutation loop uses parfor instead of for to allow parallel 
%       execution when a parallel pool is available. This affects 
%       performance but not the nominal statistical logic, aside from the 
%       usual caveats regarding reproducibility and random number streams 
%       in parallel contexts.
%
%   Verbose reporting
%       Basic progress reporting via fprintf is retained.
%
% -------------------------------------------------------------------------
% Implementation Notes
% -------------------------------------------------------------------------
%   - As with clust_perm1.m, this is a one-sample test based on random sign
%   flips under the null hypothesis of zero mean.
%
%   - Unlike a parametric test (e.g., ANOVA), only a discrete set of 
%   p-values is possible (limited by the number of permutations). For very
%   small sample sizes the test may be overly conservative (see Manly,
%   1997, for details).
%
%  - Two-tailed tests are implemented as separate upper- and lower-tailed
%  tests with a Bonferroni correction factor of 2, which can lead to 
%  p-values slightly greater than 1 (these are typically capped at 1 in
%  downstream usage).
%
%  - Because this implementation uses channel/time/subject-wise sign
%  flipping and channel-specific Ns, its exact null distribution and
%  error properties differ from those of the original clust_perm1.m
%  implementation, which uses subject-wise sign flips and a single N.
%
% -------------------------------------------------------------------------
% Misc
% -------------------------------------------------------------------------
%
% Original Author:
%   David Groppe, May 2011, Kutaslab, San Diego
%
% References:
%   Bullmore, E. T., Suckling, J., Overmeyer, S., Rabe-Hesketh, S.,
%   Taylor, E., & Brammer, M. J. (1999). Global, voxel, and cluster tests,
%   by theory and permutation, for a difference between two groups of
%   structural MR images of the brain. IEEE Trans Med Imaging, 18(1), 32–42.
%
%   Maris, E., & Oostenveld, R. (2007). Nonparametric statistical testing of
%   EEG- and MEG-data. J Neurosci Methods, 164(1), 177–190.
%
%   Manly, B. F. J. (1997). Randomization, Bootstrap and Monte Carlo
%   Methods in Biology (2nd ed.). Chapman & Hall.
%
% If you reuse this function for your project, per the request of David 
% Groppe please cite within all related publications the following article:
%
% Groppe, D.M., Urbach, T.P., Kutas, M. (2011) Mass univariate analysis of 
% event-related brain potentials/fields I: A critical tutorial review, 
% Psychophysiology, 48(12) pp. 1711-1725, 
% DOI: 10.1111/j.1469-8986.2011.01273.x
%
% -------------------------------------------------------------------------
% License Notice
% -------------------------------------------------------------------------
% This file incorporates code from the Mass Univariate ERP Toolbox
% (https://github.com/dmgroppe/Mass_Univariate_ERP_Toolbox)
% Copyright (c) 2015, David Groppe
% Licensed under the BSD 3-Clause License; see LICENSE.md in the repository
% root and thirdparty/mass_univariate_erp_toolbox/LICENSE for details.


function [pval, t_orig, clust_info, seed_state, est_alpha, mn_clust_mass] = ABtest_EEG_clust_perm1_iceeg_sumt_rand(data,chan_hood,n_perm,fwer,tail,thresh_p,verblevel,seed_state,freq_domain)

% Check input 1
if nargin<1
    error('You need to provide data.');
end

% Check input 2
if nargin<2
    error('You need to provide a chan_hood matrix.');
end

% Check input 3
if nargin<3
    n_perm=2000;
end

%C heck input 4
if nargin<4
    fwer=.05;
elseif (fwer>=1) || (fwer<=0)
    error('Argument ''fwer'' needs to be between 0 and 1.');
end

% Warning about p-value threshold and number of permutation
if fwer<=.01 && n_perm<5000
    watchit(sprintf('You are probably using too few permutations for a FWER (i.e., alpha level) of %f. Type ">>help clust_perm1" for more info.',fwer));
elseif fwer<=.05 && n_perm<1000
    watchit(sprintf('You are probably using too few permutations for a FWER (i.e., alpha level) of %f. Type ">>help clust_perm1" for more info.',fwer));
end

% Check input 5
if nargin<5
    tail=0;
elseif (tail~=0) && (tail~=1) && (tail~=-1)
    error('Argument ''tail'' needs to be 0,1, or -1.');
end

% Check input 6
if nargin<6
    thresh_p=.05;
elseif thresh_p<=0 || thresh_p>1
    error('Argument thresh_p needs to take a value between 0 and 1');
end

% Check input 7
if nargin<7
    verblevel=2;
end

% Get random # generator state
% Check Matlab version
if verLessThan('matlab','7.6')
    watchit('Your version of MATLAB is too old to seed random number generator. You will not be able to exactly reproduce test results.');
    seed_state=NaN;
else
    if verLessThan('matlab','8.1')
        defaultStream=RandStream.getDefaultStream;
    else
        defaultStream=RandStream.getGlobalStream;
    end
    if (nargin<6) || isempty(seed_state)
        % Store state of random number generator
        seed_state=defaultStream.State;
    else
        defaultStream.State=seed_state; % Reset random number generator to saved state
    end
end

% Check input 9
if (nargin<9)
    freq_domain=0;
end

% Acquire dimensions of data (voxel x time x subject)
s=size(data);
n_chan=s(1); % Number of voxel
n_pts=s(2); % Number of time points
n_subs=s(3); %N umber of subjects

% Check if too little subjects (less than 2)
if n_subs<2
    error('You need data from at least two observations (e.g., participants) to perform a hypothesis test.')
end

% Check if too little subjects (less than 7)
if n_subs<7
    n_psbl_prms=2^n_subs;
    watchit(sprintf(['Due to the very limited number of participants,' ...
        ' the total number of possible permutations is small.\nThus only a limited number of p-values (at most %d) are possible and the test might be overly conservative.'], ...
        n_psbl_prms));
end

%C reate array of subject numbers
n_subs_all=sum(~isnan(squeeze(data(:,1,:))),2);

% T-score degrees of freedom
df=n_subs_all-1;

% Print cluster procedure details
if verblevel~=0
    fprintf('clust_perm1: Number of channels: %d\n',n_chan);
    if freq_domain
        fprintf('clust_perm1: Number of frequencies: %d\n',n_pts);
    else
        fprintf('clust_perm1: Number of time points: %d\n',n_pts);
    end
    fprintf('clust_perm1: Total # of comparisons: %d\n',n_pts*n_chan);
    fprintf('clust_perm1: Number of participants: %s\n',num2str(n_subs_all'));
    fprintf('t-score degrees of freedom: %s\n',num2str(df'));
end

% Determine if one-tailed (-1/1) or two-tailed test (0)
if tail
    % one tailed test - student's t
    thresh_t=tinv(thresh_p,df); %note unless thresh_p is greater than .5, thresh_t will be negative
else
    % two tailed test - student's t
    thresh_t=tinv(thresh_p/2,df);
end

%% Run Permutation

% Print permutation progress
if (verblevel>=2)
    fprintf('Permutations completed: ');
end

% Constant factor for computing t, speeds up computing t to precalculate 
% now
sqrt_nXnM1=sqrt(n_subs_all.*(n_subs_all-1));

% Setup empty matrix of zeros
mn_clust_mass=zeros(1,n_perm);

% Loop over permutation iterations and print progress
parfor perm=1:n_perm
    if ~rem(perm,100)
        if (verblevel>=2)
            if ~rem(perm-100,1000)
                fprintf('%d',perm);
            else
                fprintf(', %d',perm);
            end
            if ~rem(perm,1000)
                fprintf('\n');
            end
        end
    end

    % Randomly set sign of each participant's data (random : chan,pts,subs)
    sn_test=zeros(n_chan,n_pts,n_subs); % Create empty channel/voxel x time x subjects
    sn_test(1:n_chan,1:n_pts,1:n_subs)=(rand(n_chan,n_pts,n_subs)>.5)*2-1; % Randomly select -1/1 values in voxel x time x subject matrix
    
    % Rename variable
    sn_mtrx=sn_test;
    
    % Multiple 0x1 matrix by data matrix to select just what we want.
    d_perm=data.*sn_mtrx; %Convert data signs by -1/1 matrix multiplier

    % Computes t-score of permuted data across all channels and time points or frequencies
    sm=nansum(d_perm,3); % Sum across subjects 
    
    mn=sm./n_subs_all; % Divide by the number of subjects - finding the average
    sm_sqrs=nansum(d_perm.^2,3)-(sm.^2)./n_subs_all; % Calculate the t value
    stder=sqrt(sm_sqrs)./sqrt_nXnM1;
    t=mn./stder;
    
    % Find clusters - t-values that breach threshold and adjacent
    [clust_ids, n_clust]=find_clusters(t,thresh_t,chan_hood,-1);

    % get most extremely negative t-score (sign isn't important since we asumme
    % symmetric distribution of null hypothesis for one sample test)
    mn_clust_mass(perm)=find_mn_mass(clust_ids,t,n_clust);
    
end

% End permutations completed line
if (verblevel>=2) 
    fprintf('\n');
end

% Estimate true FWER of test
if tail==0
    % two-tailed
    tmx_ptile=prctile(mn_clust_mass,100*fwer/2);
    est_alpha=mean(mn_clust_mass<=tmx_ptile)*2;
else
    % one tailed
    tmx_ptile=prctile(mn_clust_mass,100*fwer);
    est_alpha=mean(mn_clust_mass<=tmx_ptile);
end

% If not two-tailed test
if verblevel~=0
    fprintf('Desired family-wise error rate: %f\n',fwer);
    fprintf('Estimated actual family-wise error rate: %f\n',est_alpha);
end

%% Calculate t-values for original (non-permutated data)

% computes t-scores of observations at all channels and time points/frequencies

% Calculate average over subjects
sm=nansum(data,3);
mn=sm./n_subs_all;

% T-value calculation
sm_sqrs=nansum(data.^2,3)-(sm.^2)./n_subs_all;
stder=sqrt(sm_sqrs)./sqrt_nXnM1;
t_orig=mn./stder;

% Setup empty matrix to add computed p-values
pval=ones(n_chan,n_pts);

% If two-tailed test
if tail==0
    
    % Find positive clusters
    [clust_ids, n_clust]=find_clusters(t_orig,-thresh_t,chan_hood,1); % note thresh_t is negative by default
    clust_info.pos_clust_pval=ones(1,n_clust);
    clust_info.pos_clust_mass=zeros(1,n_clust);
    clust_info.pos_clust_ids=clust_ids;
    
    % Loop over clusters to find p-values
    for a=1:n_clust
        use_ids=find(clust_ids==a);
        clust_mass=sum(t_orig(use_ids)); 
        clust_p=mean(mn_clust_mass<=(-clust_mass))*2; % multiply by 2 since we're effectively doing Bonferroni correcting for doing two tests (an upper tail and lower tail)
        pval(use_ids)=clust_p;
        clust_info.pos_clust_pval(a)=clust_p;
        clust_info.pos_clust_mass(a)=clust_mass;
    end
    
    % Find negative clusters
    [clust_ids, n_clust]=find_clusters(t_orig,thresh_t,chan_hood,-1); % note thresh_t is negative by default
    clust_info.neg_clust_pval=ones(1,n_clust);
    clust_info.neg_clust_mass=zeros(1,n_clust);
    clust_info.neg_clust_ids=clust_ids;
    
    % Loop over clusters to find p-values
    for a=1:n_clust
        use_ids=find(clust_ids==a);
        clust_mass=sum(t_orig(use_ids));
        clust_p=mean(mn_clust_mass<=clust_mass)*2; % multiply by 2 since we're effectively doing Bonferroni correcting for doing two tests (an upper tail and lower tail)
        pval(use_ids)=clust_p;
        clust_info.neg_clust_pval(a)=clust_p;
        clust_info.neg_clust_mass(a)=clust_mass;
    end

% If one-tailed test
elseif tail==1
    
    % Upper tailed
    [clust_ids, n_clust]=find_clusters(t_orig,-thresh_t,chan_hood,1); % note thresh_t is negative by default
    clust_info.pos_clust_pval=ones(1,n_clust);
    clust_info.pos_clust_mass=zeros(1,n_clust);
    clust_info.pos_clust_ids=clust_ids;
    
    % Loop over clusters
    for a=1:n_clust
        use_ids=find(clust_ids==a);
        clust_mass=sum(t_orig(use_ids));
        clust_p=mean(mn_clust_mass<=(-clust_mass));
        pval(use_ids)=clust_p;
        clust_info.pos_clust_pval(a)=clust_p;
        clust_info.pos_clust_mass(a)=clust_mass;
    end
    
else
    
    % Lower tailed
    [clust_ids, n_clust]=find_clusters(t_orig,thresh_t,chan_hood,-1); % note thresh_t is negative by default
    clust_info.neg_clust_pval=ones(1,n_clust);
    clust_info.neg_clust_mass=zeros(1,n_clust);
    clust_info.neg_clust_ids=clust_ids;
    
    % Loop over clusters
    for a=1:n_clust
        use_ids=find(clust_ids==a);
        clust_mass=sum(t_orig(use_ids));
        clust_p=mean(mn_clust_mass<=clust_mass);
        pval(use_ids)=clust_p;
        clust_info.neg_clust_pval(a)=clust_p;
        clust_info.neg_clust_mass(a)=clust_mass;
    end
    
end

%%% End of Main Function %%%

function mn_clust_mass=find_mn_mass(clust_ids,data_t,n_clust)

mn_clust_mass=0;

% looking for most negative cluster mass
for z=1:n_clust
    use_ids=(clust_ids==z);
    use_mass=sum(data_t(use_ids));
    if use_mass<mn_clust_mass
        mn_clust_mass=use_mass;
    end
end
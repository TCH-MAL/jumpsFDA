% ************************************************************************
% Script: jumpsFDA
% Purpose:  Perform batches of functional data analysis on the jumps time series
%
%
% ************************************************************************

clear;

% ************************************************************************
%     Setup file paths
% ************************************************************************

if ismac
    rootpath = '/Users/markgewhite/Google Drive/PhD/Studies/Jumps';
else
    rootpath = 'C:\Users\markg\Google Drive\PhD\Studies\Jumps';
end

datapath = [ rootpath '\Data\Processed\Training' ];

if ismac
    datapath = strrep( datapath, '\', '/') ;
end


% ************************************************************************
%   Read data file
% ************************************************************************

cd(datapath);

% read the processed data file
load(fullfile(datapath,'compactjumpdata.mat'));


% ************************************************************************
%   Constants
% ************************************************************************

g = 9.812; % acceleration due to gravity

tFreq = 1; % sampling frequency

nSets = 2; % number of data sets (1 = CMJ(No arms); 2 = CMJ(All))
nStd = 2; % number of methods to standardise length
nModels = 4; % number of models
nLMReg = 16; % number of landmark registration combinations including none
nCTReg = 2; % number of continuous registrations (applied or none)

% presets based on not exceed jump performance error threshold
preset.nBasis = [ 190 80; 190 80; 190 80 ];
preset.lambda = [ 1E3 1E3; 1E3 1E3; 1E3 1E3 ];

% ************************************************************************
%   Command switches
% ************************************************************************

options.test = 'None'; % type of test to perform

options.doFiltering = false; % whether to do low-pass filtering on the GRF data
options.doInitialFit = false; % whether to fit with max flexibility first

options.doCheckFit = false; % whether to check the goodness of fit
options.doResidualCheck = false; % for this check, whether to check the residuals
options.doSortCheck = false; % for this check, whether to sort from largest error to smallest
options.doUseWtFunc = false; % whether to use the weighted functional data object
options.doPlotDerivatives = false; % whether to plot the function and its first two derivatives

options.reg.doCurvePlots = false; % flag whether to show registration curve plots
options.reg.doRegHistogram = false; % flag whether to show the spread of landmark points
options.reg.doRegPlots = false; % flag whether to show registration curve plots

options.reg.doRemoveFaulty = true; % whether to remove faulty registrations

% ************************************************************************
%   Baseline settings
% ************************************************************************

setup.data.tFreq = 1; % time intervals per second
setup.data.sampleFreq = 1000; % sampling frequency
setup.data.cutoffFreq = 10; % 15 Hz cut-off frequency for filtering
setup.data.padding = 500; % milliseconds of padding for filtering
setup.data.form = 'Vertical'; % data representation
setup.data.initial = 1; % initial padding value
setup.data.threshold1 = 0.08; % primary detection threshold 
setup.data.threshold2 = 0.01; % secondary detection threshold
setup.data.sustained = 100; % milliseconds for secondary threshold 

setup.Fd.basisOrder = 4; % 5th order for a basis expansion of quartic splines
setup.Fd.penaltyOrder = 2; % roughness penalty
setup.Fd.lambda = 1E2 ; % roughness penalty
setup.Fd.names = [{'Time (ms)'},{'Jumps'},{'GRF (BW)'}]; % axes names
setup.Fd.tolerance = 0.001; % performance measure error tolerance

setup.reg.nIterations = 2; % Procrustes iterations
setup.reg.nBasis = 10; % numbers of bases for registration
setup.reg.basisOrder = 3; % time warping basis order for registration
setup.reg.wLambda = 1E-2; % roughness penalty for time warp 1E-2
setup.reg.XLambda = 1E3; % roughness penalty to prevent wiggles in y

setup.reg.lm.grfmin = false; % use VGRF minimum as a landmark?
setup.reg.lm.pwrmin = false; % use Power minimum as a landmark?
setup.reg.lm.pwrcross = false; % use Power crossing point as a landmark?
setup.reg.lm.pwrmax = false; % use Power maximum as a landmark?

setup.reg.faultCriterion = 'RelativeArea'; % after vs before area ratio
setup.reg.faultZScore = 3.5; % fault threshold

setup.pca.nComp = 15; % number of PCA components to be retained
setup.pca.nCompWarp = 5; % number of PCA components to be retained

setup.models.nRepeats = 2; % number of repetitions of CV
setup.models.nFolds = 5; % number of CV folds for each repetition
setup.models.seed = 12345; % random seed for reproducibility
setup.models.spec = 'linear'; % type of GLM
setup.models.upper = 'linear'; % linear model without interactions
setup.models.criterion = 'bic'; % predictor selection criterion
setup.models.RSqMeritThreshold = 0.0; % merit threshold for stepwise selection

setup.filename = fullfile(datapath,'jumpsAnalysis6.mat'); % where to save the analysis
setup.filename2 = fullfile(datapath,'jumpsAnalysis6.mat'); % where to save the analysis


% ************************************************************************
%   Extract data
% ************************************************************************

% exclude jumps from subjects in the second data collection
subjectExclusions = find( ismember( sDataID, ...
            [ 14, 39, 68, 86, 87, 11, 22, 28, 40, 43, 82, 88, 95, 97, ...
              100, 121, 156, 163, 196 ] ) );

% specific jumps that should be excluded
jumpExclusions = [3703 3113 2107 2116 0503 0507 6010 1109];

[ rawData, refSet, typeSet ] =  extractVGRFData( ... 
                                    grf, bwall, nJumpsPerSubject, ...
                                    sDataID, sJumpID, jumpOrder, ...
                                    subjectExclusions, jumpExclusions );

                                
% ************************************************************************
%   Smooth data - first cut
% ************************************************************************


tSpan0 = cell( nSets, 1 );
for i = 1:nSets
    
    % standardised length with padding
    maxLen = max( cellfun( @length, rawData{i} ) );
    tSpan0{i} = -maxLen+1:0; % time domain in milliseconds 
    
    rawData{i} = padData( rawData{i}, ...
                           maxLen, ...
                           setup.data.initial );
              
end 


% ************************************************************************
%   Determine smoothing levels
% ************************************************************************

perf = cell( nSets );
tSpan = cell( nSets, nStd );
vgrfData{i} = cell( nSets, nStd );

for i = 1:nSets
   
    % determine jump initation
    tStart = jumpInit( rawData{i}, ...
                       setup.data.threshold1, ...
                       setup.data.threshold2, ...
                       setup.data.sustained );
                   
   
    for j = 1:nStd

       switch j
           case 1
               % pad out to longest series
               fixStart = min( tStart );
               
               % truncate pre-padded series to this length
               vgrfData{i,j} = rawData{i}( fixStart:end, : );              
               
           case 2
               % time normalising to median series length
               fixStart = fix( median( tStart ) );
               
               % truncate times series and time normalise
               vgrfData{i,j} = timeNormData( rawData{i}, ...
                                         tStart, ...
                                         fixStart );
                                                                         
       end
       
       % compute jump performances from the truncated raw data
       if j == 1
           perf{i} = jumpperf( vgrfData{i,j} );
       end
       
       % store time span
       fixLen = size( vgrfData{i,j}, 1 );
       tSpan{i,j} = -fixLen+1:0;
       
       if options.doInitialFit
            % one basis function per data point
            setup.Fd.nBasis = fixLen + setup.Fd.basisOrder + 2;
            validateSmoothing(  vgrfData{i,j}, ...
                                tSpan{i,j}, ...
                                setup.Fd, ...
                                perf{i} );
            pause;
       end
       
    end
    
end



% ************************************************************************
%   Begin functional data analysis
% ************************************************************************

vgrfFd = cell( nSets, nStd, nLMReg, nCTReg );
warpFd = cell( nSets, nStd, nLMReg, nCTReg );
fdPar = cell( nSets, nStd );
decomp = cell( nSets, nStd, nLMReg, nCTReg );
isValid = cell( nSets, nStd, nLMReg );
name = strings( nSets, nStd, nLMReg, nCTReg );

vgrfPCA = cell( nSets, nStd, nLMReg, nCTReg );
vgrfACP = cell( nSets, nStd, nLMReg, nCTReg );

results = cell( nSets, nStd, nLMReg, nCTReg );
models = cell( nSets, nStd, nLMReg, nCTReg );

% load( setup.filename );

% set random seed for reproducibility
rng( setup.models.seed );

for i = 1:nSets
    
    % setup partitioning for all models using this data set   
    partitions = kFoldSubjectCV(  refSet{i}(:,1), ...
                                  setup.models.nRepeats, ...
                                  setup.models.nFolds );
    
    for j = 1:nStd

       % use presets specific to padding or time normalisation
       fdSetup = setup.Fd;
       fdSetup.nBasis = preset.nBasis(i,j);
       fdSetup.lambda = preset.lambda(i,j);

       % generate the smooth curves
       if isempty( vgrfFd{i,j,1,1} ) || isempty( fdPar{i,j} )
           [ vgrfFd{i,j,1,1}, fdPar{i,j} ] = smoothVGRF(  ...
                                                vgrfData{i,j}, ...
                                                tSpan{i,j}, ...
                                                fdSetup, ...
                                                options );
       end      
       
       for k = 1:nLMReg

           if isempty( isValid{i,j,k} )
               % setup reference data in case rows have to be removed
               ref = refSet{i};
               type = typeSet{i};
               jperf = perf{i};
               part = partitions;
           else
               % setup reference data based on previous validation
               ref = refSet{i}( isValid{i,j,k}, : );
               type = typeSet{i}( isValid{i,j,k}, : );
               jperf.JHtov = perf{i}.JHtov( isValid{i,j,k} );
               jperf.JHwd = perf{i}.JHwd( isValid{i,j,k} );
               jperf.PP = perf{i}.PP( isValid{i,j,k} );
               part = partitions( isValid{i,j,k}, : );
           end
           
           for l = 1:nCTReg
               
               % encode the processing procedure
               [ name{i,j,k,l}, setup.reg.lm ] = encodeProc( i, j, k, l );
               disp(['*************** ' name{i,j,k,l} ' ***************']);
               
               if l == 1 % first 'l' loop
                   if k > 1 && isempty( vgrfFd{i,j,k,l} )
                       % landmark registration required
                       % applied to unregistered curves
                       [ vgrfFd{i,j,k,l}, warpFd{i,j,k,l} ] = ...
                           registerVGRF( tSpan{i,j}, ...
                                         vgrfFd{i,j,1,1}, ...
                                         'Landmark', ...
                                         setup.reg );
                                     
                       % check for any faulty registrations
                       v = validateRegFd(  vgrfFd{i,j,1,1}, ...
                                           vgrfFd{i,j,k,l}, ...
                                           warpFd{i,j,k,l}, ...
                                           setup.reg );
                       
                       % remove faulty registrations
                       vgrfFd{i,j,k,l} = selectFd( vgrfFd{i,j,k,l}, v );
                       warpFd{i,j,k,l} = selectFd( warpFd{i,j,k,l}, v );
                       ref = ref( v, : );
                       type = type( v );
                       jperf.JHtov = jperf.JHtov( v );
                       jperf.JHwd = jperf.JHwd( v );
                       jperf.PP = jperf.PP( v );
                       part = part( v, : );
                       isValid{i,j,k} = v;
                                     
                   end
                   
               else % second 'l' loop
                   if isempty( vgrfFd{i,j,k,l} )
                       % continuous registration required
                       % applied to prior-registered curves
                       [ vgrfFd{i,j,k,l}, warpFd{i,j,k,l} ] = ...
                          registerVGRF( tSpan{i,j}, ...
                                        vgrfFd{i,j,k,1}, ...
                                        'Continuous', ...
                                        setup.reg, ...
                                        warpFd{i,j,k,1} );
                   end
               end
                   
               if k > 1 || l == 2
                   % perform a decomposition analysis
                   decomp{i,j,k,l} = regDecomp( ...
                           selectFd( vgrfFd{i,j,1,1}, isValid{i,j,k} ), ...
                           vgrfFd{i,j,k,l}, ...
                           warpFd{i,j,k,l} );
               end
               
               if isempty( vgrfPCA{i,j,k,l} )

                   % run principal component analsyis
                   vgrfPCA{i,j,k,l} = pcaVGRF( vgrfFd{i,j,k,l}, ...
                                              fdPar{i,j}, ...
                                              warpFd{i,j,k,l}, ...
                                              setup.pca.nComp, ...
                                              setup.pca.nCompWarp );

               end

               if isempty( vgrfACP{i,j,k,l} )

                   % run analysis of characterising phases
                   vgrfACP{i,j,k,l} = acpVGRF( tSpan{i,j}, ...
                                             vgrfFd{i,j,k,l}, ...
                                             warpFd{i,j,k,l}, ...
                                             vgrfPCA{i,j,k,l} );

               end                      

               % generate output tables
               if isempty( results{i,j,k,l} ) 
                    results{i,j,k,l} = outputTable( name{i,j,k,l}, ...
                                            ref, ...
                                            type, ...
                                            jperf, ...
                                            vgrfPCA{i,j,k,l}, ...
                                            vgrfACP{i,j,k,l}, ...
                                            setup );
               end

               % fit models to the data
               %if isempty( models{i,j,k,l} )
                   models{i,j,k,l} = fitVGRFModels( ...
                                        results{i,j,k,l}, ...
                                        part, setup, ...
                                        models{i,j,k,l} );
               %end
               
               % store data
               save( setup.filename2, ...
                     'decomp', 'fdPar', 'name', 'vgrfFd', 'warpFd', ...
                     'isValid', 'vgrfPCA', 'vgrfACP', 'models', 'results' ); 
         
           end
       end
       
  
       
    end
    
end


% ************************************************************************
%   Compile and save the results table
% ************************************************************************


longResults = compileResults( results );
longPerformance = compileResults( models, 'perf' );
longInclude = compileResults( models, 'incl' );
longTStat = compileResults( models, 'tStat' );
longCoeffRSq = compileResults( models, 'coeffRSq' );
longDecomp = compileResults( decomp );
faultyCountWOA = squeeze(cellfun( @sum, isValid(1,:,:) ))';
faultyCountALL = squeeze(cellfun( @sum, isValid(2,:,:) ))';


   

function filtdFoF = adaptiveDF4(varargin)
% +===================+
% | Syntax            |
% +===================+
%
%        filtdFoF = adaptiveDF4(rawImgSeries,sp)
%        filtdFoF = adaptiveDF4(rawImgSeries,sp,Name,Value)
%
%
% +===================+
% | Description       |
% +===================+
% The function adaptiveDF4 applies the calculation of a filtered delta(F)/F for
% 4-dimension calcium imaging time series described in the paper "In vivo two-photon imaging of
% sensory-evoked dendritic calcium signals in cortical neurons", by authors
% H. Jia, N. L. Rochefort, X. Chen and A. Konnerth; it was published on
% Nature Protocols in 2011.
% In particular the formulas for the calculations are found in Box 1.
%
%       dFoF = adaptiveDF4(rawImgSeries,sp)
% adaptiveDF4 performs a delta(F)/F on the matrix rawImgSeries. This
% argument has to be an 4-D matrix where the last dimension HAS to be time.
% sp is the sampling period expressed in seconds.
% The function returns delta(F)/F as a matrix, that has the same dimensions
% of the argument rawImgSeries.
%
% Other arguments can be passed as Name-Value pairs and will be treated
% below.
%
%
% +===================+
% | In-depth look     |
% +===================+
% adaptiveDF4 functions body performs three steps on the input matrix. Each one is
% characterized by a different time constant tau.
%
% STEP 1: SMOOTHING
% The raw calcium traces are smoothened with an averaging function that act
% in time windows of width tau1.
%
% STEP 2: CALCULATION OF THE BASELINE
% A baseline trace is calculated for each smoothened. calcium trace.
% Every time point will have a corresponding local baseline value. Each
% local baseline value is calculated in a time window of width tau2.
%
% STEP 3: DELTA F OVER F AND NOISE FILTERING
% The delta F over F is calculated using the raw calcium traces and the
% baseline traces.
% Then a filtering is performed. The filter is based on an exponentially
% weighted average. This filter has a time constant of tau0.
% The weights of the noise filter exponentially decay as the function: w = e^(-t/tau0)
% The weight is 1 at the point t = 0 s.
% When time reaches tau0 (t=tau0), the weight is 37%.
% The filtering can be bypassed by passing a tau0 value of 0 as argument.
%
% The three tau constants can be passed as a three-element numeric array,
% as a Name-Value pair argument:
%       adaptiveDF4(rawImgSeries,sp,'tau',[tau1 tau2 tau0])
% These values have to be greater than 0. exept for tau0. If tau0 is zero,
% then the noise filtering will be skipped.
%
% If you don't pass the argument 'tau', the program will use default
% values.
% The default values for tau0, tau1 and tau2 are expressed as function of
% the sampling period sp:
% tau0 = 6*sp
% tau1 = 22.5*sp
% tau2 = 90*sp
%
% +===================+
% | Tau defult values |
% +===================+
% When specifying tau argument, if you put 'tau',-1, you are selecting the
% default values used in Hongbo Jia paper.
% 'tau0', 0 instead selects the default values for tau1 and tau2 but
% doesn't perform any noise filter.
% If you put a three element array instead, you can choose all tau1, tau2
% and tau0 separately by selecting 'tau',[tau1 tau2 tau0].
% Or you can also choose the default value for some taus (choosing the
% value -1) and specify the others. e.g. 'tau',[-1 tau2 tau0]
% Note that 'tau',[-1 -1 -1] is the same as choosing 'tau',-1
% You can also exclude the noise filtering by choosing the value 0 for that
% parameter. 'tau', [tau1 tau2 0]
% Note that 'tau',[-1 -1 0] is the same as 'tau',0
% 


%% ARGUMENT PARSING
p = inputParser;
validScalarPosNum = @(x) isnumeric(x) && isscalar(x) && (x > 0);
validTauArray = @(x) isnumeric(x)&&isrow(x)&&length(x)==3&&...
    (all(x>=0|x==-1))||(isscalar(x)&&all(x==-1|x==0));

p.addRequired('rawImgSeries',@(x) length(size(x))==4&&isnumeric(x));
p.addRequired('sp',validScalarPosNum); % sampling period
p.addParameter('tau',-1,validTauArray);

% p.StructExpand = false; % Not sure what it does
p.parse(varargin{:})
% Import parsed variables into workspace
fargs = fields(p.Results);
for n=1:numel(fargs); eval([fargs{n} '=' 'p.Results.' fargs{n} ';']);  end

%% CONVERSION OF THE PARAMETERS AND CHECKS
% Extracting the tau variables
if tau == -1
    tau1 = 22.5*sp;
    tau2 = 90*sp;
    tau0 = 6*sp;
elseif tau == 0
    tau1 = 22.5*sp;
    tau2 = 90*sp;
    tau0 = 0;
else
    tau1=tau(1); tau2=tau(2); tau0=tau(3);
    if tau1==-1; tau1=22.5*sp; end
    if tau2==-1; tau2=90*sp; end
    if tau0==-1; tau0=6*sp; end
end

% Conversion of time constants tau1 and tau2 into time point constants
halftau1n = round(0.5*(tau1-sp)/sp); 
tau2n = round(tau2/sp);
if halftau1n<0 && tau2n<2
    error('Some tau coefficients are too small!');
end


%% MAIN FUNCTION BODY
% 1) SMOOTHING
% Symmetric windows are created. A mean value for the fluorescence is
% calculated for each window.
smthndTraces = rawImgSeries; % Initialization
for i=1:size(rawImgSeries,4)
    if i-halftau1n>0 && i+halftau1n<size(rawImgSeries,4) % We have to skip the first elements and also the last ones
        % The row i will be a mean of near values
        smthndTraces(:,:,:,i) = mean(rawImgSeries(:,:,:,i-halftau1n:i+halftau1n),4);
    elseif i-halftau1n<=0 && i+halftau1n<size(rawImgSeries,4)
        % This is to perform a reduced mean on the first part of the array
        smthndTraces(:,:,:,i) = mean(rawImgSeries(:,:,:,1:i+halftau1n) ,4);
    elseif i+halftau1n >= size(rawImgSeries,4) && i-halftau1n>0
        % This is to perform a reduced mean on the last part of the array
        smthndTraces(:,:,:,i) = mean(rawImgSeries(:,:,:,i-halftau1n:end) ,4);
    end
end

% 2) CALCULATION OF THE BASELINE with LOCAL MINIMUM VALUES
minF=smthndTraces; % Initialization
for i=tau2n:size(smthndTraces,4)
    % Looking for local mins
    % The window starts at index i-tau2n and ends at index i
    minF(:,:,:,i) = min(smthndTraces(:,:,:,i-tau2n+1:i),[],4);
end
% The first part of the min array will be equal to the first minimum found
minF(:,:,:,1:tau2n-1) = minF(:,:,:,tau2n).*ones(size(minF(:,:,:,1:tau2n-1)));

% 3) NOISE FILTERING
rawdFoF=(rawImgSeries-minF)./minF;
filtdFoF=rawdFoF; % Initialization
% If tau0 is zero, then the function skips the noise filtering.
if tau0>0
    for i=1:size(rawdFoF,4)
        weights = zeros(1,1,1,i);
        weights(1,1,1,:) = exp(-fliplr(sp*(0:i-1))/tau0);
        filtdFoF(:,:,:,i) = sum(rawdFoF(:,:,:,1:i).*weights/sum(weights),4);
    end
end

end
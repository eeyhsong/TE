function DataOut = Prepare(varargin)
%Prepare.m 处理初始数据集
% 检查输入数据和参数，同时优化嵌入参数，加入数据的一个子结构
% dataout=TEprepare(cfg, data)

% 用了几个Matlab的工具箱：
% TSTOOL 用于KSG estimator需要的最邻近搜索* DEPENDENCIES
% signal processing toolbox
% statistic toolbox
% parallel computing toolbox 用于分布式计算

% 用了如下几个函数：
%   TEactdetect
%   TEchannelselect
%   TEtrialselect
%   TEwait
%   TEconsoleoutput

% 注意数据不会自动保存，要单独实现

%% Remember the working directory

working_directory = pwd;

%% parse input
%  检查输入数据是否符合要求
%  输入数据包括两个部分，一部分是cfg，另一部分是data
%  存在toi和trial且两者是正常的结构
if isfield(varargin{1},'toi') && isstruct(varargin{1}) && isstruct(varargin{2}) && isfield(varargin{2},'trial')
    cfg =  varargin{1};
    data = varargin{2};
else
    error('\n TRENTOOL ERROR: incorrect input values, see help!');
end

%% define logging levels

LOG_INFO_MAJOR = 1;
LOG_INFO_MINOR = 2;
LOG_DEBUG_COARSE = 3;
LOG_DEBUG_FINE = 4;

if ~isfield(cfg, 'verbosity'), cfg.verbosity = 'info_minor'; end

%% check data

msg = 'Checking data and config';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

% check data using checkdata from Fieldtrip
[data] = ft_checkdata(data, 'datatype','raw');

% check whether time axes and trials have the same number of entries
if iscell(data.time) % one time axis per trial
    for tt=1:size(data.trial,2) % 此处检测每次trial的长度是否与时间长度对应
        if ~( size(data.time{tt},2) == size(data.trial{tt},2) )
            errorstr=strcat('TRENTOOL ERROR! incorrect number of samples in time axis or trial detected in trial Nr:',...
                num2str(tt),...
                ', samples: ',num2str(size(data.trial{tt},2)),...
                ', timeindices: ',num2str(size(data.time{tt},2)) );
            fprintf('\n')
            error(errorstr)
        end
    end
else % time is a single vector
    for tt=    size(data.trial,2)    % for each trial
        if ~( length(data.time) == size(data.trial{tt},2) )
            disp('in trial Nr: ')
            disp(num2str(tt))
            errorstr=strcat('TRENTOOL ERROR! incorrect number of samples in time axis or trial detected in trial Nr: ',num2str(tt));
            error(errorstr);
        end
    end
end

% check the data structure
if ~isfield(data, 'trial')
    fprintf('\n')
    error('TRENTOOL ERROR: data must be in ''.trial''-field, see help!');
end
if ~isfield(data, 'time')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.time''-field, see help!');
end
if ~isfield(data, 'label')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.label''-field, see help!');
end
if ~isfield(data, 'fsample')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.fsample''-field, see help!');
end

% for use of fMRI Data from the function TEnifti2TRENTOOL_3D
if isfield(data, 'datatype')
    TEprepare.datatype = data.datatype; % .datatype = 'fMRI'
    cfg.datatype = data.datatype;
    if ~isfield(data, 'outputtype')
        fprintf('\n')
        error('TRENTOOL ERROR: data contains no ''.outputdata''-field, see help!');
    else
        cfg.fmridatatype = data.outputtype;
    end
    if ~isfield(cfg, 'trialselect')   
        cfg.trialselect = 'no';    
    end
    if ~isfield(cfg, 'TheilerT')       
        cfg.TheilerT = 4;           
    end
    if ~isfield(cfg, 'embedding_delay_unit')       
        cfg.embedding_delay_unit = 'ACT';           
    end

    if strcmp(cfg.embedding_delay_unit,'Volumes')==0 && strcmp(cfg.embedding_delay_unit,'ACT')==0
        fprintf('\n')
        error('TRENTOOL ERROR: wrong input for cfg.embedding_delay_unit - see help!')
    end

    if strcmp(cfg.fmridatatype, '3DAsEmbed')
        if isfield(cfg, 'optimizemethod')
            fprintf('\n')
            error('TRENTOOL ERROR. No optimization can be used for the 3DAsEmbed data!')
        end
    end

    if strcmp(cfg.embedding_delay_unit,'Volumes')
        TEprepare.change_act = 1;

%         if strcmp(cfg.optimizemethod, 'cao') && ~isfield(cfg, 'tau')
%             cfg.caotau = 1;
%         else
        if strcmp(cfg.optimizemethod, 'cao') && isfield(cfg, 'tau')
            if mod(cfg.caotau,1)~=0
                fprintf('\n')
                error('TRENTOOL ERROR: in case of fMRI Data and cfg.embedding_delay_unit is not ''ACT'' cfg.caotau must be an integer number.')
            end
        elseif strcmp(cfg.optimizemethod, 'ragwitz')
            fprintf('\n')
            error('TRENTOOL ERROR: in case of fMRI Data and the use of ragwitz criterion cfg.embedding_delay_unit must be ''ACT''.')

%         elseif strcmp(cfg.fmridatatype, '3DAsEmbed')
%             if ~isfield(cfg, 'tau'),              cfg.caotau = 1;               end;
        end

    end

end


if size(data.time,1)>size(data.time,2) % size(X,DIM) 维度DIM的size
    data.time=data.time';
end


%% check configuration and set defaults

if ~isfield(cfg, 'trialselect')   ,   cfg.trialselect = 'ACT';         end
if ~isfield(cfg, 'maxlag'),           cfg.maxlag = 1000;               end
if ~isfield(cfg, 'TEcalctype')    ,   cfg.TEcalctype = 'VW_ds';        end
if ~isfield(cfg, 'ensemblemethod'),   cfg.ensemblemethod = 'no';       end
if ~isfield(cfg, 'minnrtrials')   ,   cfg.minnrtrials = 12;            end

%% check optimizemethod

%  注意看下Ragwitz criterion这篇文章
if ~isfield(cfg, 'optimizemethod'),  cfg.optimizemethod = 'ragwitz';   end

if strcmp(cfg.optimizemethod, 'ragwitz')

    % check input for ragwitz
    if ~isfield(cfg, 'ragtausteps'), cfg.ragtausteps = 10;  end

    if isfield(cfg, 'ragtausteps')
        if cfg.ragtausteps < 5
            warning(['\nTRENTOOL WARNING: cfg.ragtausteps is %d, it ' ...
                'should bigger than 5!'], cfg.ragtausteps)
        end
    else
        fprintf('\n')
        error('TRENTOOL ERROR: specify cfg.ragtaurange, see help!')
    end


    if length(cfg.ragtaurange) == 1

        cfg.ragtau = cfg.ragtaurange;

        if cfg.ragtausteps ~= 1
            fprintf('\n')
            warning('TRENTOOL WARNING: ragtaurange is a scalar, not using the number of ragtausteps specified in cfg.ragtausteps.');
        end

    elseif length(cfg.ragtaurange) == 2

        if cfg.ragtaurange(1) > cfg.ragtaurange(2)
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.ragtaurange must be a vector with increasing values!')
        end

        if size(cfg.ragtaurange,1)>size(cfg.ragtaurange,2)
            cfg.ragtaurange=cfg.ragtaurange';
        end

        % create cfg.ragtau vector
        if cfg.ragtaurange(1) == cfg.ragtaurange(2)
            cfg.ragtau = cfg.ragtaurange(1);
        else
            cfg.ragtau = unique(linspace(cfg.ragtaurange(1),cfg.ragtaurange(2),cfg.ragtausteps));
        end
    else
        fprintf('\n')
        error('TRENTOOL ERROR: cfg.ragtaurange is misspecified, should be a 1-by-2-array, see help!')
    end


    if ~isfield(cfg, 'ragdim'),
        cfg.ragdim = 1:10;
    else
        ragdimsort=sort(cfg.ragdim);
        if ragdimsort ~= cfg.ragdim
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.ragdim must be a vector with increasing values!')
        end

        if size(cfg.ragdim,1)>size(cfg.ragdim,2)
            cfg.ragdim=cfg.ragdim';
        end
    end;

elseif strcmp(cfg.optimizemethod, 'cao')

    if ~isfield(cfg, 'caokth_neighbors'), cfg.caokth_neighbors = 4;        end;
    if ~isfield(cfg, 'kth_neighbors'),  cfg.kth_neighbors = cfg.caokth_neighbors;  end;

    if ~isfield(cfg, 'tau'),              cfg.caotau = 1.5;               end;
    % check input for cao
    if ~isfield(cfg, 'caodim'),
        cfg.caodim = [1,2,3,4,5,6,7,8,9,10];
    else

        l=length(cfg.caodim);
        diff=zeros(l-1,1);

        if l > 1
            for ii = 2:l
                diff(ii-1)=cfg.caodim(ii)-cfg.caodim(ii-1);
            end
        end

        if any(diff~=1)
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.caodim must contain a row of numbers with stepwith 1, see help!');
        end

        if length(cfg.caodim) < 5
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.caodim must contain at least 5 entries, see help!');
        end
    end;

    if size(cfg.caodim,1)>size(cfg.caodim,2)
        cfg.caodim=cfg.caodim';
    elseif size(cfg.caotau,1)>size(cfg.caotau,2)
        cfg.caotau=cfg.caotau';
    elseif size(cfg.caokth_neighbors,1)>size(cfg.caokth_neighbors,2)
        cfg.caokth_neighbors=cfg.caokth_neighbors';
    end;

    fprintf('\n\nXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n');
    fprintf('XX                                                                        XX\n');
    fprintf('XX  THE CAO CRITERION IS DEPRECATED AS AN OPTION IN TRENTOOL VERSIONS 3.0   XX\n');
    fprintf('XX  AND HIGHER. SEE HELP.                                                 XX\n');
    fprintf('XX                                                                        XX\n');
    fprintf('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n\n');

    pause(10);

end;


%% check TE parameter
% -------------------------------------------------------------------------

if isempty(cfg.predicttime_u),
    fprintf('\n')
    error('TRENTOOL ERROR: specify cfg.predicttime_u, see help!');
elseif ~isscalar(cfg.predicttime_u)
    fprintf('\n')
    error('TRENTOOL ERROR: cfg.predicttime_u must be a scalar, see help!');
end


if ~isfield(cfg, 'kth_neighbors'),  cfg.kth_neighbors = 4;  end;

if ~isfield(cfg, 'TheilerT'),       cfg.TheilerT = 'ACT';   end;
if ~strcmp(cfg.TheilerT, 'ACT');
    if ~isscalar(cfg.TheilerT)
        fprintf('\n')
        error('TRENTOOL ERROR: cfg.TheilerT must be a scalar, see help!');
    end
end

if ~strcmp(cfg.TEcalctype,'VW_ds')
    fprintf('\n')
    error(['TRENTOOL ERROR: Please provide "VW_ds" as estimator in ' ...
        '"cfg.TEcalctype". Older/other estimators are no longer supported. See help!'])
end;


% check if channel or channelcombinations are defined
if ~isfield(cfg, 'channel') && ~isfield(cfg, 'sgncmb') ,
    fprintf('\n')
    error('TRENTOOL ERROR: specify cfg.channel OR cfg.sgncmb, see help!');
elseif isfield(cfg, 'channel') && isfield(cfg, 'sgncmb') ,
    fprintf('\n')
    error('TRENTOOL ERROR: specify cfg.channel OR cfg.sgncmb, see help!');
elseif isfield(cfg, 'channel') && ~isfield(cfg, 'sgncmb') ,
    if size(cfg.channel,2)>size(cfg.channel,1)
        cfg.channel=cfg.channel';
    end
    channelselect = 1;
    % a warning because of some issue if only a subselection of
    % channels enters the analysis -> PW: I removed this warning, I can't
    % find any issues
    %if max(size(cfg.channel))<size(data.trial{1},1) % If there are less channels
    %    fprintf('\nTRENTOOL WARNING: your are specifying a subselection of channels \n - please use cfg.sgncmb to specify channelcombinations directly');
    %end
elseif ~isfield(cfg, 'channel') && isfield(cfg, 'sgncmb') ,
    if size(cfg.sgncmb) ~= 2
        fprintf('\n')
        error('TRENTOOL ERROR: cfg.sgncmb has wrong dimensions, see help!');
    end
    channelselect = 2;
end;


% check the format of input vectors
if size(cfg.toi,1) > 2 || size(cfg.toi,2) >2
    fprintf('\n')
    error('TRENTOOL ERROR: cfg.toi has more than two entries');
end
if size(cfg.toi,1)>size(cfg.toi,2)
    cfg.toi=cfg.toi';
end



% check alternative ways of trial selection and the required related inputs
if strcmp(cfg.trialselect, 'ACT')
    if isempty(cfg.actthrvalue) || isempty(cfg.minnrtrials)
        fprintf('\n')
        error('TRENTOOL ERROR: specify cfg.actthrvalue and cfg.minnrtrials for ACT thresholding, see help!');
    end
elseif strcmp(cfg.trialselect, 'range')
    if isempty(cfg.trial_from) || isempty(cfg.trial_to)
        fprintf('\n')
        error('TRENTOOL ERROR: specify cfg.trial_from and cfg.trial_to for setting the range of used trials, see help!');
    end
end

par_state = check_set_parallel(cfg); %check for parallel and set the configuration



%% check if GPU-computation is requested and available on the system
% -------------------------------------------------------------------------

if strcmp(cfg.ensemblemethod, 'yes')

    [status, result] = system('nvidia-smi');
    if status~=0
        result = strrep(result, '%', '%%');
        fprintf(result);
        error('TRENTOOL ERROR: You requested ensemble method with GPU calculation. No Nvidia GPU could be detected on your system. See help!');
    end;
    clear status result;

    % set ensemble method, so InteractionDelayReconstruction_calculate can
    % switch to the appropriate version of TEsurrogatestats.m
    TEprepare.ensemblemethod = 'yes';
else
    TEprepare.ensemblemethod = 'no';
end

%% building channelpairs
% -------------------------------------------------------------------------
msg = 'Building channelpairs';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

% OUTPUT:   channelcombi      = nx2 matrix of indices of the channel
%                               combinations.
%           channelcombilabel = nx2 cell array of labels  of the channel
%                               combinations.
[channelcombi,channelcombilabel] = TEchannelselect(cfg, data, channelselect);
TEprepare.cfg.channelcombi = channelcombi;
TEprepare.cfg.channelcombilabel = channelcombilabel;

TEprepare.channelcombi=channelcombi;
TEprepare.channelcombilabel=channelcombilabel;

% remember individual channel label for group statistics
TEprepare.channellabel = data.label;

TEconsoleoutput(cfg.verbosity, channelcombilabel, LOG_INFO_MINOR, 'Channelcombinations:');

%% read data
% -------------------------------------------------------------------------
msg = 'Reading data';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

% create datacell {channelcombi x 2} including the matrix (trial x
% timepoints) for each channel.
datacell = cell(size(channelcombi,1),2);
for cc = 1:size(channelcombi,1)
    for pp = 1:2
        datamat = zeros(size(data.trial,2),size(data.trial{1},2));
        for ii = 1:size(data.trial,2)
            datamat(ii,:)=data.trial{ii}(channelcombi(cc,pp),:);
        end
        datacell{cc,pp}=datamat;
        clear datamat;
    end
end


% read time values of the data
if iscell(data.time)
    alltime=cell2mat(data.time(1));
else
    alltime=data.time;
end

% find correct indices for the samples in alltime/cfg.toi
% to be used later
% look in the time dimension of the data
timeindices=zeros(1,2);
for ii = 1:size(cfg.toi,2)
    [col]=nearest(alltime, cfg.toi(ii));
    timeindices(ii)=col;
end

% check if indices make sense
if timeindices(1) >= timeindices(2)
    error(['TRENTOOL ERROR: Something seems to be wrong with your ' ...
        'time indices %d and %d: time index 1 >= time index 2!'], ...
        timeindices(1), timeindices(2))
else
    TEprepare.timeindices = timeindices;
    msg = sprintf('Time indices are %.0f and %.0f',timeindices(1),timeindices(2));
    TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
end

%% define ACT and trials
% ------------------------------------------------------------------------

% calculate ACT
TEconsoleoutput(cfg.verbosity, 'Calculating ACT', LOG_INFO_MINOR);
[ACT]=TEactdetect(datacell,cfg.maxlag,timeindices);
if isfield(data, 'datatype')
    if strcmp(data.datatype, 'fMRI') && strcmp(cfg.embedding_delay_unit, 'Volumes')
        ACT(:,:,:) = 1;
        msg = 'TRENTOOL WARNING: In case of using fMRI data using with cao and cfg.embedding_delay_unit=''Volumes'' the ACT values are set to 1!';
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
    end
end
TEprepare.ACT=ACT;

% select trials
TEconsoleoutput(cfg.verbosity, 'Selecting trials', LOG_INFO_MINOR);
[trials,nrtrials]=TEtrialselect(cfg,datacell,ACT,channelcombi);
TEprepare.trials=trials;
TEprepare.nrtrials=nrtrials;
TEprepare.maxact = 0;
for i=1:size(channelcombi,1)
    TEprepare.maxact=max(TEprepare.maxact,max(max(squeeze(ACT(i,2,trials{i,2})))));
end

% convert u value from ms to sampling points
dimu = round(cfg.predicttime_u/1000*data.fsample);
TEprepare.u_in_samples = dimu;

% if the user scans over u, use the maximum requested u-value to determine
% the no. sample points left after embedding
if isfield(cfg,'predicttimemax_u')
    dimu_max = round(cfg.predicttimemax_u/1000*data.fsample);
    TEprepare.max_u_in_samples = dimu_max;
else
    dimu_max = dimu;
end

%% optimize embedding parameters
% -------------------------------------------------------------------------


% Ragwitz criterion
% ------------------

if isfield(cfg, 'datatype')
    if strcmp(cfg.datatype, 'fMRI') && strcmp(cfg.fmridatatype, '3DAsEmbed')
        fprintf('\n')
        warning('WarnTests:convertTest',...
            'No optimization will be performed! TEprepare.optdim will be defined by the number of surrounding voxels specified in Data.Data4Embedding!!!!')
        TEprepare.optdim = size(Data.Data4Embedding{1},2);
    end
else

    if strcmp(cfg.optimizemethod, 'ragwitz') == 1

        % define channel on which ragwitz is performed
        targetchannel = 2; % this is index of the target channel in the matrices


        % define max tau in samples
        maxact = min([max(max(ACT(:,targetchannel,:))) cfg.actthrvalue]);
        maxtau = ceil( maxact * max(cfg.ragtau) );
        emb_length = (max(cfg.ragdim)-1)*maxtau;
        avail_samples = TEprepare.timeindices(2)-TEprepare.timeindices(1);
        if strcmp(cfg.TheilerT, 'ACT');
            theiler_corr = maxact;
        else
            theiler_corr = cfg.TheilerT;
        end
        rem_samples = avail_samples - theiler_corr - emb_length - dimu_max;
        msg = {...
            'theiler corr.' num2str(theiler_corr); ...
            'embedding legth' num2str(emb_length); ...
            'delay u' num2str(dimu_max); ...
            'available samples' num2str(avail_samples); ...
            'remaining samples' num2str(rem_samples); ...
            'cfg.repPred' num2str(cfg.repPred); ...
            };
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR, 'Required no. samples for TE estimation:');

        % check if enough data points for embedding exist
        if cfg.repPred >= rem_samples
            fprintf('\n')
            error(['TRENTOOL ERROR: Not enough points in timeseries ' ...
                'for current analysis settings (cfg.repPred > remaining ' ...
                'samples), reduce one of the following: cfg.repPred, ' ...
                'ACT/Theiler T, embedding length (max(cfg.ragdim)-1*max(cfg.ragtaurange)) ' ...
                ', or maximum delay u.']);
        end

        msg = 'Optimizing embedding parameters using Ragwitz'' criterion';
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

        % create matrices with nans
        optdim = nan(size(channelcombi,1),max(nrtrials(:,targetchannel)));
        opttau = nan(size(channelcombi,1),max(nrtrials(:,targetchannel)));
        opttau_act = nan(size(channelcombi,1),max(nrtrials(:,targetchannel)));

        % create vector of time points of interest (toi)
        toi=timeindices(1):timeindices(2);
        %     T=length(toi);

        % create comand line waitbar
        TEwaitbar('init', size(channelcombi,1), cfg.verbosity);

%-------------------------------------------------------------------------------
        for channel = 1:size(channelcombi,1) % loop over used channels

            TEwaitbar('update', channel, cfg.verbosity);

            if ~par_state
               for nt = 1:nrtrials(channel,targetchannel) % loop over trials

                    if strcmp(cfg.TheilerT, 'ACT');
                        TheilerT = ACT(channel,2,trials{channel,targetchannel}(nt));
                    else
                        TheilerT = cfg.TheilerT;
                    end

                    dat=squeeze(datacell{channel,targetchannel}(trials{channel,targetchannel}(nt),toi));
                    mre = nan(length(cfg.ragdim),length(cfg.ragtau)); % error matrix

                    % loop over ragdim and ragtau
                    for rd = 1:length(cfg.ragdim)
                        for rt = 1:length(cfg.ragtau)

                            tau_sample = round(ACT(channel,2,trials{channel,targetchannel}(nt)) * cfg.ragtau(rt));
                            if tau_sample < 1
                                tau_sample = 1;
                            end

                            [mre(rd,rt)] = TEragwitz(cfg,dat,cfg.repPred,1,cfg.flagNei,cfg.sizeNei,cfg.ragdim(rd),tau_sample,TheilerT,max(cfg.ragdim),maxtau);
                        end
                    end

                    if size(mre,2) > 2 % if we can convolve with the kernel
                        Smin = eye(size(cfg.ragtau,2)-1);
                        S = eye(size(cfg.ragtau,2));
                        S(2:end, 1:end-1) = S(2:end, 1:end-1) + Smin;
                        S(1:end-1, 2:end) = S(1:end-1, 2:end) + Smin;
                        S(3, 1) = 1;
                        S(end-2, end) = 1;
                        Smoothedmre = (mre * S) ./ 3;
                    else % ... forget about smoothing
                        Smoothedmre = mre;
                    end

                    [optdimidx, opttauidx] = find(Smoothedmre == min(min(Smoothedmre)));
                    optdim(channel,nt) = cfg.ragdim(min(optdimidx));
                    opttau(channel,nt) = cfg.ragtau(min(opttauidx));

                end
            else
                aux_optdim= nan(1,nrtrials(channel,targetchannel));
                aux_opttau= nan(1,nrtrials(channel,targetchannel));
                parfor nt = 1:nrtrials(channel,targetchannel) % loop over trials

                    % define trainingpoints for Ragwitz criteria depending on
                    % TheilerT
                    if strcmp(cfg.TheilerT, 'ACT');
                        TheilerT = ACT(channel,2,trials{channel,targetchannel}(nt));
                    else
                        TheilerT = cfg.TheilerT;
                    end

                    % get trial data from data matrix
                    dat=squeeze(datacell{channel,targetchannel}(trials{channel,targetchannel}(nt),toi));

                    %create emtpy result matrix with nans
                    mre = nan(length(cfg.ragdim),length(cfg.ragtau));


                    % loop over ragdim and ragtau
                    for rd = 1:length(cfg.ragdim)
                        for rt = 1:length(cfg.ragtau)
                            tau_sample = round(ACT(channel,2,trials{channel,targetchannel}(nt)) * cfg.ragtau(rt));
                            if tau_sample < 1
                                tau_sample = 1;
                            end

                            [mre(rd,rt)] = TEragwitz(cfg,dat,cfg.repPred,1,cfg.flagNei,cfg.sizeNei,cfg.ragdim(rd),tau_sample,TheilerT,max(cfg.ragdim),maxtau);
                        end
                    end

                    if size(mre,2) > 2 % if we can convolve with the kernel
                        Smin = eye(size(cfg.ragtau,2)-1);
                        S = eye(size(cfg.ragtau,2));
                        S(2:end, 1:end-1) = S(2:end, 1:end-1) + Smin;
                        S(1:end-1, 2:end) = S(1:end-1, 2:end) + Smin;
                        S(3, 1) = 1;
                        S(end-2, end) = 1;
                        Smoothedmre = (mre * S) ./ 3;
                    else % ... forget about smoothing
                        Smoothedmre = mre;
                    end

                    [optdimidx, opttauidx]= find(Smoothedmre == min(min(Smoothedmre)));
                    %optdim(channel,nt) = cfg.ragdim(min(optdimidx));
                    %opttau(channel,nt) = cfg.ragtau(min(opttauidx));
                    aux_optdim(nt) = cfg.ragdim(min(optdimidx));
                    aux_opttau(nt) = cfg.ragtau(min(opttauidx));

                end
                optdim(channel,:) = aux_optdim;
                opttau(channel,:) = aux_opttau;
            end
        end
%---------------------------------------------------------------------------

% PW 30/05/2014 bugfix: we don't need these loops, opttau doesn't need any
% conversion -> this causes TEprepare to always choose the smalles ragtau
%
%         % tau from samples to multiples of ACT
%         for channel = 1:size(channelcombi,1)
%             for nt = 1:nrtrials(channel,targetchannel)
%                 tauinact = opttau(channel,nt) ./ ACT(channel,2,nt);
%                 [tauindex]=nearest(cfg.ragtau, tauinact);
%                 opttau_act(channel,nt) =  cfg.ragtau(tauindex);
%             end
%         end
        opttau_act = opttau;

        % find max tau
        % TEprepare.opttaumat includes a vector with the maximum tau for
        % each channel combination
        TEprepare.opttaumat = max(opttau_act,[],2);
        TEprepare.opttaumattrial = opttau_act;
% PW 30/05/2014 bugfix: I don't think this is needed (and probably wrong?), we
% just keep the max. ragtau as the tau for the whole data set
%         [chanidx, trialidx] = find(opttau_act == max(max(opttau_act)));
%         opttaumultiplier = opttau_act(min(chanidx), min(trialidx));	% PW: the two min functions choose an arbitrary value in ottau_act?
%         % TEprepare.opttau includes a scalar with the maximum tau for
%         % all channel combinations
%         TEprepare.opttau = opttaumultiplier;
        TEprepare.opttau = max(max(opttau_act));

% PW 30/05/2014 bugfix:
%        fprintf(strcat(['\nOptimal tau for this dataset may be: ', num2str(opttaumultiplier),'\n']))
        msg = sprintf('Optimal tau for this dataset is: %.2f', TEprepare.opttau);
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

        % find max dimension
        % TEprepare.optdimmat includes a vector with the maximum (over trials) dimension for
        % each channel combination
        TEprepare.optdimmattrial = optdim;

        TEprepare.optdimmat = max(optdim,[],2);
        % TEprepare.optdim includes a scalar with the maximum dimension for
        % all channel combinations
        TEprepare.optdim = max(max(optdim));
        msg = sprintf('Optimal dimension for this dataset is: %d', max(max(optdim)));
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);



    % Cao criterion
    % --------------
    elseif strcmp(cfg.optimizemethod, 'cao') == 1

        msg = '\nOptimization using cao criteria\n';
        TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

        % Change to directory containing mex files for the nearest neighbors search
        %[dir_mex] = TEarch(cfg);
        %cd(dir_mex);
        TEarch;


        % scan dimensions for each channel and trial
        % -------------------------------------------------------------------------
        maxdim = max(cfg.caodim)+1;
        TEprepare.nrreferencepoints=zeros(size(datacell,1),size(datacell{1,1},1));
        optdim=zeros(size(datacell,1),maxdim-1);

        % channel of the channelpair used to calculate for: 2 = target channel
        targetchannel = 2; % this is index of the target channel in the matrices

        ch_count = 0;
        for chanpair = 1:size(channelcombi,1) %
            ch_count = ch_count +1;

            nt_count = 0;
            for nt = 1:nrtrials(chanpair,targetchannel)
                nt_count = nt_count +1;


                dat = squeeze(datacell{chanpair,targetchannel}(nt,timeindices(1)+1:timeindices(2)));
                tau = ceil(cfg.caotau*squeeze(ACT(chanpair,2,trials{chanpair,2}(nt))));

                % embedding
                T = length(dat);     % length of full time series
                M = T-(maxdim-1)*tau; % number of points inside the time series ready for delay embedding
                query = (1:M);

                if M < 1
                    error(strcat(['TRENTOOL ERROR: maximum caodim (',num2str(max(cfg.caodim)),') is to high for channel ',channelcombilabel{chanpair,targetchannel}]))
                end

                caodimadded = [cfg.caodim ,max(cfg.caodim)+1];

                pointset = zeros(M,maxdim);
                for ii = 1:M
                    for jj = caodimadded
                        pointset(ii,jj) = dat(ii+(maxdim-1)*tau-(jj-1)*tau);
                    end
                end
                TEprepare.nrreferencepoints(chanpair,nt)=size(pointset,1);

                % calculate cao
                [E,Ex]=cao(pointset,query,cfg.caokth_neighbors);

                % calculate E1 and E2
                E1(chanpair,nt,:)=E(2:end)./E(1:end-1);
                E2(chanpair,nt,:)=Ex(2:end)./Ex(1:end-1);

                % change because cao !!!!!!!!!!!!!!!!!
                %E1der2=zeros(1,maxdim-2);
                %for kk = 2:maxdim-2
                E1der2=zeros(1,maxdim-3);
                for kk = 2:maxdim-3
                    E1der2(kk) = E1(chanpair,nt,kk-1)+E1(chanpair,nt,kk+1)-2*E1(chanpair,nt,kk);
                end
                optdim(chanpair,nt)=find(E1der2==min(E1der2), 1 );
            end
        end

        % find max dimension
        TEprepare.optdimmat = max(optdim,[],2);
        TEprepare.optdim = max(max(optdim));

        if max(max(optdim)) == max(cfg.caodim)
            error(['\nTRENTOOL ERROR: Optimal dimension found (%d) is the ' ...
                'highest in cfg.caodim. Rerun the data with higher ' ...
                'values for cfg.caodim!'], max(max(optdim)))
        else
            msg = sprintf('Optimal dimension for this dataset may be: %d', max(max(optdim)));
            TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
        end

        TEprepare.cao.E1=E1;
        TEprepare.cao.E2=E2;

    end

    if strcmp(cfg.optimizemethod, 'nonuniformMuTE') == 1
        TEprepare.embeddingMtx = nonUniformEmbedding_MuTE(cfg,TEprepare,data);
        warning('TRENTOOL_DEV: Return after estimating embedding points with MuTE!');
        return
    end

end


cd(working_directory)




%% add TEprepare structure to the data
% -------------------------------------------------------------------------
msg = 'Adding TEprepare structure to original data structure';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

TEprepare.cfg=cfg;
varargin{2}.TEprepare = TEprepare;
DataOut = varargin{2};


end

function par_state = check_set_parallel(cfg)

if isfield(cfg,'TEparallel') && ft_hastoolbox('DCT') && isfield(cfg.TEparallel,'parON') && strcmp(cfg.TEparallel.parON,'yes')

    par_state = 1;
    parallelConfig = findResource('scheduler','configuration',defaultParallelConfig);
    %parallelConfig = parcluster(parallel.defaultClusterProfile);
    max_workers = parallelConfig.ClusterSize;
    if ~isfield(cfg.TEparallel,'workers')
        cfg.TEparallel.workers = max_workers;
    end

    if  matlabpool('size')== 0

        if cfg.TEparallel.workers <= max_workers
            matlabpool(cfg.TEparallel.workers)
        else
            matlabpool(max_workers)
        end

    else if matlabpool('size') > cfg.TEparallel.workers
            matlabpool close;
            matlabpool(cfg.TEparallel.workers)
        end
    end
else
    par_state = 0;
end

end
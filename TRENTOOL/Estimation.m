function TEpermtest = Estimation(cfg,data)

%% Estimation 计算传递熵
% 计算传递熵的值，后在两个传递熵数据集上进行一次组合（原始的和替代的）
% TEsurrogatestats(cfg, data)

% % 用了几个Matlab的工具箱：
% TSTOOL 用于KSG estimator需要的最邻近搜索
% signal processing toolbox
% statistic toolbox
% 用了如下几个函数：
%  - TEprepare
%  - transferentropy
%  - TEactdetect
%  - TEchannelselect
%  - TEcmc
%  - TEperm
%  - TEtrialselect
%  - TEvalues
%  - TEwait
%  - TEconsoleoutput
%
% 用到了Faes Method的无需进行shift test

%% Remember the working directory

working_directory1 = pwd;

%% check if TEprepare was performed

if ~isfield(data, 'TEprepare')
    fprintf('\n')
    error('TRENTOOL ERROR: The function TEprepare must be performed on the data, see help!');
end

%% define logging levels

LOG_INFO_MAJOR = 1;
LOG_INFO_MINOR = 2;
verbosity = data.TEprepare.cfg.verbosity;

%% check data

TEconsoleoutput(verbosity, 'Checking data and config', LOG_INFO_MINOR);

% check data using checkdata from Fieldtrip
[data] = ft_checkdata(data, 'datatype','raw');

% check the data structure
if ~isfield(data, 'trial')
    fprintf('\n')
    error('TRENTOOL ERROR: data must be in ''.trial''-structure, see help!');
end
if ~isfield(data, 'time')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.time''-structure, see help!');
end
if ~isfield(data, 'label')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.label''-structure, see help!');
end
if ~isfield(data, 'fsample')
    fprintf('\n')
    error('TRENTOOL ERROR: data contains no ''.fsample''-structure, see help!');
end
if size(data.time,1)>size(data.time,2)
    data.time=data.time';
end

% compare new cfg and cfg from TEprepare if equal fields exist

doublefields = 0;
cfgTEprepare = data.TEprepare.cfg;

cfgfields = fieldnames(cfgTEprepare);
cfgfields2 = fieldnames(cfg);

for ii = 1:size(cfgfields,1)
    for jj = 1:size(cfgfields2,1)
        if strcmp(cfgfields{ii},cfgfields2{jj})
            doublefields = doublefields + 1;
            disp('---- The following field is being overwritten:')
            disp(cfgfields{ii})
        end
    end
end

clear cfgTEprepare

if doublefields  > 0
    fprintf('\n')
    error('TRENTOOL ERROR: Illegal attempt to overwrite entry generated by or used for TEprepare! Change cfg or rerun TEprepare. (see help)')
end

% add structures and values of data.TEprepare.cfg to cfg
names1 = fieldnames(data.TEprepare.cfg);
nr1 = size(names1,1);
for ii = 1:nr1
    eval(strcat('cfg.',names1{ii},' = getfield(data.TEprepare.cfg, {1}, names1{ii});'))
end

% check configuration and set defaults

% if not defined set defaults
if ~isfield(cfg, 'alpha'),          cfg.alpha = 0.05;           end
if ~isfield(cfg, 'correctm'),       cfg.correctm = 'FDR';       end
if ~isfield(cfg, 'tail'),           cfg.tail = 1;               end
if ~isfield(cfg, 'extracond'),      cfg.extracond = 'none';     end

if ~isfield(cfg, 'permstatstype'),  cfg.permstatstype = 'mean'; end
if strcmp(cfg.permstatstype , 'mean') == 0 && strcmp(cfg.permstatstype , 'normmean') == 0 && strcmp(cfg.permstatstype , 'indepsamplesT') == 0 && strcmp(cfg.permstatstype , 'depsamplesT') == 0
    fprintf('\n')
    error('TRENTOOL ERROR: wrong cfg.permstatstype - use ''mean'' ''normmean'' ''depsamplesT'' or ''indepsamplesT'', see help!');
end

if ~isfield(cfg, 'shifttest'),  cfg.shifttest = 'yes'; end
if strcmp(cfg.shifttest , 'yes') == 0 && strcmp(cfg.shifttest , 'no') == 0
    fprintf('\n')
    error('TRENTOOL ERROR: wrong cfg.shifttest - use ''yes'' or ''no'', see help!');
end
% check whether, Faes method and shift test are requested, this is not
% allowed
if strcmp(cfg.shifttest , 'yes')  && strcmp(cfg.extracond , 'Faes_Method')
    fprintf('\n')
    error('TRENTOOL ERROR: you requested Faes method AND the conduction of a shift test. Set "cfg.shifttest = no" as Both methods are mutually exclusive, see help!');
end
if strcmp(cfg.shifttest , 'yes')
    if ~isfield(cfg, 'shifttype'),    cfg.shifttype = 'predicttime';        end
    if ~isfield(cfg, 'shifttesttype'),  cfg.shifttesttype = 'TE > TEshift'; end
    if strcmp(cfg.shifttesttype , 'TE>TEshift') == 0 && strcmp(cfg.shifttesttype , 'TEshift>TE') == 0
        fprintf('\n')
        error('TRENTOOL ERROR: wrong cfg.shifttesttype - use ''TE>TEshift'' or ''TEshift>TE'', see help!');
    end
end

if ~isfield(cfg, 'fileidout')
    fprintf('\n')
    error('TRENTOOL ERROR: cfg.fileidout must be defined, see help!');
end

% check optimizemethod
if ~isfield(cfg, 'optdimusage')
    fprintf('\n')
    error('TRENTOOL ERROR: cfg.optdimusage is not defined, see help!')
else
    if strcmp(cfg.optdimusage, 'maxdim') == 0 && strcmp(cfg.optdimusage, 'indivdim') == 0
        fprintf('\n')
        error(['TRENTOOL ERROR: ',cfg.optdimusage,' is a wrong input for cfg.optdimusage , see help!'])
    end
end

% check dim
if ~isfield(cfg, 'dim')
    if strcmp(cfg.optdimusage, 'indivdim')
        cfg.dim = data.TEprepare.optdimmat;
%         cfg.optdimusage = cfg.optdimusage;
    else
        cfg.dim(1:size(data.TEprepare.optdimmat,1),1) = data.TEprepare.optdim;
%         cfg.optdimusage = cfg.optdimusage;
    end
else
    if strcmp(cfg.optdimusage, 'indivdim')
        if size(cfg.dim,1) ~= size(data.TEprepare.channelcombi,1)
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.dim has to be in that size: (channelcombi x 1), see help!')
        elseif size(cfg.dim,2)>1
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.dim has to be in that size: (channelcombi x 1), see help!')
        end
    else
        if size(cfg.dim,1)>1 && size(cfg.dim,2)>1
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.dim must include a scalar, see help!');
        end
        if cfg.dim < data.TEprepare.optdim
            warning(['\nTRENTOOL WARNING: embedding dimension ' ...
                'specified in cfg.dim (=%d) is smaller than the optimal ' ...
                'dimension found by TEprepare (%d).'], ...
                cfg.dim, data.TEprepare.optdim)
        elseif cfg.dim > data.TEprepare.optdim
            warning(['\nTRENTOOL WARNING: embedding dimension ' ...
                'specified in cfg.dim (=%d) is bigger than the optimal ' ...
                'dimension found by TEprepare (%d).'], ...
                cfg.dim, data.TEprepare.optdim)
        end
    end
end

% check tau
if ~isfield(cfg, 'tau')
    if strcmp(data.TEprepare.cfg.optimizemethod, 'ragwitz')
        if strcmp(cfg.optdimusage, 'indivdim')
            cfg.tau = data.TEprepare.opttaumat;
        else
            cfg.tau(1:size(data.TEprepare.channelcombi,1)) = data.TEprepare.opttau;
        end
    elseif strcmp(data.TEprepare.cfg.optimizemethod, 'cao')
        cfg.tau(1:size(data.TEprepare.channelcombi,1)) = data.TEprepare.cfg.caotau;
    end

else
    if strcmp(cfg.optdimusage, 'indivdim') && strcmp(data.TEprepare.cfg.optimizemethod, 'ragwitz')
        if size(cfg.tau,1) ~= size(data.TEprepare.channelcombi,1)
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.tau has to be in that size: (channelconmbi x 1), see help!')
        elseif size(cfg.tau,2)>1
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.tau has to be in that size: (channelconmbi x 1), see help!')
        end
    else
        if size(cfg.tau,1)>1 && size(cfg.tau,2)>1
            fprintf('\n')
            error('TRENTOOL ERROR: cfg.tau must include a scalar, see help!');
        end
    end

end

% check TE parameter
if isempty(cfg.predicttime_u)
    error('TRENTOOL ERROR: specify cfg.predicttime_u, see help!');
elseif length(cfg.predicttime_u) == 1
    cfg.predicttime_u = repmat(cfg.predicttime_u, size(data.TEprepare.channelcombi,1), 1);
elseif length(cfg.predicttime_u) ~= size(data.TEprepare.channelcombi,1)
    error('TRENTOOL ERROR: cfg.predicttime_u should either be a scalar or a vector of size [n channel combinations X 1], see help!');
end

if ~isfield(cfg, 'kth_neighbors'),  cfg.kth_neighbors = 4;  end

if ~isfield(cfg, 'TheilerT'),       cfg.TheilerT = 'ACT';   end
if ~strcmp(cfg.TheilerT, 'ACT')
    if size(cfg.TheilerT,1)>1 || size(cfg.TheilerT,2)>1
        fprintf('\n')
        error('TRENTOOL ERROR: cfg.TheilerT must include a scalar, see help!');
    end
end

% check the format of input vectors
if size(cfg.toi,1)>size(cfg.toi,2)
    cfg.toi=cfg.toi';
elseif size(cfg.predicttime_u,1)>size(cfg.predicttime_u,2)
    cfg.predicttime_u=cfg.predicttime_u';
elseif size(cfg.kth_neighbors,1)>1 || size(cfg.kth_neighbors,2)>1
    fprintf('\n')
    error('TRENTOOL ERROR: cfg.dim must include a scalar, see help!');
end

%% get channels, ACT and trials from the cfg.TEprepare

cfg.permtest.channelcombi = data.TEprepare.channelcombi;
cfg.permtest.channelcombilabel = data.TEprepare.channelcombilabel ;
cfg.permtest.ACT=data.TEprepare.ACT;

% select trials
trials=data.TEprepare.trials;
nrtrials=data.TEprepare.nrtrials;
cfg.permtest.trials=trials;
cfg.permtest.nrtrials=nrtrials;

%% check nr of permutations

msg = 'Checking number of permutations';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

if isfield(cfg, 'numpermutation') && strcmp(cfg.numpermutation, 'findDelay')
    cfg.numpermutation = 0;
    cfg.shifttest = 0;
else
    cfg.numpermutation = TEchecknumperm(cfg, size(cfg.permtest.channelcombi, 1), min(nrtrials(:,2)), min(nrtrials(:,2)));
end

%% start calculating TE

warning('off','all')        % otherwise parfor loops throw warnings
cfg.calctime = 'yes';

% for unshuffled data
% ----------------------
msg = 'Calculating transfer entropy for unshuffled data...';
TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
cfg.shuffle = 'no';
[TEresult] = transferentropy(cfg,data);
TEresult.TEprepare = data.TEprepare;

% %$ML
% save(strcat(cfg.fileidout,'_TEresultorig'), 'TEresult','-v7.3');

cfg.calctime = 'no';

% for shifted data
% ----------------------
% TEshift is created inside transferentropy.m as a reduced version of
% TEresult without certain fields. TEshift is never written to disk/file
% to avoid later confusion. Please save TEshift yourself if necessary.
if strcmp(cfg.shifttest, 'yes')
    msg = 'Calculating transfer entropy for shifted data';
    TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);

    cfg.shuffle = 'no';
    [TEshift] = transferentropy(cfg,data,'shifttest');

%     %$ML
%     save(strcat(cfg.fileidout,'_TEshift'), 'TEshift','-v7.3');


    % permutation test for shift test
    msg = 'Start permutation tests for shift test';
    TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
    permstatstype = cfg.permstatstype;
    cfg.permstatstype = 'indepsamplesT';
    tailtype = cfg.tail;
    cfg.tail = 1;
    if strcmp(cfg.shifttesttype, 'TE > TEshift')
        alpha = cfg.alpha;
        cfg.alpha = 0.05;
        TEpermshift = TEperm(cfg,TEresult,TEshift);
        cfg.alpha = alpha;
    elseif strcmp(cfg.shifttesttype, 'TEshift > TE')
        alpha = cfg.alpha;
        cfg.alpha = 0.1;
        TEpermshift = TEperm(cfg,TEshift,TEresult);
        cfg.alpha = alpha;
    end
    cfg.permstatstype = permstatstype;
    cfg.tail=tailtype;

%     %$ML
%     save(strcat(cfg.fileidout,'_TEpermshift'), 'TEpermshift','-v7.3');

    % analyze shift test
    TEconsoleoutput(cfg.verbosity, 'Analyzing shift test', LOG_INFO_MINOR);

    % MW: check if there are NaNs in TEresult from errors in
    % transferentropy
    NaNidx=find(isnan(TEresult.TEmat));
    if ~isempty(NaNidx)
        fprintf('\n')
        warning('TRENTOOL WARNING: Found NaN in TEresult.TEmat! Aborting')
        return
    end


    if strcmp(cfg.shifttesttype, 'TE>TEshift')
        indexinstmix = find(TEpermshift.TEpermvalues(:,2)==0);
        if size(indexinstmix,1) == 0
            msg = 'No instantaneous mixing found';
            TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
        else
            msg = sprintf('%d instantaneous mixings found by strict shifttest!\nFor these cases TEvalues of all trials are set to NaN!\n', size(indexinstmix,1));
            TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
            mask=repmat((TEpermshift.TEpermvalues(:,2)-1)*-1, [1 1 size(TEresult.TEmat,2)]);
            TEresult.TEmat(mask==1) = NaN;
            TEresult.MImat(mask==1) = NaN;
            clear mask;
            TEresult.instantaneousmixing = (TEpermshift.TEpermvalues(:,2)-1)*-1;
        end
    elseif strcmp(cfg.shifttesttype, 'TEshift>TE')
        indexinstmix = find(TEpermshift.TEpermvalues(:,2)==1);
        if size(indexinstmix,1) == 0
            msg = 'No instantaneous mixing found';
            TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
        else
            msg = sprintf('%d instantaneous mixings found by strict shifttest!\nFor these cases TEvalues of all trials are set to NaN!\n', size(indexinstmix,1));
            TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
            mask=repmat(TEpermshift.TEpermvalues(:,2), [1 1 size(TEresult.TEmat,2)]);
            TEresult.TEmat(mask==1) = NaN;
            TEresult.MImat(mask==1) = NaN;
            clear mask;
            TEresult.instantaneousmixing = TEpermshift.TEpermvalues(:,2);
        end
    end

    clear TEpermshift
end

% for shuffled data
% ----------------------
% TEshuffle is created inside transferentropy.m as a reduced version of
% TEresult without certain fields. TEshuffle is never written to disk/file
% to avoid later confusion. Please save TEshuffle yourself if necessary.
if cfg.numpermutation > 0
    msg = 'Calculating transfer entropy for shuffled data';
    TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
    cfg.shuffle = 'yes';
    [TEshuffle] = transferentropy(cfg,data);
    cfg = rmfield(cfg, 'shuffle');
    msg = 'Starting permutation tests';
    TEconsoleoutput(cfg.verbosity, msg, LOG_INFO_MINOR);
    TEpermtest = TEperm(cfg,TEresult,TEshuffle);
    TEpermtest.TEmat_sur = TEshuffle.TEmat;
    cfg.correctm = TEpermtest.correctm;
    TEpermtest = rmfield(TEpermtest, 'correctm');
else
    TEpermtest = [];
end
cfg = rmfield(cfg, 'calctime');

%     %$ML
%    save(strcat(cfg.fileidout,'_TEshuffle'), 'TEshuffle','-v7.3');

warning('on','all')

%% permutation tests

TEpermtest.dimord = 'chanpair_value';
TEpermtest.cfg = cfg;
TEpermtest.ACT.actvalue = data.TEprepare.ACT;
TEpermtest.sgncmb = TEresult.sgncmb;
TEpermtest.numpermutation = cfg.numpermutation;
TEpermtest.TEprepare = data.TEprepare;
TEpermtest.TEmat = TEresult.TEmat;
TEpermtest.MImat = TEresult.MImat;

%% save results

% fprintf('\nSaving ...')
% fprintf('\n\tresults of TE estimation')
% save(strcat(cfg.fileidout,'_time',num2str(cfg.toi(1)),'-',num2str(cfg.toi(2)),'s_TE_output.mat'), 'TEresult','-v7.3');
% fprintf(' - ok');
% fprintf('\n\tresults of permutation test')
% save(strcat(cfg.fileidout,'_time',num2str(cfg.toi(1)),'-',num2str(cfg.toi(2)),'s_TEpermtest_output.mat'), 'TEpermtest','-v7.3');
% fprintf(' - ok');

%% Returning to the working directory

cd(working_directory1)

return;


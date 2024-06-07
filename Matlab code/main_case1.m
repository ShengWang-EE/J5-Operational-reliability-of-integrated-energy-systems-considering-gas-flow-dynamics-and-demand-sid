clear
clc
%% 1 data input
% ----- 1.1 general paras -----
missionTime = 12; % �����������ʱ��ʱ��
ND = 48; % 15min interval ���ϵ���ʱ��ʱ����
dd = missionTime / ND;
NK = 48; % 15min time step ��Ȼ����̬����ʱ�䲽��
dt = missionTime / NK;
KK = 0:dt:missionTime;
simulationTimes = 100000; % TSMCS ����

% ----- 1.2 IEGS para ------
[mpc0, gtd] = case24GEv5(); mpc = mpc0; % physical para
rts = Case24ReliabillityDatav3(); % reliability parameters
% preprocess: Ҫ�ѷ��������Ȼ��Դ�ĳ�������ȡ������Ȼ����̫С��ʱ����������Ҫ�ǵ����ࣩ
mpc0.gen(:,10) = 0; 
%
nb   = size(mpc.bus, 1);    %% number of buses
nGb  = size(mpc.Gbus,1); % number of gas bus
nEH = size(mpc.EHlocation,1); % number of EHs
nGl = size(mpc.Gline,1);
nGen = sum(mpc.gen(:,22)==1)+sum(mpc.gen(:,22)==0);% all gen(TFU and GFU), excluded dispatchable loads
nGs = size(mpc.Gsou,1);
nComponent = nGen+nGs;
% --------------test-----------------------
% testmpc = mpc0; testmpc.bus(:,3) = mpc0.bus(:,3)*1.25; %�����ԣ���ฺ�ɵ�1.27�����һ�������
% testGEresult = GErunopf(testmpc);
%-----------------------
GEresult0 = GErunopf(mpc0);

% ----- 1.2 the load data for each energy hub -----
[loadCurve,EHpara] = EHdata();% original EH��data
% expand the time resolution of load profile
[load0.electricity, load0.heating, load0.cooling] = deal(interp(loadCurve(1,:),1/dt),interp(loadCurve(2,:),1/dt),interp(loadCurve(3,:),1/dt));
% ����ԭʼ����load���ֵռԭʼEH���豸�����ı����������µĸ��ڵ��EH���豸������������mpc.EH����
[nodalEHpara] = scaleEH(mpc,[load0.electricity;load0.heating;load0.cooling],EHpara);% 96�����EH����

% ----- 1.3 gas transient data -----
[dx, nx] = decidePipelineCell(gtd);% maximun value of 3 miles per cell according to the reference

% ----- 1.4 reliability data preprocess
for i = 1:nComponent
    if i<= nGen % is generator
        lamda(i) = 1 / rts.gen(i,1); mu(i) = 1 / rts.gen(i,2);
    else
        lamda(i) = 1 / rts.Gsou(i-nGen,1); mu(i) = 1/ rts.Gsou(i-nGen,2);
    end
    avaliability{i,1} = mu(i)/(lamda(i)+mu(i)) + lamda(i)/(lamda(i)+mu(i)) * exp(-(lamda(i)+mu(i))*KK);
    avaliability{i,2} = 1 - avaliability{i,1};
end

%%  ��������ڻ�ȡ�ڵ���Դ�۸񣬺͸����޹�
ob.dayahead = zeros(NK,1);
[dayahead_mpc,dayahead_result] = deal(cell(NK,1));
[nodalPrice.electricity, nodalPrice.gas] = deal(zeros(NK,nb),zeros(NK,nGb));
for k = 1:NK
    % mpc for each period
    % ���ɲ�������̫�󣬶��Ҳ���ʵ����һ���û����Կ��ܲ����ܾ��ң����Ǵ�Χ���������кܶ�̶����ɣ����繤ҵ���ɣ�����������ô��
    % �����趨ֻ��һ�븺����EH�仯����һ���ǹ̶���
    dayahead_mpc{k} = mpc0;
    dayahead_mpc{k}.bus(:,3:4) = mpc0.bus(:,3:4) * (0.6 + 0.4* load0.electricity(k)/max(load0.electricity)); 
    %��������ɱ仯���ƷŻ�һ��
    dayahead_mpc{k}.Gbus(:,3) = mpc0.Gbus(:,3) *(0.6 + 0.4 * (load0.heating(k)+load0.cooling(k))/ max((load0.heating+load0.cooling)));
    % ��Ȼ�����ɾ�����ô���㣬ʵʱEH���е��ڵ�ʱ���������������㣬�������в���   
end
for k = 1:NK
    [dayahead_IEGSresult{k},flag] = GErunopf(dayahead_mpc{k});
    ob.dayahead(k) = flag;
    [nodalPrice.electricity(k,:),nodalPrice.gas(k,:)] = deal(dayahead_IEGSresult{k}.bus(:,14)',dayahead_IEGSresult{k}.Gbus(:,11)');
end
% �ڵ�۸����㣺ԭ������$/MWh��$/(Mm3)�����ڵ粻�䣬�������$/(MWh)
nodalPrice.gas = nodalPrice.gas/200;
%% calculate the day ahead optimal schedule of nodal EHs, according to the nodal energy price
for i = 1:nEH
    dayaheadEHschedule{i} = zeros(NK,15);%һ��EH15������������ei��gi��
    for k = 1:NK
        Ebus = mpc.EHlocation(i,2); Gbus = mpc.EHlocation(i,1);
        [dayaheadEHschedule{i}(k,:),diagnostics] = EHschedule(nodalPrice.electricity(k,Ebus),nodalPrice.gas(k,Gbus),nodalEHpara{i},k);
        % attention: gi is in MW      
        ob.EH(i,k) = diagnostics.problem;
    end
end
% �޸�dayaheadIEGS�������ݣ�ȥ��EH���ֵĸ���
dayahead_IEGSresult_basicLoad = dayahead_IEGSresult; % ���Ҳ����dayahead_mpc�������ɵĻ��������
for k = 1:NK
    for i = 1:nEH
        EHgbus = mpc0.EHlocation(i,1); EHebus = mpc0.EHlocation(i,2); 
        dayahead_IEGSresult_basicLoad{k}.bus(EHebus,3:4) = dayahead_IEGSresult{k}.bus(EHebus,3:4) * ...
            (1-dayaheadEHschedule{i}(k,1)/dayahead_IEGSresult{k}.bus(EHebus,3));
        dayahead_IEGSresult_basicLoad{k}.Gbus(EHgbus,3) = dayahead_IEGSresult{k}.Gbus(EHgbus,3) * ...
            (1-dayaheadEHschedule{i}(k,2)/200/dayahead_IEGSresult{k}.Gbus(EHgbus,3));
        if (dayahead_IEGSresult_basicLoad{k}.bus(EHebus,3)<=0) || (dayahead_IEGSresult_basicLoad{k}.Gbus(EHgbus,3) <=0)
            ob.basicLoad = 1;%ȷ��EH�ڵ��ϵĻ������ɲ����ɸ���
        end
    end
end
% ������EH����Դ���ĺ�IEGS�������𣿶�����
% EH������������Ҫ�����ĸ��ɸ���һ��������ƺ��ˣ��ǰ�ʣ�ಿ�־���Ϊ�ǹ̶����֡�
% ������ǰ���£��ڵ���ܸ��ɻ��ǲ���ģ����Բ����ټ���һ��
save stop2.mat
%% stage2: MCS 
clear
clc
load stop2.mat
% [constraints,objective,variables] = 
% LaCMS_controller = lookAheadContingencyManagement_Optimizer(nComponent,dd,dt,nodalEHpara, gtd,...
%     nx,dx,nEH, mpc0);
% [model,recoverymodel,diagnostic,internalmodel] = export(constraints,objective);
% %%
clc
normalCondition = setInitialConditionForGasSystem(dayahead_IEGSresult{1},gtd,nx,dx);
%------------test-----------------
for k = 1:NK
    dayahead_IEGSresult_basicLoad{k} = GEresult0;
end
for i = 1:simulationTimes
    % ----- 2.1 generate the system state sequence -----
    [Info_components] = MCSformingScenarioV6(rts,missionTime);
    Info_components(:,2:3) = round(Info_components(:,2:3)/dd); % ���յ���ʱ��ȡ��
    nSystemStates = size(Info_components,1);
    deleteLine = [];
    for s = 1:nSystemStates
        if Info_components(s,2) == Info_components(s,3)
            deleteLine = [deleteLine s];
        end
    end
    Info_components(deleteLine,:) = []; % ɾȥ������������ʱ����ٵ�״̬
    % -------------- test ----------------------
    % �ֶ����õ��͹��ϳ�������ͨ����̬OPF�����и�����������þ�����̬
    info1 = ones(1,nComponent);
    info2 = info1; info2(nGen+([1])) = 0;%��Դ1��1/5ʧЧ����������״̬����
    info3 = info2; info3(nGen+([2:4])) = 0;%��Դ1��3/5��һ��ʧЧ��˵����ǰ���ı�Ҫ�ԣ����䶯������˵�������ԺͿɿ��Ե�Ȩ��
    info4 = info1; info4([23,32]) = 0; % �������ϵͳ���ϣ���ʱ��Ȼ����Ϊ�߼ʻ��������ϵͳ���硣�䶯��ѹ��Χ��˵����Ȼ��ϵͳ�Ե���ϵͳ��֧��
    info5 = info4; info5(nGen+([1:4])) = 0; % ��Ȼ��ϵͳ���ϣ�ͨ��ǰһʱ�εĲ�ͬ��֧��˵������̫��֧�Ż����Ȼ��ϵͳ�ɿ��Դ�������
    Info_components =    [  1   0    8   info1;
                            2   8   16   info2;
                            3   16   24   info3;
                            4   24   32   info1;%�ָ�
                            5   32   40   info4;
                            6   40   48   info5;
                            ];
%     Info_components =    [  1   0    8   info1;
%                             2   8   16   info1;
%                             3   16   24   info1;
%                             4   24   32   info1;%�ָ�
%                             5   32   40   info4;
%                             6   40   48   info5;
%                             ];
% �Ƚϲ�ͬ��ѹ���ƶ��ڵ���ϵͳ���ϸ���������Ӱ��
%     Info_components =    [  1   0    8   info1;
%                             2   8   16   info1;
%                             3   16   24   info1;
%                             4   24   32   info1;%�ָ�
%                             5   32   40   info4;
%                             6   40   48   info1;
%                             ];
%     Info_components2 =    [  1   0    8   info3;
%                             2   8   16   info1;
%                             3   16   24   info1;
%                             4   24   32   info1;%�ָ�
%                             5   32   40   info1;
%                             6   40   48   info1;
%                             ];
%     for ii = 1:size(testInfoComponents,1)
%         testmpc = mpcUpdateBinary(testInfoComponents(ii,4:end),mpc0,nGen);
% %         testmpc.gencost(34:50,6)=2600;
%         testmpc.Gcost=mpc0.Gcost * 1000;
%         testmpc.branch(:,6:8) = 9999;
% %         testmpc.gen(mpc0.gfuIndex,9) = mpc0.gen(mpc0.gfuIndex,9)/3;
%         testmpc.gencost(12:14,6)=16;%���������ȼ������ļ۸�ʹȼ�������Ϊ�߼ʻ���
%         % Ϊɶ��ô��ȼ�����鶼����������
%         testResultSteady{ii} = GErunopf(testmpc);
%     end
    % ------------------------------------------
    % initialization
    NS = size(Info_components,1);
    for s = 1:NS
        newmpc{s} = mpcUpdateBinary(Info_components(s,4:end),mpc0,nGen);
    end
    initialCondition = setInitialConditionForGasSystem(dayahead_IEGSresult{1},gtd,nx,dx);
    [solution,nextInitialCondition] = lookAheadContingencyManagement(dt*3600,gtd,dx, NK,NS,mpc,...
       nodalEHpara,dayahead_IEGSresult_basicLoad,dayaheadEHschedule,mpc0,newmpc,initialCondition,normalCondition,Info_components,...
       nEH,nx);
    NS = size(Info_components2,1);
    for s = 1:NS
        newmpc{s} = mpcUpdateBinary(Info_components2(s,4:end),mpc0,nGen);
    end
   [solution,nextInitialCondition] = lookAheadContingencyManagement(dt*3600,gtd,dx, NK,NS,mpc,...
       nodalEHpara,dayahead_IEGSresult_basicLoad,dayaheadEHschedule,mpc0,newmpc,nextInitialCondition,normalCondition,Info_components2,...
       nEH,nx);
   
    % �������gu
    [a] = resultProcessing(stateVar,mpc,ND/NK,nComponent+1,nx);
    % �����µ�ϵͳ״̬���³�ʼ����
    initialCondition = setInitialConditionForGasSystem(operationResults.IEGS{kst},gtd,nx,dx);

    % ���������������ص�һЩָ�꣬���ڲ��м��㡣������
    for k = 1:NK
%         ec{i}(k,i) = operationResults.IEGS
    end
end
            
            
            
%%         
        
    % ----- 2.2 
iK.DR = (53+1):1:59; % �为�ɴ���700����������ΪDRʱ��ȽϺ���
NK.DR = iK.DR(end)-iK.DR(1)+1;
notifyTime = 48; %����12��֪ͨ
endTime = 68; %����17���°࣬��������17��
iK.studyPeriod = notifyTime:endTime;
NK.studyPeriod = endTime-notifyTime+1;
NK.nonDR = NK.studyPeriod - NK.DR;
% ÿ��EH��DR�ṩ���б��õ������Ƕ��٣����踺������ǰ�Ļ����ϸ���*120%��Ȼ��ֻ��EH�Ͽ��������ɾ���
EHreserve = zeros(NK.all,nEH);
counter = 0;
for k = iK.DR(1):iK.DR(end)
    counter = counter+1;
    h = k2h_h2k(k,4,'k2h');
    % electricity load only
    realtime_mpc{k} = dayahead_mpc{k};
%     realtime_mpc{k}.bus(:,3:4) = dayahead_mpc{k}.bus(:,3:4) * 1.29;
    realtime_mpc{k}.bus(:,3:4) = dayahead_mpc{k}.bus(:,3:4) * 1.25;
    % ȥ���������ɵ�DR������ֻ��EH������DR
    load_igen = find(mpc0.gen(:,22)==2);
    EH_igen = [];
    for i = 1:size(load_igen)
        if ~ismember(realtime_mpc{k}.gen(load_igen(i),1),mpc0.EHlocation(:,2)) % not EH
            realtime_mpc{k}.gen(load_igen(i),9) = 0; % if not EH bus, don't curtail loads
        else % is EH
            % �޸�DR������ΪĿǰEH��ei
            EHindex = find(mpc.EHlocation(:,2) == realtime_mpc{k}.gen(load_igen(i),1));
            realtime_mpc{k}.gen(load_igen(i),9) = dayaheadEHschedule{EHindex}(h,1);
        end
    end
    [reserve_result{counter},flag] = GErunopf(realtime_mpc{k});
    ob.reserve(counter) = flag;
    for i = 1:nEH
        EH_igen = [EH_igen; find(mpc.gen(load_igen,1) == mpc.EHlocation(i,2))+load_igen(1)-1];% ��EH��Ӧ�ĸ�����mpc.gen����ı�Ŵ�����EH_igen����
    end
        
    EHreserve(k,:) = reserve_result{counter}.gen(EH_igen,2)';
end

% knowing the reserve requirement at each time period, 
[dx, nx] = decidePipelineCell(gtd);
dt = 900; % 15min 
% iK = endTime - notifyTime;
iter = 1;
UB(iter) = 10e20; LB(iter) = 0;
addCutsCoefficient = [];SP_EHresult = [];exitflagSP = [];
% control variables: 
[MPformulation] = MP_IEGSdispatch_optimizer(addCutsCoefficient,exitflagSP,SP_EHresult,...
    dayahead_IEGSresult_basicLoad,dayaheadEHschedule,EHreserve,mpc,gtd,nx,dx,dt,NH,nEH,NK,iK,nodalPrice,iter);
for i = 1:nEH
    [SPformulation{i}] = SP_EHschedule_lp_optimizer([],[],nodalEHpara{i},NK,iK);
end
while abs(UB(iter)-LB(iter)) / abs(UB(iter)+LB(iter)) > 1e-2    
%     yalmip('clear');
    iter = iter + 1;
%     load periter.mat
    [MP_IEGSresult, solverTime,MPformulation] = MP_IEGSdispatch_solver(addCutsCoefficient,exitflagSP,SP_EHresult,...
    dayahead_IEGSresult_basicLoad,dayaheadEHschedule,EHreserve,mpc,gtd,nx,dx,dt,NH,nEH,NK,iK,nodalPrice,iter,MPformulation);


%     save MP.mat
%     %%%%%%%%%%%%%%%%
%     clear
%     yalmip('clear')
%     load MP20200615.mat
    LB(iter) = MP_IEGSresult.f_MP;
    for i = 1:nEH
        % ע��MP�õ���ei��gi���Ǳ��ۻ����
        ei_hat = MP_IEGSresult.ei(:,i) * mpc.baseMVA; gi_hat = MP_IEGSresult.gi(:,i) * 200; 
        [SP_EHresult{i},addCutsCoefficient{i},SP_solverTime(iter,i),exitflagSP(iter,i)] = SP_EHschedule_lp_solver(SPformulation{i},ei_hat,gi_hat,nodalEHpara{i},NK,iK);
    end
    if min(exitflagSP(iter,:)) == 1 % if all EH schedule is feasible, then update upper bound
        UB(iter) = MP_IEGSresult.f_MP;
        for i = 1:nEH
            UB(iter) = UB(iter) + SP_EHresult{i}.EHcost;
        end
    else
        UB(iter) = UB(iter-1);
    end
%     UB(iter) = min(UB(iter),UB(iter-1));

% save periter.mat
end
totalSolverTime = sum(MP_solverTime) + sum(sum(SP_solverTime));

%% visualize the results
% 1 computation speed
% SP_solverTime = 10*SP_solverTime;
computationTime.MPsolver = sum(MP_solverTime);
computationTime.SPsolver = sum(SP_solverTime);
computationTime.SPwaiting = sum(max(SP_solverTime,[],2) - SP_solverTime);
computationTime.total = totalSolverTime;
UB1(1) = UB(1); LB1(1) = LB(1);
for i = 2:iter
    UB1(i) = min(UB(i),UB1(i-1));
    LB1(i) = max(LB(i),LB1(i-1));
end
% 2 self-schedule
load1 = nodalEHpara{1}.load(:,iK.DR)' - SP_EHresult{end,1}.so;
SP_EHresult{end,1}.h3h + SP_EHresult{end,1}.h1h + SP_EHresult{end,1}.h2h;
nodalEHpara{1,1}.load(3,iK.studyPeriod(1):iK.studyPeriod(end))' - SP_EHresult{end,1}.c3c - SP_EHresult{end,1}.c4c;
% operating condition

% 3 IEGS
% pressure:
prsInfo = cell(nGl,1);
for i = 1:nGl
    prsInfo{i} = [];
    for j = 1:size(MP_IEGSresult{end}.PrsPipe{i},2)
        prsInfo{i} = [prsInfo{i};max(MP_IEGSresult{end}.PrsPipe{i}(:,j)),min(MP_IEGSresult{end}.PrsPipe{i}(:,j)),mean(MP_IEGSresult{end}.PrsPipe{i}(:,j))];
    end
end
    
% cost


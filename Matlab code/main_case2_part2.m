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
simulationTimes = 10000; % TSMCS ����

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

normalCondition = setInitialConditionForGasSystem(dayahead_IEGSresult{1},gtd,nx,dx);
%------------test-----------------
for k = 1:NK
    electricityLoad(k) = sum(dayahead_IEGSresult_basicLoad{k}.bus(:,3)) * 1 * 2850/2300;
    gasLoad(k) = sum(dayahead_IEGSresult_basicLoad{k}.Gbus(:,3)) * 46/45;
    dayahead_IEGSresult_basicLoad{k}.bus(:,3) = dayahead_IEGSresult_basicLoad{k}.bus(:,3) * 1 * 2850/2300;
    dayahead_IEGSresult_basicLoad{k}.Gbus(:,3) = dayahead_IEGSresult_basicLoad{k}.Gbus(:,3) * 46/45;
end
PrsVioPercentge = 0.1;terminalFactor = 0.00;startk = 1; endk = 24;
[LaCMS_optimizer1st] = lookAheadContingencyManagement_Optimizer(dt*3600,gtd,dx, NK/2,mpc,...
   nodalEHpara,dayahead_IEGSresult_basicLoad,mpc0,normalCondition,nEH,nx,startk,endk,PrsVioPercentge,terminalFactor);
PrsVioPercentge = 0.1;terminalFactor = 0.05;startk = 25; endk = 48;
[LaCMS_optimizer2nd] = lookAheadContingencyManagement_Optimizer(dt*3600,gtd,dx, NK/2,mpc,...
   nodalEHpara,dayahead_IEGSresult_basicLoad,mpc0,normalCondition,nEH,nx,startk,endk,PrsVioPercentge,terminalFactor);

% %%
clc
tic
simulationTimes = 3;
LCe = cell(simulationTimes,1); LCg = cell(simulationTimes,1);
for i = 1:simulationTimes
    % ----- 2.1 generate the system state sequence -----
    [Info_components] = MCSformingScenarioV6(rts,missionTime);
    Info_components(:,2:3) = round(Info_components(:,2:3)/dd); % ���յ���ʱ��ȡ��
    Info_components = deleteRepeatedLine(Info_components);
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
%                             2   8   16   info4;
%                             3   16   24   info1;
%                             4   24   32   info3;%�ָ�
%                             5   32   40   info3;
%                             6   40   48   info1;
%                             ];

% ��������֣��ӵ�24��ʱ�Σ�
divideOrder = min(find(Info_components(:,2)>=NK/2));
Info_components1 = Info_components(1:divideOrder,:);
Info_components1(end,3) = NK/2;
Info_components2 = Info_components(divideOrder:end,:);
Info_components2(1,2) = NK/2;
Info_components2(:,2:3) = Info_components2(:,2:3) - NK/2;
Info_components1 = deleteRepeatedLine(Info_components1);
Info_components2 = deleteRepeatedLine(Info_components2);


    % ------------------------------------------
    % 1st 
    NS = size(Info_components1,1);
    newmpc = cell(NS,1);
    for s = 1:NS
        newmpc{s} = mpcUpdateBinary(Info_components1(s,4:end),mpc0,nGen);
    end

    [LCe1st{i},LCg1st{i},PGs1st{i},totalCost1st{i},GenAndLCeCost1st{i},GasPurchasingCost1st{i},GasCurtailmentCost1st{i},...
        nextInitialCondition] = lookAheadContingencyManagement_Solver(LaCMS_optimizer1st,NK/2,NS,mpc,...
       mpc0,newmpc,normalCondition,Info_components1,nx); 
   % 2nd
   NS = size(Info_components2,1);
    for s = 1:NS
        newmpc{s} = mpcUpdateBinary(Info_components2(s,4:end),mpc0,nGen);
    end
    [LCe2nd{i},LCg2nd{i},PGs2nd{i},totalCost2nd{i},GenAndLCeCost2nd{i},GasPurchasingCost2nd{i},GasCurtailmentCost2nd{i},...
        nextInitialCondition] = lookAheadContingencyManagement_Solver(LaCMS_optimizer2nd,NK/2,NS,mpc,...
       mpc0,newmpc,nextInitialCondition,Info_components2,nx); 
   
end
save stop3.mat
%%
% ע���Ұ���Ȼ���Ĺ�����������10����������˵���С��Դ����������2���Ͳ���ˡ�
% ����������˵����Ȼ����صĿɿ��ԡ������ɱ��ȶ�����5
nLCg = size(find(mpc.Gbus(:,3)~=0),1); nLCe = size(find(mpc.bus(:,3)~=0),1);
% 1st
[systemEDNSsum1st,systemEGNSsum1st] = deal(zeros(NK/2,1));
[sumPGs1st] = zeros(1,6);
[sumTotalCost1st,sumGenAndLCeCost1st,sumGasPurchasingCost1st,sumGasCurtailmentCost1st] = deal(zeros(1,1));
for i = 1:simulationTimes
    systemEDNSsum1st = systemEDNSsum1st + sum(LCe1st{i},2);systemEGNSsum1st = systemEGNSsum1st + sum(LCg1st{i},2);    
    sumPGs1st = sumPGs1st + sum(PGs1st{i});sumTotalCost1st = sumTotalCost1st + totalCost1st{i};
    sumGenAndLCeCost1st = sumGenAndLCeCost1st + GenAndLCeCost1st{i};
    sumGasPurchasingCost1st = sumGasPurchasingCost1st + GasPurchasingCost1st{i};
    sumGasCurtailmentCost1st = sumGasCurtailmentCost1st + GasCurtailmentCost1st{i};    
end
systemEDNS1st = systemEDNSsum1st/simulationTimes;systemEGNS1st = systemEGNSsum1st/simulationTimes;
expectedPGs1st = sumPGs1st/4/24/simulationTimes;expectedTotalCost1st = sumTotalCost1st/simulationTimes;
expectedGenAndLCeCost1st = sumGenAndLCeCost1st / simulationTimes; 
expectedGasPurchasingCost1st = sumGasPurchasingCost1st / simulationTimes;
expectedGasCurtailmentCost1st = sumGasCurtailmentCost1st / simulationTimes;
EENS1st = sum(systemEDNS1st)/4; EVNS1st = sum(systemEGNS1st)/24/4;
% 2nd
[systemEDNSsum2nd,systemEGNSsum2nd] = deal(zeros(NK/2,1));
[sumPGs2nd] = zeros(1,6);
[sumTotalCost2nd,sumGenAndLCeCost2nd,sumGasPurchasingCost2nd,sumGasCurtailmentCost2nd] = deal(zeros(1,1));
for i = 1:simulationTimes
    systemEDNSsum2nd = systemEDNSsum2nd + sum(LCe2nd{i},2);systemEGNSsum2nd = systemEGNSsum2nd + sum(LCg2nd{i},2);    
    sumPGs2nd = sumPGs2nd + sum(PGs2nd{i});sumTotalCost2nd = sumTotalCost2nd + totalCost2nd{i};
    sumGenAndLCeCost2nd = sumGenAndLCeCost2nd + GenAndLCeCost2nd{i};
    sumGasPurchasingCost2nd = sumGasPurchasingCost2nd + GasPurchasingCost2nd{i};
    sumGasCurtailmentCost2nd = sumGasCurtailmentCost2nd + GasCurtailmentCost2nd{i};    
end
systemEDNS2nd = systemEDNSsum2nd/simulationTimes;systemEGNS2nd = systemEGNSsum2nd/simulationTimes;
expectedPGs2nd = sumPGs2nd/4/24/simulationTimes;expectedTotalCost2nd = sumTotalCost2nd/simulationTimes;
expectedGenAndLCeCost2nd = sumGenAndLCeCost2nd / simulationTimes; 
expectedGasPurchasingCost2nd = sumGasPurchasingCost2nd / simulationTimes;
expectedGasCurtailmentCost2nd = sumGasCurtailmentCost2nd / simulationTimes;
EENS2nd = sum(systemEDNS2nd)/4; EVNS2nd = sum(systemEGNS2nd)/24/4;

% std
LCeAll = zeros(NK/2,simulationTimes);LCgAll = zeros(NK/2,simulationTimes);
for i = 1:simulationTimes
    LCeAll(:,i) = sum(LCe1st{i},2);LCgAll(:,i) = sum(LCg1st{i},2);
    if mod(i,1000) == 0
        stdSystemEDNS(:,i) = std(LCeAll(:,1:i),0,2)./mean(LCeAll(:,1:i),2)/sqrt(i); 
        stdSystemEGNS(:,i) = std(LCgAll(:,1:i),0,2)./mean(LCgAll(:,1:i),2)/sqrt(i); 
    end
end
toc    
%% convergence
for i = 1:simulationTimes
    if mod(i,1000) == 0
        EDNScvrg(:,i/1000) = stdSystemEDNS(40:48,i);
        EGNScvrg(:,i/1000) = stdSystemEGNS(40:48,i);
    end
end
EDNScvrg = EDNScvrg';EGNScvrg = EGNScvrg';
% nodal EENS and EGNS
nodalEENS = sum(nodalEDNS)'/4;%MWh
nodalEVNS = sum(nodalEGNS)'/24/4;%Mm3

%%
[totalCost1st,GenAndLCeCost1st,GasPurchasingCost1st,GasCurtailmentCost1st] = ...
    deal(totalCost1st,sumGenAndLCeCost1st,sumGasPurchasingCost1st,sumGasCurtailmentCost1st);
[totalCost2nd,GenAndLCeCost2nd,GasPurchasingCost2nd,GasCurtailmentCost2nd] = ...
    deal(totalCost2nd,sumGenAndLCeCost2nd,sumGasPurchasingCost2nd,sumGasCurtailmentCost2nd);
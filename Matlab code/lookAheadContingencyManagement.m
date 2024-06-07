function [solution,nextInitialCondition] = lookAheadContingencyManagement(dt,gtd,dx, NK,NS,mpc,...
   nodalEHpara,dayahead_IEGSresult_basicLoad,dayaheadEHschedule,mpc0,newmpc,initialCondition,normalCondition,Info_components,...
       nEH,nx)
%% initialization
NL = 3;
mpc0.basePrs = 1e6;
[para] = initializeParameters2();
% data dimensions
nb   = size(mpc.bus, 1);    %% number of buses
nl   = size(mpc.branch, 1); %% number of branches
ngen   = size(mpc.gen, 1);    %% number of dispatchable injections

%add GFU,LCe are included in the mpc
nGb  = size(mpc.Gbus,1); % number of gas bus
nGl  = size(mpc.Gline,1); % number of gas line
nGs  = size(mpc.Gsou,1); % number of gas source
nLCg = size(find(mpc.Gbus(:,3)~=0),1);
% 
normalP = repmat(cell2mat(normalCondition.P')/mpc0.basePrs,NK,1);% bar/10
normalQ = repmat(cell2mat(normalCondition.Q'),NK,1);%Mm3/day
%% define named indices into data matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[PW_LINEAR, POLYNOMIAL, MODEL, STARTUP, SHUTDOWN, NCOST, COST] = idx_cost;
% create (read-only) copies of individual fields for convenience\
mpopt = [];
[baseMVA, bus, gen, branch, gencost, Au, lbu, ubu, mpopt, ...
    N, fparm, H, Cw, z0, zl, zu, userfcn] = opf_args(mpc, mpopt);
%% state variables
Prs = sdpvar(NK,sum(nx+1));                                                    % gas pressure along the pipeline
Gf = sdpvar(NK,sum(nx+1));  
PGs = sdpvar(NK,nGs);
LCg = sdpvar(NK,nLCg);
Va = sdpvar(NK,nb,'full'); 
Pg = sdpvar(NK,ngen);
ei = sdpvar(NK,nEH);gi = sdpvar(NK,nEH);
[eeeAll] = sdpvar(NK,nEH);
[ee3All] = sdpvar(NK,nEH);[e13All] = sdpvar(NK,nEH);[e1hAll] = sdpvar(NK,nEH);
[gg1All] = sdpvar(NK,nEH);[gg2All] = sdpvar(NK,nEH);[h3hAll] = sdpvar(NK,nEH);
[h1hAll] = sdpvar(NK,nEH);[h14All] = sdpvar(NK,nEH);[h24All] = sdpvar(NK,nEH);
[h2hAll] = sdpvar(NK,nEH);[c3cAll] = sdpvar(NK,nEH);[c4cAll] = sdpvar(NK,nEH);
lcAll = sdpvar(NK,nEH,NL); % load curtailment for each DR period
% stateVar = {PrsAll,GfAll,PGsAll,LCgAll,VaAll,PgAll,eiAll,giAll,...
%     eeeAll,ee3All,e13All,e1hAll,gg1All,gg2All,h3hAll,...
%     h1hAll,h14All,h24All,h2hAll,c3cAll,c4cAll,lcAll};
% parameter variables (change in each loop)
% initialP = sdpvar(NK,sum(nx+1)); 
% initialQ = sdpvar(NK,sum(nx+1)); %ÿ��������ÿ������ʱ����ͬ
% PGsmaxScenario = sdpvar(NS,NK,nGs);
% PgmaxScenario = sdpvar(NS,NK,ngen); % ÿ��������ͬ��2������ʱ�β�ͬ�����е�NS������ΪԪ��״̬���仯��
% electricityLoad1st = sdpvar(NK,nb);
% gasLoad1st = sdpvar(NK,nGb);
% EHload1st = sdpvar(NK,nEH,NL);
% electricityLoad2nd = sdpvar(NK,nb);
% gasLoad2nd = sdpvar(NK,nGb);
% EHload2nd = sdpvar(NK,nEH,NL);
% scenarioProbability = sdpvar(NS+1,1);
% PrsVioPercentge = sdpvar(1,1);
% paraVar = {initialP,initialQ,PGsmaxScenario,PgmaxScenario,electricityLoad1st,gasLoad1st,EHload1st...
%     electricityLoad2nd,gasLoad2nd,EHload2nd,scenarioProbability,PrsVioPercentge};
%% initial values IEGS ÿ�������µĳ�ֵ����ͬ��
for k = 1:NK
    Pg0(k,:) = dayahead_IEGSresult_basicLoad{k}.gen(:, PG) / baseMVA; % 
    Va0(k,:)  = dayahead_IEGSresult_basicLoad{k}.bus(:, VA) * (pi/180);% ����
    Prs0(k,:) = cell2mat(initialCondition.P')/mpc0.basePrs;% bar/10
    Gf0(k,:) =  cell2mat(initialCondition.Q');%Mm3/day
    PGs0(k,:) = dayahead_IEGSresult_basicLoad{k}.Gsou(:,5);% Mm3/day
    LCg0(k,:) = dayahead_IEGSresult_basicLoad{k}.Gbus(mpc0.Gbus(:,3)~=0,10);% Mm3/day; %Mm3/day
end
for i = 1:nEH
    ei0(:,i) = dayaheadEHschedule{i}(:,1)/baseMVA;
    gi0(:,i) = dayaheadEHschedule{i}(:,2)/200; %Mm3/day
end
% start value EH ��MW)
[eee0, ee30, e130, e1h0, gg10, gg20, h3h0, h1h0, h140, h240, h2h0, c3c0, c4c0] = deal(zeros(NK,nEH));
lc0 = zeros(NK,nEH,NL); % load curtailment for each DR period

% assign values
assign(Pg,Pg0); assign(Va,Va0);
assign(Prs,Prs0); assign(Gf,Gf0);assign(PGs,PGs0);
assign(LCg,LCg0);
assign(ei,ei0); assign(gi,gi0); % ע����Ȼ����λ������
assign([eeeAll, ee3All, e13All, e1hAll, gg1All, gg2All, h3hAll, h1hAll, h14All, h24All, h2hAll, c3cAll, c4cAll],...
    [eee0, ee30, e130, e1h0, gg10, gg20, h3h0, h1h0, h140, h240, h2h0, c3c0, c4c0]);
assign(lcAll,lc0);
%% specify parameter variables
initialP = zeros(NK,sum(nx+1)); %bar/10
initialQ = zeros(NK,sum(nx+1)); %ÿ��������ÿ������ʱ����ͬ (Mm3/day)
PGsmax = zeros(NK,nGs); %Mm3/day
Pgmax = zeros(NK,ngen); % ÿ��������ͬ��2������ʱ�β�ͬ�����е�NS������ΪԪ��״̬���仯��

initialP = Prs0; 
initialQ = Gf0;
for s = 1:NS
    duration = Info_components(s,3)-Info_components(s,2);
    PGsmax(Info_components(s,2)+1:Info_components(s,3),:) = repmat(newmpc{s}.Gsou(:,4)',duration,1);
    Pgmax(Info_components(s,2)+1:Info_components(s,3),:) = repmat(newmpc{s}.gen(:,PMAX)',duration,1)/baseMVA;
end
PrsVioPercentge = 0.2;
%% set upper and lower bounds
Pgmin = mpc.gen(:, PMIN) / baseMVA *0; %Pgmin is set to zero

refs = find(mpc.bus(:, BUS_TYPE) == REF);
Vau = Inf(nb, 1);       %% voltage angle limits
Val = -Vau;
Vau(refs) = 1;   %% voltage angle reference constraints
Val(refs) = 1;

Prsmin = normalP*(1-PrsVioPercentge); Prsmax = normalP*(1+PrsVioPercentge); %bar/10
% PrsԼ����������ģ���Ϊ�ڶ�����ʱ�ε�prsԼ�����µ�һʱ�β�����̫��prs
Gfmax = [];
for i = 1:nGl
    addGfmax = mpc.Gline(i,5) * ones(nx(i)+1,1);
    Gfmax = [Gfmax; addGfmax];
end
Gfmin = -Gfmax;
PGsmin = mpc.Gsou(:,3)*0; %test: PGs������Ϊ0

LCgmin = zeros(nLCg,1);
LCgmax = mpc.Gbus(mpc.Gbus(:,3)~=0,3).*1;  
eimin = zeros(NK,nEH); gimin = zeros(NK,nEH);
eimax = inf * ones(NK,nEH); % no upper limits 
gimax = inf * ones(NK,nEH);
% ------------------
PrsBoxCons = [Prsmin <= Prs <= Prsmax];
GfBoxCons = [repmat(Gfmin',NK,1) <= Gf <= repmat(Gfmax',NK,1)];
PGsBoxCons = [repmat(PGsmin',NK,1) <= PGs <= PGsmax];
LCgBoxCons = [repmat(LCgmin',NK,1) <= LCg<= repmat(LCgmax',NK,1)];
VaBoxCons = [repmat(Val',NK,1) <= Va <= repmat(Vau',NK,1)];
PgBoxCons = [repmat(Pgmin',NK,1) <= Pg <= Pgmax];
eiBoxCons = [eimin <= ei <= eimax];
giBoxCons = [gimin <= gi <= gimax];
%%
for k = 1:NK
    electricityLoad(k,:) = dayahead_IEGSresult_basicLoad{k}.bus(:,PD)'/baseMVA;
    gasLoad(k,:) = dayahead_IEGSresult_basicLoad{k}.Gbus(:,3)';

end


%% IEGS other limtis
% preparations
il = find(branch(:, RATE_A) ~= 0 & branch(:, RATE_A) < 1e10);
[Ybus, Yf, Yt] = makeYbus(baseMVA, bus, branch);
cumnx = cumsum(nx+1);
pp = ones(nGl,2);
pp(2:nGl,1) = cumnx(1:(nGl-1))+1;
pp(1:nGl,2) = cumnx(1:nGl);
%
vv.i1.Pg = 1; vv.iN.Pg = ngen; vv.N.Pg = ngen;
vv.i1.Qg = vv.iN.Pg + 1; vv.iN.Qg = vv.iN.Pg + ngen; vv.N.Qg = ngen;
vv.i1.Va = vv.iN.Qg + 1; vv.iN.Va = vv.iN.Qg + nb; vv.N.Va = nb;
vv.i1.Vm = vv.iN.Va + 1; vv.iN.Vm = vv.iN.Va + nb; vv.N.Vm = nb;
vv.i1.Prs = vv.iN.Vm + 1; vv.iN.Prs = vv.iN.Vm + sum(nx+1); vv.N.Prs = sum(nx+1);
vv.i1.Gf = vv.iN.Prs + 1; vv.iN.Gf = vv.iN.Prs + sum(nx+1); vv.N.Gf = sum(nx+1);
vv.i1.PGs = vv.iN.Gf + 1; vv.iN.PGs = vv.iN.Gf + nGs; vv.N.PGs = nGs;
vv.i1.LCg = vv.iN.PGs + 1; vv.iN.LCg = vv.iN.PGs + nLCg; vv.N.LCg = nLCg;
vv.N.all = vv.N.Pg + vv.N.Qg + vv.N.Pg + vv.N.Va + vv.N.Vm + vv.N.Prs + ...
    vv.N.Gf + vv.N.PGs + vv.N.LCg;
% 
% ei_inbus = zeros(NK.studyPeriod,nb); gi_inbus = zeros(NK.studyPeriod,nGb);
gi_connect = zeros(nEH,nGb);ei_connect = zeros(nEH,nb);
for i = 1:nEH
    gi_connect(i,mpc.EHlocation(i,1)) = 1;
    ei_connect(i,mpc.EHlocation(i,2)) = 1;
end
gi_inbus = gi * gi_connect ;
ei_inbus = ei * ei_connect ;
avrgQP = initialP./initialQ;
% ----- other constraints -----
dynamicGasFlowContinuityCons = [optimalcontrol_dynamicGasflow_fcn_continuity3(Prs,Gf,avrgQP,...
    mpc,gtd,initialCondition,para,vv,dx,nx,dt,NK) ==0]:'dynamicGasFlowContinuityCons';
dynamicGasFlowMotionCons = [optimalcontrol_dynamicGasflow_fcn_motion3(Prs,Gf,avrgQP,...
    mpc,gtd,initialCondition,para,vv,dx,nx,dt,NK) == 0]:'dynamicGasFlowMotionCons';
electricPowerBalanceConsDC = [optimalcontrol_power_balance_fcn_dc3(Va,Pg,ei_inbus, electricityLoad,...
    mpc, NK) == 0]:'electricPowerBalanceConsDC';
electricBranchFlowConsDC = [optimalcontrol_branch_flow_fcn_dc3(Va, mpc, ...
    il,NK) <= 0]:'electricBranchFlowConsDC';
gasBalanceCons = [optimalcontrol_gas_balance_fcn_yalmip3(Pg,Gf,PGs,LCg,gi_inbus,gasLoad,pp,vv,...
    mpc,nx,NK)==0]:'gasBalanceCons';
gasPressureCons = [optimalcontrol_gas_pressure_fcn_yalmip3(Prs,pp,mpc,NK)==0]:'gasPressureCons';
% terminal condition
terminalCondition = [0.95*normalP(1,:) <= Prs(NK,:) <= 1.5*normalP(1,:)];
%% EH constraints
EHconstraints = []; EHobjective = 0;
for i = 1:nEH
    eiNodal = ei(:,i)*baseMVA; % MW
    giNodal = gi(:,i) * 200; % MW
    eee = eeeAll(:,i);ee3 = ee3All(:,i);e13 = e13All(:,i);e1h = e1hAll(:,i);gg1 = gg1All(:,i);
    gg2 = gg2All(:,i);h3h = h3hAll(:,i);h1h = h1hAll(:,i); h14 = h14All(:,i); h24 = h24All(:,i);
    h2h = h2hAll(:,i); c3c = c3cAll(:,i); c4c = c4cAll(:,i); lc = reshape(lcAll(:,i,:),[NK,NL]);
    [EHconstraintsEach{i},EHobjectiveEach{i}] = EHscheduleFormulation(eiNodal,giNodal,eee,ee3,e13,e1h,gg1,gg2,h3h,h1h,h14,h24,h2h,c3c,c4c,lc...
        ,nodalEHpara{i},NK);
    EHconstraints = [EHconstraints,EHconstraintsEach{i}];
    EHobjective = EHobjective + EHobjectiveEach{i};
end

%% formulation
IEGSconstraints = [ 
                PrsBoxCons;
                GfBoxCons;
                PGsBoxCons;
                LCgBoxCons;
                VaBoxCons;
                PgBoxCons;
                electricPowerBalanceConsDC;
                electricBranchFlowConsDC;
                gasBalanceCons;
                gasPressureCons;
                dynamicGasFlowContinuityCons;  
                dynamicGasFlowMotionCons;
                %%
                eiBoxCons;
                giBoxCons;
                terminalCondition;
                ];
constraintsAll = [IEGSconstraints;EHconstraints];
rampingCost = sum([ 
                    sum(sum((PGs(1:end-1,:)-PGs(2:end,:)).^2))*100;
                    sum(sum((gi(1:end-1,:)-gi(2:end,:)).^2))*100 ;
                    sum(sum((LCg(1:end-1,:)-LCg(2:end,:)).^2))*100 ;
%     sum(sum((Gf(1:end-1,:)-Gf(2:end,:)).^2))*100 + ...
                    sum(sum((Pg(1:end-1,:)-Pg(2:end,:)).^2))*200;
                    sum(sum((ei(1:end-1,:)-ei(2:end,:)).^2))*200;
                    ]);
objectiveAll = objfcn_IEGSdispatch(Pg,PGs,LCg,mpc,NK) + EHobjective + rampingCost;
options = sdpsettings('verbose',2,'solver','gurobi','usex0',0,'debug',1);
options.gurobi.TimeLimit = 100;
% options = sdpsettings('verbose',2,'usex0',0,'debug',1);
solution = optimize(constraintsAll,objectiveAll,options);
%% results processing
[PrsRaw1,GfRaw1,PGsRaw1,LCg1,Va1,Pg1,ei1,gi1] = ...
    deal(value(Prs),value(Gf),value(PGs),value(LCg),value(Va),value(Pg)*baseMVA,value(ei)*baseMVA,value(gi));
PrsPipe = mat2cell(PrsRaw1*10,NK,nx+1); GfPipe = mat2cell(GfRaw1,NK,nx+1); 
PrsNodal = zeros(NK,nGb);
for i = 1:nGl
    PrsNodal(:,mpc.Gline(i,1)) = PrsPipe{i}(:,1);%bar
    PrsNodal(:,mpc.Gline(i,2)) = PrsPipe{i}(:,end);
end
PGs1 = [sum(PGsRaw1(:,1:5),2),sum(PGsRaw1(:,6:9),2),sum(PGsRaw1(:,10:11),2),PGsRaw1(:,12:14)];
% EH
[eeeAll1,ee3All1,e13All1,e1hAll1,gg1All1,gg2All1,h3hAll1,h1hAll1,h14All1,h24All1,h2hAll1,c3cAll1,c4cAll1] ...
    = deal(value(eeeAll),value(ee3All),value(e13All),value(e1hAll),value(gg1All),value(gg2All),...
    value(h3hAll),value(h1hAll),value(h14All),value(h24All),value(h2hAll),value(c3cAll),value(c4cAll));
ho1 = h1hAll1+h14All1; eo1 = e13All1+e1hAll1;
ho2 = h24All1 + h2hAll1;
co3 = c3cAll1;
co4 = c4cAll1;
%%
nextInitialCondition.P = mat2cell(PrsRaw1(end,:)*1e6,1,nx+1)';
nextInitialCondition.Q = mat2cell(GfRaw1(end,:),1,nx+1)';
end


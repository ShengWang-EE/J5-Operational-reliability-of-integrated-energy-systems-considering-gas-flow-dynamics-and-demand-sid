function [f] = optimalcontrol_dynamicGasflow_fcn_continuity3(p0,q0,mpc,gtd,initialCondition,initialP,initialQ,para,vv,dx,nx,dt,NK)
% nvar = vv.N.all * NK; 

[C_q,R,T,Z_T,Z,B,~,~,rhon] = unpackPara2(para);
% PrsInitial = cell2mat(initialCondition.P');
% GfInitial =  cell2mat(initialCondition.Q');
nGl = size(mpc.Gline,1);
Prs = mat2cell([initialP;p0]*1e6,NK+1,nx+1);% psia
gasflow = mat2cell([initialQ;q0],NK+1,nx+1);

% get index
% [f_continuity, f_motion] = deal(cell(nGl,1));
[iContinuity,iMotion,iPrs,iGf] = deal(cell(nGl,1));
for k = 1:NK
    for i = 1:nGl
        for m = 1:nx(i)
            iContinuity{i}(k,m) = sum(nx)*(k-1) + sum(nx(1:i-1)) + m;
            iMotion{i}(k,m) = sum(nx)*NK + sum(nx)*(k-1) + sum(nx(1:i-1)) + m;
%              iPrs{i}(k,m) = vv.N.all*(k-1) + vv.i1.Prs-1 + sum(nx(1:i-1)) + m;
%             iGf{i}(k,m) = vv.N.all*(k-1) + vv.i1.Gf-1 + sum(nx(1:i-1)) + m;
        end
    end
end

for i = 1:nGl
    p = Prs{i}; q = gasflow{i};
%     [f_continuity{i}, f_motion{i}] = deal(zeros(nx(i),NK));
%     [df_continuity{i}, df_motion{i}] = deal(zeros(nvar,nx(i)*NK));
    % parameter
    r = gtd.Gline(i,3); A = pi*r^2; D = 2*r;
    F = gtd.Gline(i,5);
    dl = dx(i); 
    for m = 2:nx(i)+1
%         avrgQP2 = mean([initialCondition.Q{i}(1,m-1:m)./initialCondition.P{i}(1,m-1:m),terminalCondition.Q{i}(1,m-1:m)./terminalCondition.P{i}(1,m-1:m)]);
% %         avrgQP = mean([terminalCondition.Q{i}(1,m-1:m)./terminalCondition.P{i}(1,m-1:m)]);
        for k = 2:NK+1
            P = p(k-1,m-1); P_X = p(k-1,m); P_T = p(k,m-1); P_XT = p(k,m);
            Q = q(k-1,m-1); Q_X = q(k-1,m); Q_T = q(k,m-1); Q_XT = q(k,m);
%             f_continuityAndMontion(iContinuity{i}(k-1,m-1)) = C_q*R*T/A * dt/dl * (Q_XT - Q_T) + P_TAV/Z_T - P_AV/Z;
%             f_continuityAndMontion(iMotion{i}(k-1,m-1)) = (P_XT^2-P_T^2)/dl * (0.5) +  ...
%                 (Q_T+Q_XT)*signGf*(Q_T+Q_XT)*C_q^2*B^2/(2*F^2*D*A^2) + C_q^2*B^2/A^2 * (Q_XT^2-Q_T^2)/dl + ...
%                 C_q*P/A * (Q_T+Q_XT-Q-Q_X)/(2*dt);    
% v1:根据华科文章线性化的两个式子(不严格的情况下可行）
%             f_continuityAndMontion(iContinuity{i}(k-1,m-1)) = 1/B^2*(P_XT+P_T-P_X-P) + dt/dl/A*rhon*(Q_XT-Q_T+Q_X-Q);
%             f_continuityAndMontion(iMotion{i}(k-1,m-1)) = C_q/A*(Q_XT+Q_T-Q_X-Q) + dt/dl*(P_XT-P_T+P_X-P) + ...
%                             (C_q^2*dt*B^2)/(F^2*D*A^2)*avrgQP2*(Q_XT+Q_T+Q_X+Q)*signGf;
%             %统一量纲，便于数值计算
%             f_continuityAndMontion(iMotion{i}(k-1,m-1)) = f_continuityAndMontion(iMotion{i}(k-1,m-1)) / (dt/dl) * (1/B^2);
% v2: SOC relaxation:
%             f_continuityAndMontion(iContinuity{i}(k-1,m-1)) = 1/B^2*(P_XT+P_T-P_X-P) + dt/dl/A*C_q*(Q_XT-Q_T+Q_X-Q);            
% v3: 自适应线性化
            f_continuityAndMontion(iContinuity{i}(k-1,m-1)) = (P_XT+P_T-P_X-P) + B^2 * dt*C_q*(dl*A)^-1 * (Q_XT-Q_T+Q_X-Q);
            
        end
    end
end
% f = [cell2mat(f_continuity); cell2mat(f_motion)]';
f = f_continuityAndMontion';
end

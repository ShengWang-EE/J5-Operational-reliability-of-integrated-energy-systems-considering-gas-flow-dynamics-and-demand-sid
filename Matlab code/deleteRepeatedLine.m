function [newInfo_components] = deleteRepeatedLine(Info_components)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
nSystemStates = size(Info_components,1);
deleteLine = [];
for s = 1:nSystemStates
    if Info_components(s,2) == Info_components(s,3)
        deleteLine = [deleteLine s];
    end
end
Info_components(deleteLine,:) = []; % ɾȥ������������ʱ����ٵ�״̬
newInfo_components = Info_components;
end


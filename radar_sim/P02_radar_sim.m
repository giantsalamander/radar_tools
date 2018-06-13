﻿%--------------------------------------------------------------------------
%   雷达信号仿真通用模板
%   20180404
%   qwe14789cn@gmail.com
%--------------------------------------------------------------------------
%   初始化
disp('初始化...')
%--------------------------------------------------------------------------
clear;
clc;
warning off;

%--------------------------------------------------------------------------
%   读取波形数据
disp('读取波形数据...')
%--------------------------------------------------------------------------
load P01_waveform.mat

%--------------------------------------------------------------------------
%   参数设置
disp('参数设置...')
%--------------------------------------------------------------------------
%   射频15GHz
%--------------------------------------------------------------------------
fc = 38e9;                                                                  %射频
c = 299792458;                                                              %光速
lambda = c/fc;                                                              %波长
range_max = 50e3;                                                           %设定探测最大距离
T = PRT - Tp1 - Tp2;                                                        %采样时间

%--------------------------------------------------------------------------
%   得到信号频率
%--------------------------------------------------------------------------
disp('读取连续信号...')
%--------------------------------------------------------------------------
f_sample = 20e6;                                                             

%--------------------------------------------------------------------------
disp('约束关系自检...')
%--------------------------------------------------------------------------
down_n = fs/f_sample;
if fix(down_n)~=down_n
    disp('原始信号与采样速率不为整数倍关系,程序中断')
    return
end

%--------------------------------------------------------------------------
%   目标建模
disp('创建空间坐标关系...')
%--------------------------------------------------------------------------
car_dist    = [10000;0;0];                                                  %目标初始化位置
car_speed   = [10;0;0];                                                     %速度换算成m/s
radar_speed = [0;0;0];                                                      %雷达运动速度
radar_dist  = [0;0;0];                                                      %雷达平台坐标

%--------------------------------------------------------------------------
%   构造阵列形状
disp('构造阵列形状...')
%--------------------------------------------------------------------------
radar_array_dist = [0;0;0];
radar_array_speed =[0;0;0];

%--------------------------------------------------------------------------
%   构造传播信道
disp('生成目标模型参数特征...')
%--------------------------------------------------------------------------
range_c2r = norm(radar_dist-car_dist);                                      %雷达-目标 径向距离
car_rcs = db2pow(min(10*log10(range_c2r)+5,20));                            %径向距离计算汽车RCS
cartarget = phased.RadarTarget('MeanRCS',car_rcs,'PropagationSpeed',c,...
    'OperatingFrequency',fc);                                               %创建目标回波实例化，汽车rcs，传播速度，雷达发射中心频率

carmotion = phased.Platform('InitialPosition',car_dist,...
    'Velocity',car_speed);                                                  %创建目标运动实例化,初始化汽车坐标，汽车速度

%--------------------------------------------------------------------------
%   传播信道建模
disp('构造传播信道模型...')
%--------------------------------------------------------------------------
channel_t = phased.FreeSpace('PropagationSpeed',c,...
    'OperatingFrequency',fc,'SampleRate',fs,'TwoWayPropagation',false);

channel_r = phased.FreeSpace('PropagationSpeed',c,...
    'OperatingFrequency',fc,'SampleRate',fs,'TwoWayPropagation',false); 

%--------------------------------------------------------------------------
%   雷达系统设计
disp('雷达系统参数...')
%--------------------------------------------------------------------------
ant_aperture = 0.019*sqrt(3);                                               %天线孔径 单位 m2
ant_gain = aperture2gain(ant_aperture,lambda);                              %天线增益，单位dB

tx_ppower = 100;                                                             %发射机功率 单位W
% tx_gain = 9+ant_gain;                                                     %发射机增益
tx_gain = 100;                                                               %发射机增益

% rx_gain = 24+ant_gain;                                                    %接收机功率单位 dB
rx_gain = 100;                                                               %接收机功率单位 dB
rx_nf = 0.0;                                                                %噪声系数单位dB

transmitter = phased.Transmitter('PeakPower',tx_ppower,'Gain',tx_gain);     %生成发射机
receiver = phased.ReceiverPreamp('Gain',rx_gain,'NoiseFigure',rx_nf,...     %生成接收机
    'SampleRate',fs);

%--------------------------------------------------------------------------
%   雷达平台
disp('构造雷达平台运动函数...')
%--------------------------------------------------------------------------
radarmotion_point = phased.Platform('InitialPosition',radar_dist,...        %雷达平台运动
    'Velocity',radar_speed);

radarmotion_array = phased.Platform('InitialPosition',radar_array_dist,...  %雷达平台运动
    'Velocity',radar_array_speed);

%--------------------------------------------------------------------------
%   回波仿真
%--------------------------------------------------------------------------
Nsweep = 100;                                                               %发射脉冲数量

%--------------------------------------------------------------------------
xr_array = complex(zeros(round(f_sample * PRT,0),round(Nsweep,0),N));       %阵列缓冲器,快时间距离维,慢时间速度维

%--------------------------------------------------------------------------
%   生成图形属性，需要放在循环外
%--------------------------------------------------------------------------

for m = 1:Nsweep ,...
        disp(['脉冲发射-> ',...
        num2str(m),'/1024 当前进度-> ',...
        num2str(round(m/Nsweep*100,2)) ' %'])
    %----------------------------------------------------------------------
    %   停跳假设，更新雷达和目标的坐标，速度
    %----------------------------------------------------------------------
    [radar_pos,radar_vel] = radarmotion_point(PRT);                         %更新雷达位置，速度，时间间隔，扫频周期
    [radar_array_pos,radar_array_vel] = radarmotion_array(T);               %更新雷达阵列位置，速度，时间间隔，扫频周期
    
    [tgt_pos,tgt_vel] = carmotion(PRT);                                     %更新目标位置，速度，时间间隔，扫频周期

    %----------------------------------------------------------------------
    %   发射信号，通过发射机
    %----------------------------------------------------------------------
    txsig_1 = transmitter(sig);                                               %信号穿过发射机,延迟一个采样周期
    
    %----------------------------------------------------------------------
    %   信号传播并且目标反射
    %----------------------------------------------------------------------
    txsig_2 = channel_t(txsig_1,radar_pos,tgt_pos,radar_vel,tgt_vel);       %发射空间传播
    txsig_3 = cartarget(txsig_2);                                           %目标反射
    
    %----------------------------------------------------------------------
    %   信号传播
    %----------------------------------------------------------------------
    txsig_4 = channel_r(txsig_3,radar_pos,tgt_pos,radar_vel,tgt_vel);       %辅助通道接收空间传播延迟

    %----------------------------------------------------------------------
    %   信号通过接收机
    %----------------------------------------------------------------------
    txsig_5 = receiver(txsig_4);                                            %信号通过接收机
    
    %----------------------------------------------------------------------
    %   阵列天线数据
    %----------------------------------------------------------------------
    xr_array(:,m,:) = downsample(txsig_5_array,down_n);                     %阵列信号抽取，降低采样率为25Mhz
    
end

%--------------------------------------------------------------------------
%   切割信号点数
%--------------------------------------------------------------------------
xr_array = xr_array( (Tp1+Tp2)*f_sample+1 :end,:,:);

%--------------------------------------------------------------------------
%   数据保存
disp('保存回波数据，删除冗余数据...');
%--------------------------------------------------------------------------
save P02_radar_sim.mat xr_array lambda N R c sig sig1 sig2 down_n target_angle f_sample
clear;
%--------------------------------------------------------------------------
%   仿真完成
disp('雷达回波仿真完成...');
%--------------------------------------------------------------------------
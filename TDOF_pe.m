config

%% Application of the Kalman Filter, the Unscented Kalman Filter and the
%% Particle Filter to a Two Degree of Freedom linear system state and 
%% parameters estimation

%  The system assumed in this code is a two degree of freedom linear
%  system, which is described by the equations
%
%     d2x1(t)             dx1(t)      dx2(t)                                    d2x_g(t)
%  m1*------- + (c1 + c2)*------ - c2*------ + (k1 + k2)*x1(t) - k2*x2(t) = -m1*--------
%       dt2                 dt          dt                                        dt2
%
%  and
%
%     d2x2(t)      dx1(t)      dx2(t)                             d2x_g(t)
%  m2*------- - c2*------ - c2*------ - k2*x1(t) - k2*x2(t) = -m2*--------
%       dt2          dt          dt                                 dt2
%
%  where:
%   - m1, m2  : Mass of the bodies.
%   - c1, cs  : Damping coefficients of the system.
%   - k1, k2  : Stiffness of the system.
%   - x1, x2  : Displacement of the system, its derivatives represesents the
%               velocity and the acceleration.
%   - x_g : Its second derivative represents the ground acceleration, in
%           other words, the input of the system.
%
%  The excitation signal is the El Centro earthquake.

%% Response simulation

% The excitation signal
load elcentro_NS.dat
t   = elcentro_NS(:, 1)';   % times
x_g = elcentro_NS(:, 2)';   % ground acceleration
x_g = 9.82*x_g;             % (m/s^2)

dt = t(2) - t(1);           % time between measurements
N  = length(t);             % number of measurements

% The parameters are:
m1 = 1;                     % kN*s^2/m
m2 = 1;                     % kN*s^2/m
c1 = 0.6;                   % kN*s/m
c2 = 0.5;                   % kN*s/m
k1 = 12;                    % kN/m
k2 = 10;                    % kN/m

% Initial state

x_0 = [0; 0; 0; 0];         % the system starts from rest
nx  = length(x_0);          % number of states

x = zeros(nx, N+1);         % here the evolution of the system is going to 
x(:,1) = x_0;               % be saved

% The system is written in a state-space form
% X = [x1 x2 dx1/dt dx2/dt]'
F = @(x, u) [x(3)
             x(4)
             -((c1 + c2)*x(3) - c2*x(4) + (k1 + k2)*x(1) - k2*x(2))/m1
             -(-c2*x(3) + c2*x(4) - k2*x(1) + k2*x(2))/m2] - [0; 0; u; u];

% To simulate the system, the Runge-Kutta fourth order method is used.
for i = 1:N
    % [x_kmh] = rk_discrete(diff_eq,x_0,u,h)
    x(:,i+1) = rk_discrete(F, x(:,i), x_g(i), dt);
end

% Then, the total acceleration of the system is given as
acc = zeros(2, N);
acc(1, :) = -((c1+c2)*x(3, 2:end) - c2*x(4, 2:end) + (k1+k2)*x(1, 2:end) - k2*x(2))/m1;
acc(2, :) = -(-c2*x(3, 2:end) + c2*x(4, 2:end) - k2*x(1, 2:end) + k2*x(2, 2:end))/m2;

%% Measurements generation

% The filters will take the acceleration measurement as the observations
meas = zeros(2, N);
% the RMS noise-to-signal is used to add the noise
RMS = sqrt(sum(acc.^2, 2)/N);

noise_per = 0.05;           % 5% of the RMS is asumed as noise variance

% the measures are generated
meas = acc + noise_per*RMS.*randn(2, N);

%% Parameter estimation

% The number of parameters to estimate are
np = 4;

%% Unscented Kalman Filter implementation

% The 'Unscented Kalman Filter' (UKF) is useful to the estimation
% of the nonlinear dynamical system given by:
%
%               x_{k+1} = F(x_k, u_k) + v_k        (1)
%               y_k     = H(x_k)      + n_k        (2)

% The initial state and covariance matrix
x_0 = [0; 0; 0; 0; 2; 2; 0.2; 0.2];
P_0 = blkdiag(0.00001*eye(nx), 100*eye(np));

% We redifine the functions
F = @(x, u) [x(3)
             x(4)
             -((x(7)+x(8))*x(3) - x(8)*x(4) + (x(5)+x(6))*x(1) - x(6)*x(2))/m1
             -(-x(8)*x(3) + x(8)*x(4) - x(6)*x(1) + x(6)*x(2))/m2
             0
             0
             0
             0] - [0; 0; u; u; 0; 0; 0; 0];
H = @(x) HH(x, m1, m2);

% and a "soft" discretization of the covariance matrices
Q_nl = blkdiag(0.001*eye(nx), 0.01*eye(np))*dt;
R_nl = 0.01*eye(2)/dt;

% using the Unscented Kalman Filter
%[xh, P] = ukf(F,H,x_0,P_0,y,u,Rv,Rn,dt)
tic
[x_ukf, P_ukf] = ukf(F, H, x_0, P_0, meas, x_g, Q_nl, R_nl, dt);
toc

% to compute the standard deviation at each time step
sd_ukf = zeros(size(x_ukf));
for i = 1:N
    sd_ukf(:, i) = sqrt(diag(P_ukf{i}));
end

%% Particle Filter implementation

% The 'Particle Filter' (PF) is a Monte Carlo aproach to Bayesian
% filtering, is useful to the estimation of the nonlinear dynamical 
% system given by:
%
%               x_k = F(x_{k-1}, u_k, v_{k-1})	(1)
%               y_k = H(x_k, n_k)               (2)

% where the functions are redefined as
F_pf = @(x, u, v) rk_discrete(F, x, u, dt) + v;
H_pf = @(x, n)    H(x) + n;

% The number of particles used
Ns = 1000;

% the initial particles and their respective weigths are defined as
x_k0 = mvnrnd(x_0, P_0, Ns)';       % initial particles
w_k0 = 1/Ns*ones(1, Ns);            % initial weigths

% using the Particle Filter
% [x_k, w_k, m_xk] = p_f(F,H,x_k0,w_k0,z_k,u_k,Rv,Rn)
tic
[xx_pf, w_pf, x_pf] = p_f(F_pf, H_pf, x_k0, w_k0, meas, x_g, Q_nl, R_nl);
toc
% to compute the percentile 15.87 and 84.13 (that in a gaussian distribution
% are plus one and minus one standard deviation) at each time step
per_pf = zeros(16, N);
for i = 1:N
    per = prctile(xx_pf(:, :, i), [15.87 84.13], 2);
    per_pf(:, i) = per(:);
end

%% Parameters estimated
% The estimation from the second 20 to the end are used
est_ukf = sum(x_ukf(5:8, 1000:end), 2)/length(x_ukf(5, 1000:end));
est_pf  = sum(x_pf(5:8, 1000:end) , 2)/length(x_pf(5, 1000:end));

%% Relative Errors

% Unscented Kalman Filter error
err_d1_ukf = (x_ukf(1, :) - x(1, 2:end))./x(1, 2:end);
var_d1_ukf = var(err_d1_ukf); m_d1_ukf = mean(err_d1_ukf);
ms_d1_ukf = var_d1_ukf + m_d1_ukf^2;
err_v1_ukf = (x_ukf(3, :) - x(3, 2:end))./x(3, 2:end);
var_v1_ukf = var(err_v1_ukf); m_v1_ukf = mean(err_v1_ukf);
ms_v1_ukf = var_v1_ukf + m_v1_ukf^2;
m_d1_ukf, m_v1_ukf, var_d1_ukf, var_v1_ukf, ms_d1_ukf, ms_v1_ukf

err_d2_ukf = (x_ukf(2, :) - x(2, 2:end))./x(2, 2:end);
var_d2_ukf = var(err_d2_ukf); m_d2_ukf = mean(err_d2_ukf);
ms_d2_ukf = var_d2_ukf + m_d2_ukf^2;
err_v2_ukf = (x_ukf(4, :) - x(4, 2:end))./x(4, 2:end);
var_v2_ukf = var(err_v2_ukf); m_v2_ukf = mean(err_v2_ukf);
ms_v2_ukf = var_v2_ukf + m_v2_ukf^2;
m_d2_ukf, m_v2_ukf, var_d2_ukf, var_v2_ukf, ms_d2_ukf, ms_v2_ukf

err_k1_ukf = abs((est_ukf(1) - k1)/k1);
err_k2_ukf = abs((est_ukf(2) - k2)/k2);
err_c1_ukf = abs((est_ukf(3) - c1)/c1);
err_c2_ukf = abs((est_ukf(4) - c2)/c2);

% Particle Filter error
err_d1_pf = (x_pf(1, :) - x(1, 2:end))./x(1, 2:end);
var_d1_pf = var(err_d1_pf); m_d1_pf = mean(err_d1_pf);
ms_d1_pf = var_d1_pf + m_d1_pf^2;
err_v1_pf = (x_pf(3, :) - x(3, 2:end))./x(3, 2:end);
var_v1_pf = var(err_v1_pf); m_v1_pf = mean(err_v1_pf);
ms_v1_pf = var_v1_pf + m_v1_pf^2;
m_d1_pf, m_v1_pf, var_d1_pf, var_v1_pf, ms_d1_pf, ms_v1_pf

err_d2_pf = (x_pf(2, :) - x(2, 2:end))./x(2, 2:end);
var_d2_pf = var(err_d2_pf); m_d2_pf = mean(err_d2_pf);
ms_d2_pf = var_d2_pf + m_d2_pf^2;
err_v2_pf = (x_pf(4, :) - x(4, 2:end))./x(4, 2:end);
var_v2_pf = var(err_v2_pf); m_v2_pf = mean(err_v2_pf);
ms_v2_pf = var_v2_pf + m_v2_pf^2;
m_d2_pf, m_v2_pf, var_d2_pf, var_v2_pf, ms_d2_pf, ms_v2_pf

err_k1_pf = abs((est_pf(1) - k1)/k1);
err_k2_pf = abs((est_pf(2) - k2)/k2);
err_c1_pf = abs((est_pf(3) - c1)/c1);
err_c2_pf = abs((est_pf(4) - c2)/c2);

%% Plots

% Acceleration measures
figure
% 1st DOF
subplot(211)
hold on
ylabel('DOF 1 Acceleration [$m/s^{2}$]')
xlabel('Time [$s$]')
a11 = plot(t, acc(1, :),      '-r');
a21 = plot(t, meas(1, :), '.k', 'MarkerSize', 5);
legend([a11, a21], ...
       'True signal', 'Measurements', ...
       'Location', 'southeast')
axis tight
% 2nd DOF
subplot(212)
hold on
ylabel('DOF 2 Acceleration [$m/s^{2}$]')
xlabel('Time [$s$]')
a12 = plot(t, acc(2, :),      '-r');
a22 = plot(t, meas(2, :), '.k', 'MarkerSize', 5);
legend([a12, a22], ...
       'True signal', 'Measurements', ...
       'Location', 'southeast')
axis tight

% Unscented Kalman filter results

figure
% 1st DOF
% Displacement
subplot(211)
hold on

d_ukf = plot(t, x_ukf(1, :),  '-b');
d = plot(t, x(1, 2:end), '--r');
legend([d, d_ukf], 'True signal', 'UKF',  ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Displacement [$m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(1, :)+sd_ukf(1, :) x_ukf(1, end:-1:1)-sd_ukf(1, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Velocity
subplot(212)
hold on
v_ukf = plot(t, x_ukf(3, :),  '-b');
v = plot(t, x(3, 2:end), '--r');
ylabel('Velocity [$m/s$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(3, :)+sd_ukf(3, :) x_ukf(3, end:-1:1)-sd_ukf(3, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% Stiffness
subplot(211)
hold on

stiff_ukf = plot(t, x_ukf(5, :),  '-b');
stiff  = plot(t, k1*ones(size(x_pf(5, :))), '--r');
legend([stiff, stiff_ukf], 'True parameter', 'UKF', ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Stiffness [$kN/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(5, :)+sd_ukf(5, :) x_ukf(5, end:-1:1)-sd_ukf(5, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Damping
subplot(212)
hold on

damp_ukf = plot(t, x_ukf(7, :),  '-b');
damp  = plot(t, c1*ones(size(x_pf(7, :))), '--r');
ylabel('Damping [$kN \cdot s/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(7, :)+sd_ukf(7, :) x_ukf(7, end:-1:1)-sd_ukf(7, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% 2nd DOF
% Displacement
subplot(211)
hold on

d_ukf = plot(t, x_ukf(2, :),  '-b');
d = plot(t, x(2, 2:end), '--r');
legend([d, d_ukf], 'True signal', 'UKF',  ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Displacement [$m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(2, :)+sd_ukf(2, :) x_ukf(2, end:-1:1)-sd_ukf(2, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Velocity
subplot(212)
hold on

v_ukf = plot(t, x_ukf(4, :),  '-b');
v = plot(t, x(4, 2:end), '--r');
ylabel('Velocity [$m/s$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(4, :)+sd_ukf(4, :) x_ukf(4, end:-1:1)-sd_ukf(4, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% Stiffness
subplot(211)
hold on

stiff_ukf = plot(t, x_ukf(6, :),  '-b');
stiff  = plot(t, k2*ones(size(x_pf(1, :))), '--r');
legend([stiff, stiff_ukf], 'True parameter', 'UKF',  ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Stiffness [$kN/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(6, :)+sd_ukf(6, :) x_ukf(6, end:-1:1)-sd_ukf(6, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Damping
subplot(212)
hold on

damp_ukf = plot(t, x_ukf(8, :),  '-b');
damp  = plot(t, c2*ones(size(x_pf(1, :))), '--r');
ylabel('Damping [$kN \cdot s/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([x_ukf(8, :)+sd_ukf(8, :) x_ukf(8, end:-1:1)-sd_ukf(8, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


% Particle filter results

figure
% 1st DOF
% Displacement
subplot(211)
hold on
d_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(1, :) per_pf(9, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
d_pf = plot(t, x_pf(1, :),  '-b');
d = plot(t, x(1, 2:end), '--r');
leg_pf = sprintf('PF N = %d', Ns);
legend([d, d_pf, d_pf_sd], 'True signal', leg_pf, '$P_{15.87}$ and $P_{84.13}$', ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Displacement [$m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(1, :) per_pf(9, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Velocity
subplot(212)
hold on
v_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(3, :) per_pf(11, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
v_pf = plot(t, x_pf(3, :),  '-b');
v = plot(t, x(3, 2:end), '--r');
ylabel('Velocity [$m/s$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(3, :) per_pf(11, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% Stiffness
subplot(211)
hold on
stiff_pf_sd = fill([t t(end:-1:1)], ...
                   [per_pf(5, :) per_pf(13, end:-1:1)], ...
                   [0.8 0.8 1], 'EdgeColor', 'none');
stiff_pf = plot(t, x_pf(5, :),  '-b');
stiff  = plot(t, k1*ones(size(x_pf(1, :))), '--r');
leg_pf = sprintf('PF N = %d', Ns);
legend([stiff, stiff_pf, stiff_pf_sd], 'True parameter', leg_pf, '$P_{15.87}$ and $P_{84.13}$', ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Stiffness [$kN/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(5, :) per_pf(13, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Damping
subplot(212)
hold on
damp_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(7, :) per_pf(15, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
damp_pf = plot(t, x_pf(7, :),  '-b');
damp = plot(t, c1*ones(size(x_pf(1, :))), '--r');
ylabel('Damping [$kN \cdot s/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(7, :) per_pf(15, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% 2nd DOF
% Displacement
subplot(211)
hold on
d_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(2, :) per_pf(10, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
d_pf = plot(t, x_pf(2, :),  '-b');
d = plot(t, x(2, 2:end), '--r');
leg_pf = sprintf('PF N = %d', Ns);
legend([d, d_pf, d_pf_sd], 'True signal', leg_pf, '$P_{15.87}$ and $P_{84.13}$', ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Displacement [$m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(2, :) per_pf(10, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Velocity
subplot(212)
hold on
v_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(4, :) per_pf(12, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
v_pf = plot(t, x_pf(4, :),  '-b');
v = plot(t, x(4, 2:end), '--r');
ylabel('Velocity [$m/s$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(4, :) per_pf(12, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% Stiffness
subplot(211)
hold on
stiff_pf_sd = fill([t t(end:-1:1)], ...
                   [per_pf(6, :) per_pf(14, end:-1:1)], ...
                   [0.8 0.8 1], 'EdgeColor', 'none');
stiff_pf = plot(t, x_pf(6, :),  '-b');
stiff  = plot(t, k2*ones(size(x_pf(1, :))), '--r');
leg_pf = sprintf('PF N = %d', Ns);
legend([stiff, stiff_pf, stiff_pf_sd], 'True parameter', leg_pf, '$P_{15.87}$ and $P_{84.13}$', ...
       'Location', 'southeast', ...
       'Orientation', 'horizontal')
ylabel('Stiffness [$kN/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(6, :) per_pf(14, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])

% Damping
subplot(212)
hold on
damp_pf_sd = fill([t t(end:-1:1)], ...
               [per_pf(8, :) per_pf(16, end:-1:1)], ...
               [0.8 0.8 1], 'EdgeColor', 'none');
damp_pf = plot(t, x_pf(8, :),  '-b');
damp = plot(t, c2*ones(size(x_pf(1, :))), '--r');
ylabel('Damping [$kN \cdot s/m$]')
xlabel('Time [$s$]')
ymax = ceil(max(abs([per_pf(8, :) per_pf(16, end:-1:1)]))*10)/10;
axis([min(t) max(t) -ymax ymax])


figure
% 1st DOF
% Displacement Error
subplot(211)
hold on
err = [err_d1_ukf; err_d1_pf];
b_w = (max(max(err, [], 2)) - min(min(err, [], 2)))/(3*ceil(sqrt(N)));
e_d_ukf = histogram(err_d1_ukf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
e_d_pf  = histogram(err_d1_pf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
l_pf = sprintf('PF N = %d', Ns);
legend([e_d_ukf, e_d_pf], 'UKF', l_pf, ...
       'Location', 'northwest', ...
       'Orientation', 'horizontal')
ylabel('Displacement error')
axis tight

% Velocity Error
subplot(212)
hold on
err = [err_v1_ukf; err_v1_pf];
b_w = (max(max(err, [], 2)) - min(min(err, [], 2)))/(3*ceil(sqrt(N)));
e_v_ukf = histogram(err_v1_ukf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
e_v_pf  = histogram(err_v1_pf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
ylabel('Velocity error')
axis tight


figure
% 2nd DOF
% Displacement Error
subplot(211)
hold on
err = [err_d2_ukf; err_d2_pf];
b_w = (max(max(err, [], 2)) - min(min(err, [], 2)))/(3*ceil(sqrt(N)));
e_d_ukf = histogram(err_d2_ukf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
e_d_pf  = histogram(err_d2_pf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
l_pf = sprintf('PF N = %d', Ns);
legend([e_d_ukf, e_d_pf], 'UKF', l_pf, ...
       'Location', 'northeast', ...
       'Orientation', 'horizontal')
ylabel('Displacement error')
axis tight

% Velocity Error
subplot(212)
hold on
err = [err_v2_ukf; err_v2_pf];
b_w = (max(max(err, [], 2)) - min(min(err, [], 2)))/(3*ceil(sqrt(N)));
e_v_ukf = histogram(err_v2_ukf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
e_v_pf  = histogram(err_v2_pf, ...
                    'BinWidth', b_w, ...
                    'Normalization', 'probability');
ylabel('Velocity error')
axis tight


function y = HH(xx,m1,m2)

    H = @(x)    [-((x(7)+x(8))*x(3) - x(8)*x(4) + (x(5)+x(6))*x(1) - x(6)*x(2))/m1
                 -(-x(8)*x(3) + x(8)*x(4) - x(6)*x(1) + x(6)*x(2))/m2];

    for i = 1:size(xx,2)
        y(:, i) = H(xx(:,i));
    end
end
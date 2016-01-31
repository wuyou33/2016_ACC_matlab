% 11 June 15
% controller 

function [u_f, u_m, R_des, ang_vel_des, ang_vel_dot_des, Psi, err_att, err_ang_vel] ...
    = controller(t,state, constants)

% redefine the state vector
pos = state(1:3);
vel = state(4:6);
R = reshape(state(7:15),3,3); % rotation matrix from body to inertial frame
ang_vel = state(16:18);
delta_est = state(19:21); % adaptive control term to estimate fixed disturbance

% extract out constants
J = constants.J;
G = constants.G;
kr = constants.kp;
kw = constants.kw;
sen = constants.sen;
alpha = constants.alpha;
con_angle = constants.con_angle;
con = constants.con;
W = constants.W;

% position
xd = constants.xd;
xo = constants.xo;
veld = constants.vd;

det_shell = constants.det_shell; % detection shell radius

P = constants.P;
N = constants.N;
alpha_pos = constants.alpha_pos;
beta = constants.beta;

kx = constants.kx;
kv = constants.kv;

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ATTITUDE CONTROL
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% desired attitude
[R_des, ang_vel_des, ang_vel_dot_des] = des_attitude(t,constants);

% attitude error function
% Psi = 1/2*trace(G*(eye(3,3)-R_des'*R));
% rotate body vector to inertial frame
psi_attract = 1/2*trace(G*(eye(3,3)-R_des'*R));
dA = 1/2*vee_map(G*R_des'*R - R'*R_des*G);

switch constants.avoid_switch
    case 'true' % add the avoidance term
        sen_inertial = R * sen;
        
        % loop over the constraints and form a bunch of repelling function
        psi_avoid = zeros(constants.num_con,1);
        dB = zeros(3,constants.num_con);
        for ii = 1:constants.num_con
            
            % calculate error function
            psi_avoid(ii) = -1/alpha*log((cos(con_angle(ii))-dot(sen_inertial,con(:,ii)))/(1+cos(con_angle(ii))));
            
            dB(:,ii) = 1/alpha/(dot(sen_inertial,con(:,ii))-cos(con_angle(ii)))*hat_map(R'*con(:,ii))*sen;
        end
        
        Psi = psi_attract*(sum(psi_avoid)+1);
        
        err_att = dA*(sum(psi_avoid)+1) + sum(dB.*psi_attract,2);
        
    case 'false'
        err_att = dA;
        Psi = psi_attract;
end

err_ang_vel = ang_vel - R'*R_des*ang_vel_des;

alpha_d = -hat_map(ang_vel)*R'*R_des*ang_vel_des + R'*R_des*ang_vel_dot_des;

% compute the control input

% u_m = -kp*err_att - kv*err_vel + cross(ang_vel,J*ang_vel) + J*alpha_d - W * theta_est;
switch constants.adaptive_switch
    case 'true'
        u_m = -kr*err_att - kw*err_ang_vel + cross(ang_vel,J*ang_vel) -W * delta_est;
    case 'false'
        u_m = -kr*err_att - kw*err_ang_vel + cross(ang_vel,J*ang_vel);
end

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% POSITION CONTROL
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compute the control
dA_pos = P*(pos-xd);
dR_pos = -alpha_pos*exp(-(pos-xo)'*inv(N)*(pos-xo))*inv(N)*(pos-xo);

A = 1/2*(pos-xd)'*P*(pos-xd);
R = 1+alpha_pos/2*exp(-(pos-xo)'*inv(N)*(pos-xo));

% err_pos = dA_pos*R + dR_pos*A;
err_pos = dA_pos;
err_vel = vel - veld;
% u = -kx*err_pos - kv*err_vel;
%% Gyroscopic force to avoid obstacle
% compute distance to obstacle
dist_obs = xo - pos;

% check if we are within the detection shell
S = zeros(3,3);
if norm(dist_obs) < (det_shell + beta)
    % decide on direction to rotate
    vec = hat_map(dist_obs/norm(dist_obs))*vel/norm(vel);

    if norm(vec) > 1e-6
        S = hat_map(vec);
    else
        S = hat_map([1 1 1]/norm([1 1 1]));
    end

end

u_f = -kx*err_pos - kv*err_vel + 1/2*norm(constants.initial_state(1:3)-xd)^2*S*vel;
% u_f = zeros(3,1);
end

function [R_des, ang_vel_des, ang_vel_dot_des] = des_attitude(t,constants)

% use 3-2-1 euler angle sequence for the desired body to inertial attitude
% trajectory
a = 2*pi/(20/10);
% a = pi;
b = pi/9;

phi = b*sin(a*t); % third rotation
theta = b*cos(a*t); % second rotation
psi = 0; % first rotation

phi_d = b*a*cos(a*t);
theta_d = -b*a*sin(a*t);
psi_d = 0;

phi_dd = -b*a^2*sin(a*t);
theta_dd = -b*a^2*cos(a*t);
psi_dd = 0;

% euler 3-2-1 sequence
% R_des = ROT1(phi)*ROT2(theta)*ROT3(psi);
R_des = constants.Rd;
% R_des = R_des'; % Dr. Lee is using the transpose of the attitude matrix

% convert the euler angle sequence to the desired angular velocity vector
ang_vel_des = zeros(3,1);

% ang_vel_des(1) = -psi_d*sin(theta) + phi_d;
% ang_vel_des(2) = psi_d*cos(theta)*sin(phi) + theta_d*cos(phi);
% ang_vel_des(3) = psi_d*cos(theta)*cos(phi) - theta_d*sin(phi);

ang_vel_dot_des = zeros(3,1);
% 
% ang_vel_dot_des(1) = -psi_dd*sin(theta) - theta_d*psi_d*cos(theta) + phi_dd;
% ang_vel_dot_des(2) = psi_dd*cos(theta)*sin(phi) - theta_d*psi_d*sin(theta)*sin(phi) ...
%                     + psi_d*phi_d*cos(theta)*cos(phi) + theta_dd*cos(phi) ...
%                     -theta_d*phi_d*sin(phi);
% ang_vel_dot_des(3) = psi_dd*cos(theta)*cos(phi) - theta_d*psi_d*sin(theta)*cos(phi) ...
%                     - phi_d*psi_d*cos(theta)*sin(phi) - theta_dd*sin(phi) ...
%                     - theta_d*phi_d*cos(phi);
end
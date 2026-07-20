% Clear previous connections
clear m81; clc;

% 1. Initialize the Controller
m81 = M81Controller(1);

% 2. Check your contacts (The diagnostic tool we built)
m81.check_contacts(1e-6);

% 3. Run a Delta Mode Experiment
R = m81.run_delta_mode(1e-6, 10, '2-wire');

% 4. Run an I-V Sweep
[I, V] = m81.run_iv_sweep(-1e-6, 1e-6, 21, '4-wire');

% Note: When you clear 'm81' or close MATLAB, 
% the output automatically turns off safely.
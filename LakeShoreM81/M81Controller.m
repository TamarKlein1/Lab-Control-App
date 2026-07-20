classdef M81Controller < handle
    % M81Controller: A MATLAB wrapper for the Lake Shore M81 Python Driver
    % UPDATED: Now uses '2-wire' and '4-wire'.
    
    properties
        ssm      % The Python SSMSystem object
        src      % The Python Source Module object
        meas     % The Python Measure Module object
        slot = 1 % Default slot
    end
    
    methods
        function obj = M81Controller(module_slot)
            % Constructor: Connects to the M81
            if nargin < 1, module_slot = 1; end
            obj.slot = module_slot;
            
            try
                disp('Connecting to M81 via Python driver...');
                py.importlib.import_module('lakeshore');
                obj.ssm = py.lakeshore.SSMSystem();
                obj.src = obj.ssm.get_source_module(int32(obj.slot));
                obj.meas = obj.ssm.get_measure_module(int32(obj.slot));
                
                idn = char(obj.ssm.query('*IDN?'));
                fprintf('Connected! ID: %s\n', strtrim(idn));
            catch ME
                error('Connection Failed. Check "pyenv" setup.\nError: %s', ME.message);
            end
        end
        
        function delete(obj)
            % Safety Shutdown
            try
                if ~isempty(obj.src)
                    obj.src.set_current_amplitude(0.0);
                    obj.src.disable();
                    disp('M81 Output Disabled.');
                end
            catch
            end
        end
        
        function mode_str = resolve_mode(~, input_mode)
            % Internal Helper: Converts '2-wire' -> 'LOCal'
            % Internal Helper: Converts '4-wire' -> 'REMote'
            if strcmpi(input_mode, '4-wire')
                mode_str = 'REMote';
            elseif strcmpi(input_mode, '2-wire')
                mode_str = 'LOCal';
            else
                error('Invalid Mode! Use "2-wire" or "4-wire".');
            end
        end
        
        function configure_experiment(obj, user_mode)
            % Configure instrument settings
            scpi_mode = obj.resolve_mode(user_mode);
            
            % Set Sense Mode
            obj.src.set_voltage_sense_mode(scpi_mode);
            obj.meas.set_voltage_sense_mode(scpi_mode);
            
            % Set Source/Measure defaults
            obj.src.set_source_function('CURRENT');
            obj.src.set_shape('DC');
            obj.src.set_voltage_limit(10.0);
            obj.meas.set_measure_function('VOLTAGE');
            obj.meas.setup_dc_measurement(pyargs('nplc', 1));
        end
        
        function [R_avg, R_data] = run_delta_mode(obj, current_amps, num_points, user_mode)
            % Run Delta Mode Resistance
            if nargin < 4, user_mode = '2-wire'; end
            
            fprintf('\n--- Delta Mode (%s) ---\n', user_mode);
            obj.configure_experiment(user_mode);
            
            obj.src.enable();
            pause(1.0); 
            
            R_data = zeros(num_points, 1);
            
            for i = 1:num_points
                % Positive
                obj.src.set_current_amplitude(current_amps);
                pause(0.2);
                v_pos = double(obj.meas.get_dc());
                
                % Negative
                obj.src.set_current_amplitude(-current_amps);
                pause(0.2);
                v_neg = double(obj.meas.get_dc());
                
                if abs(v_pos) > 1e20 || abs(v_neg) > 1e20
                    fprintf('Reading %d: OVERLOAD\n', i);
                    R_data(i) = NaN;
                else
                    delta_V = v_pos - v_neg;
                    delta_I = current_amps - (-current_amps);
                    R = delta_V / delta_I;
                    R_data(i) = R;
                    fprintf('Reading %d: %.4f Ohms\n', i, R);
                end
            end
            
            R_avg = mean(R_data, 'omitnan');
            fprintf('Average: %.4f Ohms\n', R_avg);
            
            obj.src.set_current_amplitude(0.0);
            obj.src.disable();
        end
        
        function [I_data, V_data] = run_iv_sweep(obj, start_i, stop_i, points, user_mode)
            % Run I-V Sweep
            if nargin < 5, user_mode = '2-wire'; end
            
            fprintf('\n--- I-V Sweep (%s) ---\n', user_mode);
            obj.configure_experiment(user_mode);
            
            I_data = linspace(start_i, stop_i, points);
            V_data = zeros(1, points);
            
            obj.src.enable();
            pause(1.0);
            
            for k = 1:points
                i_val = I_data(k);
                obj.src.set_current_amplitude(i_val);
                pause(0.15);
                v_val = double(obj.meas.get_dc());
                
                if abs(v_val) > 1e20
                    V_data(k) = NaN;
                else
                    V_data(k) = v_val;
                end
            end
            
            obj.src.set_current_amplitude(0.0);
            obj.src.disable();
            
            % Plot
            figure;
            plot(I_data*1e6, V_data*1e3, '-o', 'LineWidth', 1.5);
            xlabel('Current (\muA)');
            ylabel('Voltage (mV)');
            title(['I-V Sweep (' user_mode ')']);
            grid on;
        end
        
        function check_contacts(obj, test_current)
            % Diagnosis
            fprintf('\n--- Contact Check ---\n');
            
            disp('1. Measuring 2-wire...');
            r2 = obj.run_delta_mode(test_current, 3, '2-wire');
            
            disp('2. Measuring 4-wire...');
            r4 = obj.run_delta_mode(test_current, 3, '4-wire');
            
            fprintf('\n=== REPORT ===\n');
            if isnan(r4)
                fprintf('CRITICAL: 4-wire Open Circuit. Use 2-wire.\n');
            else
                contact_R = r2 - r4;
                fprintf('Sample R:  %.4f Ohms\n', r4);
                fprintf('Contact R: %.4f Ohms (Total)\n', contact_R);
            end
        end
    end
end
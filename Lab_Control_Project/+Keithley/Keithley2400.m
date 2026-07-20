classdef Keithley2400 < handle
    % KEITHLEY2400 MATLAB Wrapper for the Keithley 2400 SourceMeter
    % Includes a 'SIM' mode for offline testing.
    
    properties (Access = private)
        VisaObj             % Holds the visadev connection object
        IsSimulated = false % Flag to check if we are in test mode
        SimVoltage = 0      % Stores the last set voltage for generating mock data
    end
    
    methods
        %% Constructor: Connect and Initialize
        function obj = Keithley2400(visaAddress)
            % Check if user wants to run in Simulation Mode
            if strcmpi(visaAddress, 'SIM')
                obj.IsSimulated = true;
                fprintf('Started Keithley 2400 in SIMULATION mode.\n');
                return; % Exit the constructor early, do not connect to hardware
            end
            
            try
                % Establish connection via visa resource string
                obj.VisaObj = visadev(visaAddress);
                writeline(obj.VisaObj, '*RST'); 
                writeline(obj.VisaObj, ':SYST:BEEP:STAT OFF'); 
                fprintf('Successfully connected to Keithley 2400 at %s\n', visaAddress);
            catch ME
                error('Failed to connect to %s. Error: %s', visaAddress, ME.message);
            end
        end
        
        %% Destructor: Clean Disconnect
        function delete(obj)
            if obj.IsSimulated
                fprintf('Closed simulated Keithley 2400.\n');
                return;
            end
            
            if ~isempty(obj.VisaObj) && isvalid(obj.VisaObj)
                writeline(obj.VisaObj, ':OUTP OFF');
                clear obj.VisaObj;
                fprintf('Keithley 2400 connection closed.\n');
            end
        end
        
        %% Setup: Voltage Source Mode
        function setVoltageSource(obj, complianceCurrent)
            if obj.IsSimulated
                fprintf('[SIM] Configured to Voltage Source. Compliance: %e A\n', complianceCurrent);
                return;
            end
            
            writeline(obj.VisaObj, ':SOUR:FUNC VOLT');
            writeline(obj.VisaObj, ':SENS:FUNC "CURR"');
            writeline(obj.VisaObj, sprintf(':SENS:CURR:PROT %e', complianceCurrent));
        end
        
        %% Action: Turn Output ON/OFF
        function setOutput(obj, state)
            if obj.IsSimulated
                fprintf('[SIM] Output set to %s\n', num2str(state));
                return;
            end
            
            if strcmpi(state, 'ON') || state == 1
                writeline(obj.VisaObj, ':OUTP ON');
            else
                writeline(obj.VisaObj, ':OUTP OFF');
            end
        end
        
        %% Action: Set Voltage Level
        function setVoltage(obj, volts)
            if obj.IsSimulated
                obj.SimVoltage = volts; % Save this so readData knows what to calculate
                return;
            end
            
            writeline(obj.VisaObj, sprintf(':SOUR:VOLT:LEV %e', volts));
        end
        
        %% Action: Read Data
        function [voltage, current, resistance] = readData(obj)
            if obj.IsSimulated
                % Generate fake data based on Ohm's Law (V = IR)
                % Let's pretend we are measuring a 1 kOhm sample with some noise
                fakeResistance = 1000; 
                noise = randn() * 1e-6; % Adding 1 microamp of random Gaussian noise
                
                voltage = obj.SimVoltage;
                current = (voltage / fakeResistance) + noise;
                resistance = voltage / current;
                return;
            end
            
            % Actual hardware reading
            writeline(obj.VisaObj, ':READ?');
            rawData = readline(obj.VisaObj);
            dataArray = str2double(split(rawData, ','));
            
            voltage = dataArray(1);
            current = dataArray(2);
            resistance = dataArray(3);
        end
        %% Setup: Current Source Mode
        function setCurrentSource(obj, complianceVoltage)
            if obj.IsSimulated
                fprintf('[SIM] Configured to Current Source. Compliance: %e V\n', complianceVoltage);
                return;
            end
            writeline(obj.VisaObj, ':SOUR:FUNC CURR');
            writeline(obj.VisaObj, ':SENS:FUNC "VOLT"');
            writeline(obj.VisaObj, sprintf(':SENS:VOLT:PROT %e', complianceVoltage));
        end

        %% Action: Set Current Level
        function setCurrent(obj, amps)
            if obj.IsSimulated
                obj.SimVoltage = amps * 1000; % Simple mock logic (V = I*R, assuming 1kOhm)
                return;
            end
            writeline(obj.VisaObj, sprintf(':SOUR:CURR:LEV %e', amps));
        end

        %% Setup: Set NPLC (Integration Time)
        function setNPLC(obj, nplc)
            if obj.IsSimulated
                fprintf('[SIM] NPLC set to %f\n', nplc);
                return;
            end
            % Set NPLC for both voltage and current sensing
            writeline(obj.VisaObj, sprintf(':SENS:VOLT:NPLC %f', nplc));
            writeline(obj.VisaObj, sprintf(':SENS:CURR:NPLC %f', nplc));
        end
    end
end
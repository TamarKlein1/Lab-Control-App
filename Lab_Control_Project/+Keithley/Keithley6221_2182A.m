classdef Keithley6221_2182A < handle
    % KEITHLEY6221_2182A MATLAB Wrapper for the Delta Mode System
    % 6221 Current Source (Master) + 2182A Nanovoltmeter (Slave)
    
    properties (Access = private)
        VisaObj             % Holds the visadev connection object to the 6221
        IsSimulated = false % Flag to check if we are in test mode
    end
    
    methods
        %% Constructor: Connect and Initialize
        function obj = Keithley6221_2182A(visaAddress)
            if strcmpi(visaAddress, 'SIM')
                obj.IsSimulated = true;
                fprintf('Started 6221/2182A System in SIMULATION mode.\n');
                return;
            end
            
            try
                obj.VisaObj = visadev(visaAddress);
                
                % Reset the 6221 Master
                writeline(obj.VisaObj, '*RST');
                
                % Reset the 2182A Slave via the Serial Link
                obj.sendTo2182A('*RST');
                pause(0.5); % Give the nanovoltmeter a moment to boot back up
                
                fprintf('Successfully connected to 6221/2182A System at %s\n', visaAddress);
            catch ME
                error('Failed to connect to %s. Error: %s', visaAddress, ME.message);
            end
        end
        
        %% Destructor: Clean Disconnect
        function delete(obj)
            if obj.IsSimulated
                fprintf('Closed simulated 6221/2182A System.\n');
                return;
            end
            
            if ~isempty(obj.VisaObj) && isvalid(obj.VisaObj)
                % Turn off 6221 output for safety
                writeline(obj.VisaObj, 'OUTP OFF');
                clear obj.VisaObj;
                fprintf('6221/2182A connection closed safely.\n');
            end
        end
        
        %% --- 6221 MASTER COMMANDS (Current Source) ---
        
        function setCurrent(obj, amps)
            if obj.IsSimulated
                fprintf('[SIM 6221] Source Current set to %e A\n', amps);
                return;
            end
            % Ensure it is in DC function, then set the level
            writeline(obj.VisaObj, 'SOUR:CURR:FUNC DC'); 
            writeline(obj.VisaObj, sprintf('SOUR:CURR %e', amps));
        end
        
        function setOutput(obj, state)
            if obj.IsSimulated
                fprintf('[SIM 6221] Output set to %s\n', num2str(state));
                return;
            end
            if strcmpi(state, 'ON') || state == 1
                writeline(obj.VisaObj, 'OUTP ON');
            else
                writeline(obj.VisaObj, 'OUTP OFF');
            end
        end
        
        function setCompliance(obj, volts)
            if obj.IsSimulated
                fprintf('[SIM 6221] Voltage Compliance set to %f V\n', volts);
                return;
            end
            % 6221 Compliance is a voltage limit
            writeline(obj.VisaObj, sprintf('SOUR:CURR:COMP %f', volts));
        end
        
       %% --- DELTA MODE SETUP ---
        
        function setupDeltaMode(obj, I_max, I_min, repeats, mode, delayTime)
            if obj.IsSimulated; return; end
            
            % ALWAYS abort any existing armed states before configuring!
            writeline(obj.VisaObj, 'SOUR:SWE:ABOR');
            pause(0.1);
            
            writeline(obj.VisaObj, sprintf('SOUR:DELT:HIGH %e', I_max));
            writeline(obj.VisaObj, sprintf('SOUR:DELT:LOW %e', I_min));
            writeline(obj.VisaObj, sprintf('SOUR:DELT:DEL %e', delayTime));
            
            if strcmpi(mode, 'continuous')
                writeline(obj.VisaObj, 'SOUR:DELT:COUN INF');
            else
                writeline(obj.VisaObj, sprintf('SOUR:DELT:COUN %d', repeats));
            end
        end
        
        function armDeltaMode(obj)
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, 'SOUR:DELT:ARM');
        end
        
        function disarmDeltaMode(obj)
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, 'SOUR:SWE:ABOR');
        end
        
        function deltaVolts = runDeltaMeasurement(obj)
            if obj.IsSimulated
                pause(0.5); 
                deltaVolts = 1e-6 + randn()*1e-9;
                return;
            end
            
            % Trigger the ALREADY ARMED measurement
            writeline(obj.VisaObj, 'INIT:IMM');
            
            % Block MATLAB execution until the 6221 signals the sweep is complete
            writeline(obj.VisaObj, '*OPC?');
            readline(obj.VisaObj);
            
            % Fetch the trace data buffer from the 6221
            rawStr = writeread(obj.VisaObj, 'SENS:DATA?');
            
            % Parse the first numerical value
            dataPoints = str2double(split(rawStr, ','));
            if ~isempty(dataPoints)
                deltaVolts = dataPoints(1);
            else
                deltaVolts = NaN;
            end
        end
        %% --- 2182A SLAVE COMMANDS (Nanovoltmeter) ---
        
        function setVoltageRange(obj, range)
            if strcmpi(range, 'AUTO')
                obj.sendTo2182A('SENS:VOLT:DC:RANG:AUTO ON');
            else
                obj.sendTo2182A('SENS:VOLT:DC:RANG:AUTO OFF');
                obj.sendTo2182A(sprintf('SENS:VOLT:DC:RANG %f', range));
            end
        end
        
        function setNPLC(obj, nplc)
            obj.sendTo2182A(sprintf('SENS:VOLT:DC:NPLC %f', nplc));
        end
        
        function setChannel(obj, ch)
            % Supports 1, 2, or 'both'
            if isnumeric(ch) && (ch == 1 || ch == 2)
                obj.sendTo2182A(sprintf('SENS:CHAN %d', ch));
            elseif strcmpi(ch, 'both')
                % Reading both requires configuring the 2182A to scan
                obj.sendTo2182A('ROUT:SCAN (@1,2)');
                obj.sendTo2182A('ROUT:SCAN:LSEL INT');
                warning('Channel set to "both". The getReading() method will return a comma-separated string of two values.');
            else
                error('Invalid channel. Use 1, 2, or ''both''.');
            end
        end
        
        function val = getReading(obj)
            % Triggers and fetches a standard DC voltage reading
            if obj.IsSimulated
                val = 1e-6 + (randn() * 1e-9); % 1 uV with 1 nV noise
                return;
            end
            
            rawData = obj.query2182A(':READ?');
            
            % Convert the returned string to a double
            % (If 'both' channels are active, this returns an array)
            val = str2double(split(rawData, ',')); 
        end
        
        %% --- INTERNAL PROXY HELPERS ---
        % These hide the complex RS-232 proxy routing from your main scripts.
        
    private
        function sendTo2182A(obj, cmd)
            if obj.IsSimulated
                fprintf('[SIM 2182A Proxy] Sent: %s\n', cmd);
                return;
            end
            % Tell the 6221 to push a command down the serial cable
            writeline(obj.VisaObj, sprintf('SYST:COMM:SER:SEND "%s"', cmd));
        end
        
        function response = query2182A(obj, cmd)
            if obj.IsSimulated
                response = '0.000000';
                return;
            end
            % Send the query command to the 2182A
            obj.sendTo2182A(cmd);
            
            % Instruct the 6221 to grab the resulting string from the 2182A's buffer
            writeline(obj.VisaObj, 'SYST:COMM:SER:ENT?');
            
            % Read the grabbed string into MATLAB
            response = readline(obj.VisaObj);
        end
    end
end
classdef QDBridge < handle
    % QDBRIDGE MATLAB Wrapper for the legacy QD Resistivity / AC Transport Bridge
    % Communicates using the active .NET session from QDPPMS.
    
    properties (Access = private)
        NetObj              % Points to the shared .NET object
        IsSimulated = false % Flag for offline testing
    end
    
    methods

        %% Constructor: Link to the active PPMS session
        function obj = QDBridge(ppmsHandle)
            % Check if the passed PPMS object is in simulation mode
            try
                if ismethod(ppmsHandle, 'getCurrentTemperature') && ...
                   ppmsHandle.getCurrentTemperature() == 300 && contains(class(ppmsHandle), 'SIM')
                    obj.IsSimulated = true;
                end
            catch
            end
            
            if obj.IsSimulated
                fprintf('Started QD Bridge in SIMULATION mode.\n');
                return;
            end
            
            % Grab the active .NET object from the QDPPMS wrapper, 
            % OR accept the raw .NET object directly if passed from the command line.
            try
                if ismethod(ppmsHandle, 'getNetObject')
                    obj.NetObj = ppmsHandle.getNetObject();
                else
                    obj.NetObj = ppmsHandle; % Assume it is already the raw .NET object
                end
                fprintf('QD Bridge successfully linked to active PPMS session.\n');
            catch ME
                error('Failed to link to PPMS session. Error: %s', ME.message);
            end
        end
        
        %% --- ACTION: READ CHANNEL DATA ---
        function [value, retCode] = readChannel(obj, channelNum, isFast)
            % Reads a specific item/channel from the PPMS data stream.
            % 'isFast' is an optional boolean (default = false).
            
            if nargin < 3
                isFast = false;
            end
            
            if obj.IsSimulated
                value = 45.2 + (randn() * 0.05); % Mock resistance
                retCode = 0;
                pause(0.1);
                return;
            end
            
            % 1. Format inputs to exact .NET types
            chanInt = int32(channelNum);
            dummyResult = double(0.0);
            
            % 2. Execute the read via GetPPMSItem
            [retCode, value] = obj.NetObj.GetPPMSItem(chanInt, dummyResult, isFast);
        end
        
       %% --- ACTION: SEND RAW BRIDGE COMMAND ---
        function [reply, errorStr, retCode] = sendCommand(obj, cmdString, deviceID, timeoutSec)
            if nargin < 3; deviceID = 0; end
            if nargin < 4; timeoutSec = 2.0; end
            
            if obj.IsSimulated
                fprintf('[SIM BRIDGE] Sent command: %s\n', cmdString);
                reply = 'SIM_OK';
                errorStr = '';
                retCode = 0;
                return;
            end
            
            % Fix: Initialize explicit native .NET string objects for ref parameters
            dummyReply = System.String('');
            dummyError = System.String('');
            
            % Format inputs
            devInt = int32(deviceID);
            timeoutDbl = double(timeoutSec);
            
            % Execute the command
            [retCode, rawReply, rawError] = obj.NetObj.SendPPMSCommand(cmdString, dummyReply, dummyError, devInt, timeoutDbl);
            
            % Cast safely back to MATLAB chars
            reply = char(rawReply);
            errorStr = char(rawError);
        end
         %% --- ACTION: CONFIGURE CHANNEL LIMITS (Read-Modify-Write) ---
        function setChannelLimits(obj, channelNum, current_uA, power_uW, voltage_mV)
            % Configures the limits for a specific bridge channel.
            % Pass 'NaN' for any parameter you want to leave unchanged.
            % Example: bridge.setChannelLimits(1, 1000, NaN, NaN) % Only changes current to 1000 uA
            
            if obj.IsSimulated
                fprintf('[SIM BRIDGE] Configured Ch %d: I=%.2f uA, P=%.2f uW, V=%.2f mV\n', channelNum, current_uA, power_uW, voltage_mV);
                return;
            end
            
            % 1. Query the existing configuration
            queryCmd = sprintf('BRIDGE? %d', channelNum);
            [reply, err, ~] = obj.sendCommand(queryCmd);
            if ~isempty(err)
                error('Could not read existing config for Channel %d. Error: %s', channelNum, err);
            end
            
            % 2. Parse the CSV response (e.g., "1,0.000,10.000,0,0,9.00")
            parts = split(strtrim(reply), ',');
            if length(parts) < 6
                error('Unexpected response format from bridge: %s', reply);
            end
            
            % 3. Overwrite only the parameters requested by the user
            if ~isnan(current_uA);  parts{2} = sprintf('%.3f', current_uA); end
            if ~isnan(power_uW);    parts{3} = sprintf('%.3f', power_uW); end
            if ~isnan(voltage_mV);  parts{6} = sprintf('%.2f', voltage_mV); end
            
            % 4. Reconstruct the string and send it back
            newCmd = sprintf('BRIDGE %s', strjoin(parts, ','));
            [~, setErr, ~] = obj.sendCommand(newCmd);
            
            if ~isempty(setErr)
                error('Failed to apply new config. Error: %s', setErr);
            else
                fprintf('Successfully updated Channel %d configuration.\n', channelNum);
            end
        end
    end
    end
end
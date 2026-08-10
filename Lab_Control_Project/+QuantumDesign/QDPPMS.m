classdef QDPPMS < handle
    % QDPPMS MATLAB Wrapper for Quantum Design PPMS using .NET Assembly
    
    properties (Access = private)
        NetObj              % Holds the active .NET instrument object
        IsSimulated = false % Flag for offline testing
        AssemblyObj         % Holds the NET.Assembly reference
        
        % Simulation fallback values
        SimTemp = 300
        SimField = 0
        SimAngle = 0
    end
    
    methods
        %% Constructor: Load DLL and Connect
        function obj = QDPPMS(dllPath)
            if strcmpi(dllPath, 'SIM')
                obj.IsSimulated = true;
                fprintf('Started QD PPMS in SIMULATION mode.\n');
                return;
            end
            
            try
                % Load the .NET assembly into memory AND save the reference!
                obj.AssemblyObj = NET.addAssembly(dllPath);
                
                % Foolproof reflection to grab the nested Enum (using the exact string you found)
                enumString = 'QuantumDesign.QDInstrument.QDInstrumentBase+QDInstrumentType';
                enumType = obj.AssemblyObj.AssemblyHandle.GetType(enumString);
                
                % Extract the 'PPMS' specific value from that Enum
                instType = System.Enum.Parse(enumType, 'PPMS');
                
                % Initialize local connection (false = not remote)
                obj.NetObj = QuantumDesign.QDInstrument.QDInstrumentFactory.GetQDInstrument(instType, false);
                
                fprintf('Successfully connected to PPMS via .NET Assembly!\n');
            catch ME
                error('Failed to load .NET assembly or connect to PPMS. Error: %s', ME.message);
            end
        end
        
        %% Destructor
        function delete(obj)
            if ~obj.IsSimulated && ~isempty(obj.NetObj)
                clear obj.NetObj;
                fprintf('PPMS .NET connection closed safely.\n');
            end
        end
        
        %% --- TEMPERATURE CONTROL ---
        function setTemperature(obj, targetTempK, rateKperMin, approachMode)
            if obj.IsSimulated
                obj.SimTemp = targetTempK;
                fprintf('[SIM] Temperature target set to %.2f K\n', targetTempK);
                return;
            end

            enumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureApproach');

            if strcmpi(approachMode, 'FastSettle')
                mode = System.Enum.Parse(enumType, 'FastSettle');
            else
                mode = System.Enum.Parse(enumType, 'NoOvershoot');
            end

            obj.NetObj.SetTemperature(targetTempK, rateKperMin, mode);
        end
        
        function [temp, statusStr] = getCurrentTemperature(obj)
            if obj.IsSimulated
                temp = obj.SimTemp + (randn() * 0.01);
                statusStr = 'Stable';
                return;
            end
            
            % Generate dummy inputs for .NET 'ref' parameters
            dummyTemp = double(0.0);
            statusEnumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureStatus');
            dummyStatus = System.Enum.ToObject(statusEnumType, 0);
            
            % MATLAB captures the return code, followed by the populated 'ref' variables
            [~, temp, rawStatus] = obj.NetObj.GetTemperature(dummyTemp, dummyStatus);
            statusStr = char(rawStatus.ToString());
        end
        
        %% --- MAGNETIC FIELD CONTROL ---
        function setMagneticField(obj, targetFieldOe, rateOePerSec, approachMode, magnetMode)
            if obj.IsSimulated
                obj.SimField = targetFieldOe;
                fprintf('[SIM] Magnetic Field target set to %.1f Oe\n', targetFieldOe);
                return;
            end

            % Parse Approach Mode
            appEnumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldApproach');
            if strcmpi(approachMode, 'Linear')
                appMode = System.Enum.Parse(appEnumType, 'Linear');
            elseif strcmpi(approachMode, 'Oscillate')
                appMode = System.Enum.Parse(appEnumType, 'Oscillate');
            else
                appMode = System.Enum.Parse(appEnumType, 'NoOvershoot');
            end

            % Parse Magnet Mode
            magEnumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldMode');
            if strcmpi(magnetMode, 'Persistent')
                magMode = System.Enum.Parse(magEnumType, 'Persistent');
            else
                magMode = System.Enum.Parse(magEnumType, 'Driven');
            end

            obj.NetObj.SetField(targetFieldOe, rateOePerSec, appMode, magMode);
        end
        
        function [field, statusStr] = getCurrentField(obj)
            if obj.IsSimulated
                field = obj.SimField;
                statusStr = 'Stable';
                return;
            end
            
            dummyField = double(0.0);
            statusEnumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldStatus');
            dummyStatus = System.Enum.ToObject(statusEnumType, 0);
            
            [~, field, rawStatus] = obj.NetObj.GetField(dummyField, dummyStatus);
            statusStr = char(rawStatus.ToString());
        end
        
        %% --- HELIUM LEVEL ---
        % Per the PPMS GPIB Commands Manual, helium level is read via the
        % legacy LEVEL?/LEVELON commands (NOT GetPPMSItem/GETDAT - helium
        % level isn't one of the bit-mapped GETDAT channels at all). The
        % level meter only updates hourly by default to conserve cryogen,
        % so LEVELON must be used to request continuous updates while
        % actively monitoring.
        function [level, statusStr] = getHeliumLevel(obj)
            if obj.IsSimulated
                level = 65 + (randn() * 0.5);
                statusStr = 'Stable';
                return;
            end

            try
                dummyReply = '';
                dummyError = '';
                [ret, reply, errOut] = obj.NetObj.SendPPMSCommand('LEVEL?', dummyReply, dummyError, 0, 2.0);
                if ret ~= 0
                    warning('PPMS LEVEL? command failed: %s', char(errOut));
                    level = NaN;
                    statusStr = 'Unknown';
                    return;
                end

                parts = strsplit(strtrim(char(reply)), ',');
                level = str2double(parts{1});
                if numel(parts) >= 2
                    updateCode = str2double(parts{2});
                else
                    updateCode = NaN;
                end

                switch updateCode
                    case 0
                        statusStr = 'Stale';   % reading is over an hour old
                    case 1
                        statusStr = 'Recent';  % reading is under an hour old
                    case 2
                        statusStr = 'Stable';  % meter is continuously on, this is a live reading
                    otherwise
                        statusStr = 'Unknown';
                end
            catch ME
                warning('Failed to read Helium Level: %s', ME.message);
                level = NaN;
                statusStr = 'Unknown';
            end
        end

        function setHeliumLevelMeter(obj, opCode)
            % opCode: 0 = single read then turn meter off (default),
            %         1 = continuous operation (must poll LEVEL? at least
            %             once every 60s or the meter auto-shuts-off),
            %         2 = enable hourly auto-update, 3 = disable hourly auto-update.
            if obj.IsSimulated
                fprintf('[SIM] Helium level meter opcode set to %d\n', opCode);
                return;
            end

            cmdStr = sprintf('LEVELON %d', opCode);
            dummyReply = '';
            dummyError = '';
            [ret, ~, errOut] = obj.NetObj.SendPPMSCommand(cmdStr, dummyReply, dummyError, 0, 2.0);
            if ret ~= 0
                warning('PPMS LEVELON command failed: %s', char(errOut));
            end
        end

        function shutdownTemperatureController(obj)
            % Per the GPIB Commands Manual: SHUTDOWN "places the
            % temperature controller code in standby mode; in which both
            % drivers used to control the system temperature are turned
            % off and the helium flow is set to a minimum value." This is
            % a dedicated no-parameter command - NOT the same as calling
            % setTemperature with an approach mode (TemperatureApproach
            % only has FastSettle/NoOvershoot; there is no "Standby").
            if obj.IsSimulated
                fprintf('[SIM] Temperature controller placed in standby.\n');
                return;
            end

            dummyReply = '';
            dummyError = '';
            [ret, ~, errOut] = obj.NetObj.SendPPMSCommand('SHUTDOWN', dummyReply, dummyError, 0, 2.0);
            if ret ~= 0
                warning('PPMS SHUTDOWN command failed: %s', char(errOut));
            end
        end

        %% --- STABILITY CHECK ---
        function reached = waitConditionReached(obj, waitTemp, waitField, waitPosition, waitChamber)
            % Non-blocking check of whether the requested subsystems are
            % currently at their target/stable. Confirmed to exist on
            % QDInstrumentBase via .NET reflection (signature matches);
            % NOT yet verified against real hardware - test before fully
            % trusting this over the status-string checks it replaces.
            if obj.IsSimulated
                reached = true;
                return;
            end

            try
                reached = logical(obj.NetObj.WaitConditionReached(waitTemp, waitField, waitPosition, waitChamber));
            catch ME
                warning('WaitConditionReached call failed: %s', ME.message);
                reached = false;
            end
        end

        %% --- HORIZONTAL ROTATOR CONTROL ---
        function [position, status, slowDownCode] = getMovePosition(obj)
            % Sends the legacy MOVE? query, which per the GPIB Commands
            % Manual returns "Position, Status, and SlowDownCode that
            % indicate the present position of the sample and the Status
            % ... used to reach that position." Table A-2 documents the
            % Sample Position status states (Unknown / Stopped at target
            % / Moving toward set point / Hit limit switch / Hit index
            % switch / General failure), but the exact numeric value for
            % each state was not cleanly extractable from the OCR'd
            % manual. status==1 is assumed to mean "stopped at target"
            % pending confirmation against real hardware - the caller
            % logs the raw value the first time it's read so this can be
            % verified.
            if obj.IsSimulated
                position = obj.SimAngle;
                status = 1;
                slowDownCode = 0;
                return;
            end

            try
                dummyReply = '';
                dummyError = '';
                [ret, reply, errOut] = obj.NetObj.SendPPMSCommand('MOVE?', dummyReply, dummyError, 0, 2.0);
                if ret ~= 0
                    warning('PPMS MOVE? command failed: %s', char(errOut));
                    position = NaN;
                    status = NaN;
                    slowDownCode = NaN;
                    return;
                end

                parts = strsplit(strtrim(char(reply)), ',');
                position = str2double(parts{1});
                if numel(parts) >= 2; status = str2double(parts{2}); else; status = NaN; end
                if numel(parts) >= 3; slowDownCode = str2double(parts{3}); else; slowDownCode = NaN; end
            catch ME
                warning('Failed to read MOVE? status: %s', ME.message);
                position = NaN;
                status = NaN;
                slowDownCode = NaN;
            end
        end

        function setRotatorAngle(obj, targetAngleDeg, speedDegPerSec)
            if obj.IsSimulated
                obj.SimAngle = targetAngleDeg;
                fprintf('[SIM] Rotator moving to %.2f deg\n', targetAngleDeg);
                return;
            end
            
            % Enforce safety limits found in the Python wrapper
            if speedDegPerSec > 14
                speedDegPerSec = 14;
            elseif speedDegPerSec < 0.1
                speedDegPerSec = 0.1;
            end
            
            % Construct the legacy macro command: MOVE <Angle> 0 <Speed>
            cmdStr = sprintf('MOVE %.3f 0 %.3f', targetAngleDeg, speedDegPerSec);
            dummyReply = '';
            dummyError = '';
            
            % Send via the backdoor command
            [ret, ~, errOut] = obj.NetObj.SendPPMSCommand(cmdStr, dummyReply, dummyError, 0, 2.0);
            
            if ret ~= 0
                warning('PPMS Rotator Error: %s', char(errOut));
            end
        end
        
        function [angle, status] = getRotatorAngle(obj)
            if obj.IsSimulated
                angle = obj.SimAngle; status = 'Stable'; return;
            end
            
            try
                % Using the Python wrapper's trick: Rotator Angle is PPMS Map Item #3
                % Signature: GetPPMSItem(Channel, DummyValue, FastUpdate)
                [ret, currentAngle] = obj.NetObj.GetPPMSItem(3, 0.0, true);
                
                if ret == 0
                    angle = currentAngle;
                    status = 'Stable';
                    return;
                end
            catch
            end
            
            % Fallback if it fails to read
            angle = NaN; 
            status = 'Unknown';
        end
        
        %% --- BRIDGE PASSTHROUGH GETTER ---
        function netHandle = getNetObject(obj)
            netHandle = obj.NetObj;
        end
    end
end
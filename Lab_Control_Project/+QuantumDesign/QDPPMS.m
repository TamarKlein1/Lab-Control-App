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
            enumType = obj.AssemblyObj.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureApproach');
            
            if strcmpi(approachMode, 'FastSettle')
                mode = System.Enum.Parse(enumType, 'FastSettle');
            else
                mode = System.Enum.Parse(enumType, 'NoOvershoot');
            end
            
            if obj.IsSimulated
                obj.SimTemp = targetTempK;
                fprintf('[SIM] Temperature target set to %.2f K\n', targetTempK);
                return;
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
            
            if obj.IsSimulated
                obj.SimField = targetFieldOe;
                fprintf('[SIM] Magnetic Field target set to %.1f Oe\n', targetFieldOe);
                return;
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
        
        %% --- HORIZONTAL ROTATOR CONTROL ---
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
classdef USB6002 < handle
    % USB6002 MATLAB Wrapper for NI USB-6002 Analog Output
    % Maps a +/- 10V output to a bipolar magnetic field (in Oersted).
    % Includes smooth ramping to protect inductive loads.
    
    properties (Access = private)
        DaqObj              % Holds the MATLAB daq object
        IsSimulated = false % Flag for offline testing
        CurrentField = 0    % Software tracker for the current field
    end
    
    properties (SetAccess = private)
        MaxField = 4500     % Calibration: The field (Oe) at exactly 10 Volts
        SweepSpeed = 500    % Rate of field change in Oe/sec
        DeviceID = 'Dev1'   % Default NI Device ID
        Channel = 'ao0'     % Default Analog Output channel
    end
    
    methods
        %% Constructor: Connect and Initialize
        function obj = USB6002(deviceID, channel)
            if nargin > 0 && strcmpi(deviceID, 'SIM')
                obj.IsSimulated = true;
                fprintf('Started NI USB-6002 Magnet in SIMULATION mode.\n');
                return;
            end
            
            if nargin > 0
                obj.DeviceID = deviceID;
            end
            if nargin > 1
                obj.Channel = channel;
            end
            
            try
                obj.DaqObj = daq('ni');
                addoutput(obj.DaqObj, obj.DeviceID, obj.Channel, 'Voltage');
                
                % Ensure the magnet starts at 0 Volts (0 Oe)
                write(obj.DaqObj, 0);
                
                fprintf('Successfully connected to NI USB-6002 (%s, %s)\n', obj.DeviceID, obj.Channel);
            catch ME
                error('Failed to connect to NI DAQ. Error: %s', ME.message);
            end
        end
        
        %% Destructor: Clean Disconnect
        function delete(obj)
            if obj.IsSimulated
                fprintf('Closed simulated NI USB-6002.\n');
                return;
            end
            
            if ~isempty(obj.DaqObj) && isvalid(obj.DaqObj)
                % SAFETY: Smoothly zero the field before dropping the connection
                fprintf('Safety: Ramping magnetic field to 0 Oe before disconnecting...\n');
                try
                    obj.setField(0); 
                catch
                    % Fallback just in case setField fails
                    write(obj.DaqObj, 0);
                end
                clear obj.DaqObj;
                fprintf('NI DAQ connection closed safely.\n');
            end
        end
        
        %% Setup: Change Calibration
        function setCalibration(obj, newMaxFieldOe)
            if newMaxFieldOe <= 0
                error('Max field must be a positive number.');
            end
            obj.MaxField = newMaxFieldOe;
            fprintf('Calibration updated: 10 Volts = %f Oe.\n', obj.MaxField);
        end
        
        %% Setup: Change Sweep Speed
        function setSweepSpeed(obj, speedOePerSec)
            if speedOePerSec <= 0
                error('Sweep speed must be a positive number greater than 0.');
            end
            obj.SweepSpeed = speedOePerSec;
            fprintf('Magnet sweep speed updated to %f Oe/s.\n', obj.SweepSpeed);
        end
        
        %% Action: Set Magnetic Field (Smooth Ramp)
        function setField(obj, targetFieldOe)
            % 1. Check if requested field exceeds calibration limits
            if abs(targetFieldOe) > obj.MaxField
                error('Requested field (%f Oe) exceeds current calibration max (%f Oe).', targetFieldOe, obj.MaxField);
            end
            
            startField = obj.CurrentField;
            
            % If we are already there, do nothing
            if startField == targetFieldOe
                return; 
            end
            
            % 2. Calculate the sweep parameters
            updateRateHz = 20; % 20 updates per second for a smooth voltage ramp
            dt = 1 / updateRateHz; 
            stepOe = obj.SweepSpeed * dt;
            
            % Generate the array of field points to step through
            if targetFieldOe > startField
                sweepPath = startField : stepOe : targetFieldOe;
            else
                sweepPath = startField : -stepOe : targetFieldOe;
            end
            
            % Ensure the final point hits the exact target field
            if isempty(sweepPath) || sweepPath(end) ~= targetFieldOe
                sweepPath(end+1) = targetFieldOe; 
            end
            
            if obj.IsSimulated
                fprintf('[SIM MAGNET] Ramping field from %.1f Oe to %.1f Oe at %.1f Oe/s...\n', startField, targetFieldOe, obj.SweepSpeed);
            end
            
            % 3. Execute the ramp
            for i = 1:length(sweepPath)
                currentPoint = sweepPath(i);
                targetVolts = 10.0 * (currentPoint / obj.MaxField);
                
                if ~obj.IsSimulated
                    write(obj.DaqObj, targetVolts);
                end
                
                % Update software tracker incrementally
                obj.CurrentField = currentPoint; 
                
                % Pause allows hardware to update and settle
                pause(dt); 
            end
            
            if obj.IsSimulated
                fprintf('[SIM MAGNET] Reached target field: %.1f Oe.\n', targetFieldOe);
            end
        end
        
        %% Query: Get Current Field
        function field = queryField(obj)
            field = obj.CurrentField;
        end
    end
end
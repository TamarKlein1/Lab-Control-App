classdef Keithley3706 < handle
    % KEITHLEY3706 MATLAB Wrapper for the Keithley 3706 System Switch
    % Uses Keithley's native TSP (Lua) command set instead of SCPI.
    % Assumes a 6x16 Matrix Card installed in Slot 1.
    
    properties (Access = private)
        VisaObj             % Holds the visadev connection object
        IsSimulated = false % Flag to check if we are in test mode
        SimClosedChannels = '' % Stores closed channels for mock querying
    end
    
    methods
        %% Constructor: Connect and Initialize
        function obj = Keithley3706(visaAddress)
            if strcmpi(visaAddress, 'SIM')
                obj.IsSimulated = true;
                fprintf('Started Keithley 3706 in SIMULATION mode.\n');
                return;
            end
            
            try
                obj.VisaObj = visadev(visaAddress);
                
                % TSP Command: Reset the instrument to default
                writeline(obj.VisaObj, 'reset()'); 
                
                % TSP Command: Open all channels across all slots
                writeline(obj.VisaObj, 'channel.open("allslots")');
                
                fprintf('Successfully connected to Keithley 3706 at %s (TSP Mode)\n', visaAddress);
            catch ME
                error('Failed to connect to %s. Error: %s', visaAddress, ME.message);
            end
        end
        
        %% Destructor: Clean Disconnect
        function delete(obj)
            if obj.IsSimulated
                fprintf('Closed simulated Keithley 3706.\n');
                return;
            end
            
            if ~isempty(obj.VisaObj) && isvalid(obj.VisaObj)
                % TSP Command: Open all relays before disconnecting
                writeline(obj.VisaObj, 'channel.open("allslots")');
                clear obj.VisaObj;
                fprintf('Keithley 3706 connection closed safely.\n');
            end
        end
        
        %% Action: Open All Channels
        function openAllChannels(obj)
            if obj.IsSimulated
                obj.SimClosedChannels = 'NONE';
                fprintf('[SIM] All channels OPENED.\n');
                return;
            end
            
            % TSP Command to open everything
            writeline(obj.VisaObj, 'channel.open("allslots")');
        end
        
        %% Action: Close Specific Channels from Vector
        function closeChannels(obj, channelVector)
            % Expects a 1x6 vector mapping Rows 1-6 to Columns 1-16.
            if length(channelVector) ~= 6
                error('Input vector must have exactly 6 elements representing Rows 1 through 6.');
            end
            
            % First, open all channels to prevent shorts
            obj.openAllChannels();
            
            % Build the channel list string
            channelList = {};
            for row = 1:6
                col = channelVector(row);
                if col > 0 && col <= 16
                    % Format: Slot (1) + Row (1-6) + Col (01-16)
                    chStr = sprintf('1%d%02d', row, col);
                    channelList{end+1} = chStr; %#ok<AGROW>
                elseif col > 16 || col < 0
                    error('Column value %d at row %d is invalid. Must be 0 to 16.', col, row);
                end
            end
            
            if isempty(channelList)
                fprintf('Vector contained all zeros. All channels remain open.\n');
                return;
            end
            
            % TSP expects a comma-separated string of channels like: "1101, 1204, 1415"
            tspChannelString = strjoin(channelList, ',');
            
            if obj.IsSimulated
                obj.SimClosedChannels = tspChannelString;
                fprintf('[SIM] Closed channels: %s\n', tspChannelString);
                return;
            end
            
            % TSP Command: Close the specific list of channels
            writeline(obj.VisaObj, sprintf('channel.close("%s")', tspChannelString));
        end
        
        %% Action: Append Channels (Close without opening existing)
        function appendChannels(obj, channelVector)
            % Expects a 1x6 vector mapping Rows 1-6 to Columns 1-16.
            if length(channelVector) ~= 6
                error('Input vector must have exactly 6 elements representing Rows 1 through 6.');
            end

            % Build the channel list string
            channelList = {};
            for row = 1:6
                col = channelVector(row);
                if col > 0 && col <= 16
                    % Format: Slot (1) + Row (1-6) + Col (01-16)
                    chStr = sprintf('1%d%02d', row, col);
                    channelList{end+1} = chStr; %#ok<AGROW>
                elseif col > 16 || col < 0
                    error('Column value %d at row %d is invalid. Must be 0 to 16.', col, row);
                end
            end

            if isempty(channelList)
                fprintf('Vector contained all zeros. No new channels to close.\n');
                return;
            end

            tspChannelString = strjoin(channelList, ', ');

            if obj.IsSimulated
                if strcmp(obj.SimClosedChannels, 'NONE') || isempty(obj.SimClosedChannels)
                    obj.SimClosedChannels = tspChannelString;
                else
                    obj.SimClosedChannels = [obj.SimClosedChannels, ', ', tspChannelString];
                end
                fprintf('[SIM] Appended channels: %s\n', tspChannelString);
                return;
            end

            % TSP Command: Close the specific list WITHOUT opening existing channels
            writeline(obj.VisaObj, sprintf('channel.close("%s")', tspChannelString));
        end
        
        %% Query: Get Closed Channels
        function closedList = queryClosedChannels(obj)
            if obj.IsSimulated
                closedList = obj.SimClosedChannels;
                if isempty(closedList)
                    closedList = 'NONE';
                end
                return;
            end
            
            % TSP Command: Query closed channels and print the result back to the bus
            writeline(obj.VisaObj, 'print(channel.getclose("allslots"))');
            rawList = char(readline(obj.VisaObj));
            
            % TSP returns "nil" (or empty) if no channels are closed
            if isempty(rawList) || contains(rawList, 'nil')
                closedList = 'NONE';
            else
                % Firmware versions differ; some return semicolons, others commas.
                % Normalize it to commas so our GUI parser handles it easily.
                closedList = strrep(rawList, ';', ',');
                
                % Strip out any stray quotes that TSP might append
                closedList = strrep(closedList, '"', '');
                closedList = strrep(closedList, '''', '');
            end
        end
    end
end
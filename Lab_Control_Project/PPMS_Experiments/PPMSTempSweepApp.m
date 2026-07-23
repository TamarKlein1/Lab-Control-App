classdef PPMSTempSweepApp < handle
    % PPMSTempSweepApp - Multiplexed R vs. T Sweep using PPMS, M81, and 3706
    % Includes Smart 2-Wire/4-Wire detection, Selectable Voltage Range, and Global Autoscaling.
    
    properties
        UIFigure
        GridLayout
        
        % Data & State
        ChannelSets = {}
        IsRunning = false
        DataLines = {}
        CurrentFile = ''
        
        % Hardware Objects
        PPMS
        M81
        Switcher
    end
    
    properties (Access = private)
        % UI Handles
        AddrPPMS, AddrM81, AddrSwitch
        ConnectBtn, DisconnectBtn
        
        StartTempEdit, EndTempEdit, RateEdit, IntervalEdit
        CurrentEdit, FreqEdit, TCEdit, HotSwapCheckBox
        MeasureRangeDrop % NEW: Voltage Range Dropdown
        CustomVRangeEdit % NEW: Custom Voltage Edit Field
        
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = PPMSTempSweepApp()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'PPMS Multiplexed Temperature Sweep', 'Position', [100, 100, 1150, 850]);
            
            % WIDENED LEFT COLUMN to 400 to make room for the new scrollbar
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {400, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            
            % FIXED: Added 'Scrollable', 'on' directly to the grid layout!
            controlLayout = uigridlayout(controlPanel, [7, 1], ...
                'RowHeight', {'fit', 'fit', 'fit', 250, 'fit', 'fit', 50}, ...
                'Scrollable', 'on');
            
            app.createConnectionPanel(controlLayout);
            app.createSweepPanel(controlLayout);
            app.createM81Panel(controlLayout);
            app.createChannelPanel(controlLayout);
            app.createFilePanel(controlLayout);
            app.createConfigPanel(controlLayout);
            app.createControlButtons(controlLayout);
            
            % Right Panel: Live Plot
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Data');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {30, '1x'});
            
            app.AutoscaleBtn = uibutton(plotLayout, 'state', 'Text', 'Autoscale ON', ...
                'Value', true, 'ValueChangedFcn', @(src,event) app.toggleAutoscale());
            
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Resistance vs. Temperature');
            xlabel(app.PlotAxes, 'Temperature (K)');
            ylabel(app.PlotAxes, 'Resistance (\Omega)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'PPMS DLL Path:'); app.AddrPPMS = uieditfield(g, 'text', 'Value', 'C:\MATLAB\Lab_Control_Project\Drivers\QDInstrument.dll');
            uilabel(g, 'Text', 'M81 USB/GPIB:');  app.AddrM81 = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createSweepPanel(app, parent)
            p = uipanel(parent, 'Title', 'PPMS Temperature Sweep');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', 100});
            
            uilabel(g, 'Text', 'Start Temp (K):'); app.StartTempEdit = uieditfield(g, 'numeric', 'Value', 300.0);
            uilabel(g, 'Text', 'End Temp (K):');   app.EndTempEdit = uieditfield(g, 'numeric', 'Value', 10.0);
            uilabel(g, 'Text', 'Rate (K/min):');   app.RateEdit = uieditfield(g, 'numeric', 'Value', 2.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.IntervalEdit = uieditfield(g, 'numeric', 'Value', 1.0);
        end
        
        function createM81Panel(app, parent)
            p = uipanel(parent, 'Title', 'M81 Lock-In Settings');
            g = uigridlayout(p, [6, 2], 'ColumnWidth', {'1x', 100}); % Increased rows for V.Range
            
            uilabel(g, 'Text', 'AC Current (A):');    app.CurrentEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Frequency (Hz):');    app.FreqEdit = uieditfield(g, 'numeric', 'Value', 13.0);
            uilabel(g, 'Text', 'Time Constant (s):'); app.TCEdit = uieditfield(g, 'numeric', 'Value', 0.3);
            
            % NEW: Voltage Range Dropdown & Custom Edit Field
            uilabel(g, 'Text', 'V. Range:');
            app.MeasureRangeDrop = uidropdown(g, ...
                'Items', {'AUTO', '10 mV', '30 mV', '100 mV', '300 mV', '1 V', '3 V', '10 V', 'CUSTOM...'}, ...
                'ItemsData', {'AUTO', 10e-3, 30e-3, 100e-3, 300e-3, 1.0, 3.0, 10.0, 'CUSTOM'}, ...
                'Value', 'AUTO', 'ValueChangedFcn', @(s,e) app.onRangeChange());
                
            uilabel(g, 'Text', 'Custom (V):');
            app.CustomVRangeEdit = uieditfield(g, 'numeric', 'Value', 0.05, 'Enable', 'off');
            
            app.HotSwapCheckBox = uicheckbox(g, 'Text', 'Enable Hot Swap (Low Current)', 'Value', true);
            app.HotSwapCheckBox.Layout.Row = 6; app.HotSwapCheckBox.Layout.Column = [1 2];
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher (Column Indices 1-16)');
            
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', '1x'}); 
            
            lbl1 = uilabel(g, 'Text', '+I (Row 1):'); 
            lbl1.Layout.Row = 1; lbl1.Layout.Column = 1;
            app.ChanPosI = uieditfield(g, 'numeric', 'Value', 11); 
            app.ChanPosI.Layout.Row = 1; app.ChanPosI.Layout.Column = 2;
            
            lbl2 = uilabel(g, 'Text', '-I (Row 2):'); 
            lbl2.Layout.Row = 1; lbl2.Layout.Column = 3;
            app.ChanNegI = uieditfield(g, 'numeric', 'Value', 12); 
            app.ChanNegI.Layout.Row = 1; app.ChanNegI.Layout.Column = 4;
            
            lbl3 = uilabel(g, 'Text', '+V (Row 3):'); 
            lbl3.Layout.Row = 2; lbl3.Layout.Column = 1;
            app.ChanPosV = uieditfield(g, 'numeric', 'Value', 13); 
            app.ChanPosV.Layout.Row = 2; app.ChanPosV.Layout.Column = 2;
            
            lbl4 = uilabel(g, 'Text', '-V (Row 4):'); 
            lbl4.Layout.Row = 2; lbl4.Layout.Column = 3;
            app.ChanNegV = uieditfield(g, 'numeric', 'Value', 14); 
            app.ChanNegV.Layout.Row = 2; app.ChanNegV.Layout.Column = 4;
            
            addBtn = uibutton(g, 'Text', 'Add Set', 'ButtonPushedFcn', @(src,event) app.addChannelSet());
            addBtn.Layout.Row = 3; addBtn.Layout.Column = [1 2];
            
            remBtn = uibutton(g, 'Text', 'Remove Selected', 'ButtonPushedFcn', @(src,event) app.removeChannelSet());
            remBtn.Layout.Row = 3; remBtn.Layout.Column = [3 4];
            
            app.ChannelListBox = uilistbox(g, 'Items', {}); 
            app.ChannelListBox.Layout.Row = 4; app.ChannelListBox.Layout.Column = [1 4];
        end
        
        function createFilePanel(app, parent)
            p = uipanel(parent, 'Title', 'Save Data File Location');
            g = uigridlayout(p, [1, 2], 'ColumnWidth', {'1x', 70});
            
            app.FilePathEdit = uieditfield(g, 'text', 'Placeholder', 'Leave empty to prompt on run...');
            uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(src,event) app.browseFile());
        end
        
        function createConfigPanel(app, parent)
            p = uipanel(parent, 'Title', 'Experiment Config');
            g = uigridlayout(p, [1, 2]);
            uibutton(g, 'Text', 'Load Setup', 'ButtonPushedFcn', @(src,event) app.loadConfig());
            uibutton(g, 'Text', 'Save Setup', 'ButtonPushedFcn', @(src,event) app.saveConfig());
        end
        
        function createControlButtons(app, parent)
            g = uigridlayout(parent, [1, 2]);
            g.Layout.Row = 7;
            
            app.RunBtn = uibutton(g, 'Text', 'START', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runExperiment());
            app.StopBtn = uibutton(g, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopExperiment());
        end
        
        %% --- UI Callbacks ---
        function onRangeChange(app)
            % Wake up the Custom Voltage box if CUSTOM is selected
            if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                app.CustomVRangeEdit.Enable = 'on';
            else
                app.CustomVRangeEdit.Enable = 'off';
            end
        end
        
        %% --- Configuration & Hardware ---
        function saveConfig(app)
            [file, path] = uiputfile('*.mat', 'Save Configuration');
            if file == 0; return; end
            
            config = struct();
            config.AddrPPMS     = app.AddrPPMS.Value;
            config.AddrM81      = app.AddrM81.Value;
            config.AddrSwitch   = app.AddrSwitch.Value;
            config.StartTemp    = app.StartTempEdit.Value;
            config.EndTemp      = app.EndTempEdit.Value;
            config.Rate         = app.RateEdit.Value;
            config.Interval     = app.IntervalEdit.Value;
            config.Current      = app.CurrentEdit.Value;
            config.Freq         = app.FreqEdit.Value;
            config.TC           = app.TCEdit.Value;
            config.VRange       = app.MeasureRangeDrop.Value; 
            config.CustomVRange = app.CustomVRangeEdit.Value;
            config.HotSwap      = app.HotSwapCheckBox.Value; 
            config.ChannelSets  = app.ChannelSets;
            config.ChannelItems = app.ChannelListBox.Items;
            
            save(fullfile(path, file), 'config');
            uialert(app.UIFigure, 'Configuration saved.', 'Success');
        end
        
        function loadConfig(app)
            [file, path] = uigetfile('*.mat', 'Load Configuration');
            if file == 0; return; end
            
            try
                data = load(fullfile(path, file), 'config');
                c = data.config;
                
                app.AddrPPMS.Value      = c.AddrPPMS;
                app.AddrM81.Value       = c.AddrM81;
                app.AddrSwitch.Value    = c.AddrSwitch;
                app.StartTempEdit.Value = c.StartTemp;
                app.EndTempEdit.Value   = c.EndTemp;
                app.RateEdit.Value      = c.Rate;
                app.IntervalEdit.Value  = c.Interval;
                app.CurrentEdit.Value   = c.Current;
                app.FreqEdit.Value      = c.Freq;
                app.TCEdit.Value        = c.TC;
                
                try app.MeasureRangeDrop.Value = c.VRange; catch; end 
                try app.CustomVRangeEdit.Value = c.CustomVRange; catch; end 
                if isfield(c, 'HotSwap'); app.HotSwapCheckBox.Value = c.HotSwap; end
                
                app.ChannelSets         = c.ChannelSets;
                app.ChannelListBox.Items = c.ChannelItems;
                if ~isempty(app.ChannelListBox.Items); app.ChannelListBox.Value = app.ChannelListBox.Items{1}; end
                
                app.onRangeChange(); % Refresh Custom UI Box
            catch
                uialert(app.UIFigure, 'Failed to load configuration.', 'Error');
            end
        end
        
        function disconnectHardware(app)
            try delete(app.PPMS); app.PPMS = []; catch; end
            try delete(app.M81); app.M81 = []; catch; end
            try delete(app.Switcher); app.Switcher = []; catch; end
            
            app.ConnectBtn.Text = 'Connect';
            app.ConnectBtn.BackgroundColor = [0.96 0.96 0.96];
            app.ConnectBtn.Enable = 'on';
            app.DisconnectBtn.Enable = 'off';
            app.RunBtn.Enable = 'off';
        end
        
        function connectHardware(app)
            app.disconnectHardware();
            try
                app.ConnectBtn.Text = 'Connecting...'; 
                app.ConnectBtn.Enable = 'off'; drawnow;
                
                app.PPMS     = QuantumDesign.QDPPMS(app.AddrPPMS.Value); 
                app.M81      = Lakeshore.LakeshoreM81(app.AddrM81.Value);
                app.Switcher = Keithley.Keithley3706(app.AddrSwitch.Value);
                
                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ConnectBtn.Enable = 'off'; 
                app.DisconnectBtn.Enable = 'on';
                app.RunBtn.Enable = 'on';
            catch ME
                app.disconnectHardware();
                app.ConnectBtn.Text = 'Retry Connection';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end
        
        %% --- List & File Logic ---
        function addChannelSet(app)
            vector = [app.ChanPosI.Value, app.ChanNegI.Value, app.ChanPosV.Value, app.ChanNegV.Value, 0, 0];
            chanStr = sprintf('Set %d: +I(c%d), -I(c%d), +V(c%d), -V(c%d)', ...
                length(app.ChannelSets)+1, vector(1), vector(2), vector(3), vector(4));
            app.ChannelSets{end+1} = vector;
            app.ChannelListBox.Items{end+1} = chanStr;
            app.ChannelListBox.Value = chanStr;
        end
        
        function removeChannelSet(app)
            if isempty(app.ChannelListBox.Items); return; end
            idx = find(strcmp(app.ChannelListBox.Items, app.ChannelListBox.Value));
            if ~isempty(idx)
                app.ChannelListBox.Items(idx) = [];
                app.ChannelSets(idx) = [];
                if ~isempty(app.ChannelListBox.Items); app.ChannelListBox.Value = app.ChannelListBox.Items{end}; end
            end
        end
        
        function browseFile(app)
            [file, path] = uiputfile('*.csv', 'Select Save Location');
            if file ~= 0; app.FilePathEdit.Value = fullfile(path, file); end
        end
        
        function safeFile = resolveFilename(app, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            safeFile = baseFile;
            counter = 1;
            while isfile(safeFile)
                safeFile = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
                counter = counter + 1;
            end
        end
        
        %% --- Plot & Execution Logic ---
        function toggleAutoscale(app)
            if app.AutoscaleBtn.Value
                app.AutoscaleBtn.Text = 'Autoscale ON';
                app.PlotAxes.XLimMode = 'auto';
                app.PlotAxes.YLimMode = 'auto';
            else
                app.AutoscaleBtn.Text = 'Autoscale OFF (Manual)';
                app.PlotAxes.XLimMode = 'manual';
                app.PlotAxes.YLimMode = 'manual';
            end
        end
        
        function stopExperiment(app)
            app.IsRunning = false;
        end
        
        function runExperiment(app)
            numChannels = length(app.ChannelSets);
            if numChannels == 0
                uialert(app.UIFigure, 'Please add at least one channel set.', 'Configuration Error');
                return;
            end
            
            targetFile = app.FilePathEdit.Value;
            if isempty(targetFile)
                [file, path] = uiputfile('*.csv', 'Select File to Save Data');
                if file == 0; return; end 
                targetFile = fullfile(path, file);
                app.FilePathEdit.Value = targetFile;
            end
            
            app.CurrentFile = app.resolveFilename(targetFile);
            
            % Open File and Write Headers
            fileID = fopen(app.CurrentFile, 'w');
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Lock-In Current: %e A | Freq: %f Hz | TC: %f s\n', app.CurrentEdit.Value, app.FreqEdit.Value, app.TCEdit.Value);
            fprintf(fileID, '%% PPMS Sweep: %f K to %f K at %f K/min\n', app.StartTempEdit.Value, app.EndTempEdit.Value, app.RateEdit.Value);
            
            headerStr = 'Temperature_K';
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                headerStr = sprintf('%s,%d_%d_%d_%d', headerStr, vec(1), vec(2), vec(3), vec(4));
            end
            fprintf(fileID, '%s\n', headerStr);
            
            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            
            cla(app.PlotAxes);
            app.DataLines = {};
            colors = lines(numChannels);
            for c = 1:numChannels
                app.DataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, app.ChannelListBox.Items, 'Location', 'best');
            
            try
                % Resolve User Selected Voltage Range
                if ischar(app.MeasureRangeDrop.Value) && strcmp(app.MeasureRangeDrop.Value, 'CUSTOM')
                    vRange = app.CustomVRangeEdit.Value;
                else
                    vRange = app.MeasureRangeDrop.Value;
                end
                
                % Hardware Prep (Start Output OFF)
                app.M81.setOutputState(false); 
                app.M81.setSourceMode('AC', app.CurrentEdit.Value, 0.0, app.FreqEdit.Value);
                app.M81.setSourceRange(app.CurrentEdit.Value);    
                app.M81.setMeasureMode('LIA');
                app.M81.setMeasureRange(vRange); 
                app.M81.setTimeConstant(app.TCEdit.Value);
                
                % 1. PPMS: Go to Start Temperature and Wait
                app.PlotAxes.Title.String = sprintf('Ramping to Start Temperature (%.1f K)...', app.StartTempEdit.Value);
                app.PPMS.setTemperature(app.StartTempEdit.Value, 10.0, 'FastSettle');
                
                while app.IsRunning
                    [currentTemp, status] = app.PPMS.getCurrentTemperature();
                    if strcmpi(status, 'Stable') && abs(currentTemp - app.StartTempEdit.Value) < 0.2
                        break;
                    end
                    pause(1);
                end
                
                if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end
                
                % 2. PPMS: Begin the Measurement Sweep
                app.PlotAxes.Title.String = 'Resistance vs. Temperature Sweep';
                app.PPMS.setTemperature(app.EndTempEdit.Value, app.RateEdit.Value, 'NoOvershoot');
                pause(2); 
                
                % If single channel or HotSwap, setup the first channel and turn ON
                if numChannels == 1 || app.HotSwapCheckBox.Value == true
                    app.Switcher.closeChannels(app.ChannelSets{1});
                    
                    % Smart Mode Detection for the first channel
                    vec = app.ChannelSets{1};
                    if (vec(1) == vec(3)) && (vec(2) == vec(4))
                        app.M81.configureResistanceMode('TWOWire', 'AC');
                    else
                        app.M81.configureResistanceMode('4WIRE', 'AC');
                    end
                    
                    app.M81.setOutputState(true);
                    
                    if isnumeric(vRange)
                        pause(max(app.TCEdit.Value * 6, 2.0)); 
                    else
                        pause(max(app.TCEdit.Value * 10, 4.0));
                    end
                end
                
                % Initialize tracker before the loop starts
                activeChannel = 1; 
                
                % 3. Main R vs T Multiplexed Measurement Loop
                while app.IsRunning
                    loopTimer = tic;
                    
                    % Grab Live Temp once per cycle
                    [currentTemp, ~] = app.PPMS.getCurrentTemperature();
                    stepVoltages = zeros(1, numChannels);
                    
                    for c = 1:numChannels
                        if ~app.IsRunning; break; end
                        
                        % ==========================================
                        % SMART SWAP SEQUENCE LOGIC
                        % ==========================================
                        % Only trigger the relays if we are changing to a NEW channel
                        if activeChannel ~= c || numChannels > 1
                            
                            % Re-apply Smart Mode Detection for the incoming channel
                            vec = app.ChannelSets{c};
                            if (vec(1) == vec(3)) && (vec(2) == vec(4))
                                targetMode = 'TWOWire';
                            else
                                targetMode = '4WIRE';
                            end
                            
                            if app.HotSwapCheckBox.Value == true
                                % --- HOT SWAP ---
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                app.M81.configureResistanceMode(targetMode, 'AC');
                                
                                % Smart Settling Delay
                                if isnumeric(vRange)
                                    pause(max(app.TCEdit.Value * 6, 1.0)); 
                                else
                                    pause(max(app.TCEdit.Value * 10, 3.0));
                                end
                            else
                                % --- COLD SWAP ---
                                app.M81.setOutputState(false);                  
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                pause(0.2);                                     
                                
                                app.M81.configureResistanceMode(targetMode, 'AC');
                                app.M81.setOutputState(true);                   
                                
                                % Smart Settling Delay
                                if isnumeric(vRange)
                                    pause(max(app.TCEdit.Value * 6, 2.0)); 
                                else
                                    pause(max(app.TCEdit.Value * 10, 4.0));
                                end
                            end
                            
                            activeChannel = c;
                            
                        else
                            % Already on the right channel, just let temp update
                            pause(0.1);
                        end
                        % ==========================================
                        
                        % Read and Parse with a SMART RETRY LOOP
                        rVal = NaN;
                        for attempt = 1:4
                            try
                                rVal = app.M81.readResistance();
                                
                                % Fallback if instrument returns NaN instead of Resistance
                                if isnan(rVal)
                                    [~, ~, R_mag, ~] = app.M81.readLockIn();
                                    rVal = R_mag / app.CurrentEdit.Value;
                                end
                                
                                % Sanity Check: NbN should never be > 1M ohms
                                if ~isnan(rVal) && abs(rVal) < 1e6
                                    break; 
                                end
                            catch ME_Read
                                if attempt == 4; rethrow(ME_Read); end
                                pause(0.2); 
                            end
                        end
                        
                        % Record valid data
                        stepVoltages(c) = rVal;
                        if abs(rVal) < 1e6 
                            addpoints(app.DataLines{c}, currentTemp, rVal);
                        end
                    end % End of Channel Loop
                    
                    % --- GLOBAL DYNAMIC AUTOSCALING (ALL CHANNELS) ---
                    if app.AutoscaleBtn.Value
                        globalYMin = inf;
                        globalYMax = -inf;
                        validDataFound = false;
                        
                        for idx = 1:numChannels
                            [~, yData] = getpoints(app.DataLines{idx});
                            if length(yData) > 2
                                globalYMin = min(globalYMin, min(yData));
                                globalYMax = max(globalYMax, max(yData));
                                validDataFound = true;
                            end
                        end
                        
                        if validDataFound
                            if globalYMax > globalYMin
                                yPad = (globalYMax - globalYMin) * 0.1;
                                app.PlotAxes.YLim = [globalYMin - yPad, globalYMax + yPad];
                            else
                                app.PlotAxes.YLim = [globalYMin - 1, globalYMax + 1];
                            end
                        end
                    end
                    
                    % Update plot once per overall loop iteration
                    drawnow limitrate;
                    
                    % Write to CSV
                    if app.IsRunning
                        fprintf(fileID, '%f', currentTemp);
                        for c = 1:numChannels
                            fprintf(fileID, ',%e', stepVoltages(c));
                        end
                        fprintf(fileID, '\n');
                    end
                    
                    % Check if we've reached the target temperature
                    if abs(currentTemp - app.EndTempEdit.Value) < 0.05
                        break;
                    end
                    
                    % Interval Enforcement
                    timeTaken = toc(loopTimer);
                    remainingWait = app.IntervalEdit.Value - timeTaken;
                    if remainingWait > 0; pause(remainingWait); else; drawnow; end
                end
                
                % Clean Shutdown
                fclose(fileID);
                app.M81.setOutputState(false);
                app.Switcher.openAllChannels();
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                app.PlotAxes.Title.String = 'Sweep Complete';
                uialert(app.UIFigure, 'Temperature sweep finished successfully!', 'Complete');
                
            catch ME
                if exist('fileID', 'var') && fileID > 0; fclose(fileID); end
                if ~isempty(app.M81); app.M81.setOutputState(false); end
                if ~isempty(app.Switcher); app.Switcher.openAllChannels(); end
                
                app.IsRunning = false;
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                
                if ~strcmp(ME.identifier, 'App:UserStop')
                    uialert(app.UIFigure, sprintf('Error during measurement: %s', ME.message), 'Experiment Aborted');
                end
            end
        end
    end
end
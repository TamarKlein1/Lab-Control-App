classdef PPMSFieldSweepApp < handle
    % PPMSFieldSweepApp - Stepped Voltage vs. Magnetic Field Sweep
    % Includes Hot Swapping, Global Autoscaling, Back & Forth, Configurable Settle, 
    % Range Limits, Zero Field End, Safety Freeze, and Strict M81 AC Lock-in Routing
    
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
        
        StartFieldEdit, EndFieldEdit, StepEdit, RateEdit
        BackForthCheckBox, CyclesEdit, ZeroFieldCheckBox
        FieldSettleEdit 
        CurrentEdit, FreqEdit, TCEdit
        SrcRangeEdit, MeasRangeEdit
        HotSwapCheckBox
        
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox
        FilePathEdit
        
        PlotAxes
        AutoscaleBtn
        RunBtn, StopBtn
    end
    
    methods
        function app = PPMSFieldSweepApp()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'PPMS Voltage (Stepped Field Sweep)', 'Position', [100, 100, 1150, 870]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup', "Scrollable","on");
            scrollContainer = uipanel(controlPanel, 'BorderType','none','Position',[0,0,360,1100]);
            controlLayout = uigridlayout(scrollContainer, [7, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit', 50});
            
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
            title(app.PlotAxes, 'Voltage vs. Magnetic Field');
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Voltage (V)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'PPMS DLL Path:'); app.AddrPPMS = uieditfield(g, 'text', 'Value', 'C:\MATLAB\Lab_Control_Project\Drivers\QDInstrument.dll');
            uilabel(g, 'Text', 'M81 Address:');  app.AddrM81 = uieditfield(g, 'text', 'Value', 'GPIB1::12::INSTR');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'GPIB1::16::INSTR');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createSweepPanel(app, parent)
            p = uipanel(parent, 'Title', 'Stepped Magnetic Field Sweep');
            g = uigridlayout(p, [5, 4], 'ColumnWidth', {'fit', '1x', 'fit', '1x'});
            
            uilabel(g, 'Text', 'Start (Oe):'); app.StartFieldEdit = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End (Oe):');   app.EndFieldEdit = uieditfield(g, 'numeric', 'Value', 10000.0);
            
            uilabel(g, 'Text', 'Step (Oe):');  app.StepEdit = uieditfield(g, 'numeric', 'Value', 1000.0);
            uilabel(g, 'Text', 'Rate (Oe/s):');app.RateEdit = uieditfield(g, 'numeric', 'Value', 50.0);
            
            app.BackForthCheckBox = uicheckbox(g, 'Text', 'Back & Forth');
            app.BackForthCheckBox.Layout.Row = 3; app.BackForthCheckBox.Layout.Column = [1 2];
            
            lbl = uilabel(g, 'Text', 'Cycles:'); lbl.Layout.Row = 3; lbl.Layout.Column = 3;
            app.CyclesEdit = uieditfield(g, 'numeric', 'Value', 1); app.CyclesEdit.Layout.Row = 3; app.CyclesEdit.Layout.Column = 4;
            
            app.ZeroFieldCheckBox = uicheckbox(g, 'Text', 'Zero Field & Persistent at End?', 'Value', true);
            app.ZeroFieldCheckBox.Layout.Row = 4; app.ZeroFieldCheckBox.Layout.Column = [1 4];
            
            lblWait = uilabel(g, 'Text', 'Settle Time (s):'); lblWait.Layout.Row = 5; lblWait.Layout.Column = 1;
            app.FieldSettleEdit = uieditfield(g, 'numeric', 'Value', 5.0, 'Tooltip', 'Time to wait after field reaches target before measuring.');
            app.FieldSettleEdit.Layout.Row = 5; app.FieldSettleEdit.Layout.Column = 2;
        end
        
        function createM81Panel(app, parent)
            p = uipanel(parent, 'Title', 'M81 Lock-In Settings');
            g = uigridlayout(p, [5, 2], 'ColumnWidth', {'1x', 140}); 
            
            uilabel(g, 'Text', 'AC Current (A):');    app.CurrentEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Frequency (Hz):');    app.FreqEdit = uieditfield(g, 'numeric', 'Value', 17.7);
            uilabel(g, 'Text', 'Time Constant (s):'); app.TCEdit = uieditfield(g, 'numeric', 'Value', 0.1);
            
            uilabel(g, 'Text', 'Ranges (Src / Meas):');
            rangeGrid = uigridlayout(g, [1, 2], 'Padding', 0);
            app.SrcRangeEdit = uieditfield(rangeGrid, 'text', 'Value', 'AUTO', 'Tooltip', 'Source Range (e.g., AUTO, 1e-3)');
            app.MeasRangeEdit = uieditfield(rangeGrid, 'text', 'Value', 'AUTO', 'Tooltip', 'Measure Range (e.g., AUTO, 10e-3)');
            
            app.HotSwapCheckBox = uicheckbox(g, 'Text', 'Enable Hot Swap (Faster, Low Current)', 'Value', true);
            app.HotSwapCheckBox.Layout.Row = 5; app.HotSwapCheckBox.Layout.Column = [1 2];
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher Matrix');
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', '1x'}); 
            
            lbl1 = uilabel(g, 'Text', '+I (Row 1):'); lbl1.Layout.Row = 1; lbl1.Layout.Column = 1;
            app.ChanPosI = uieditfield(g, 'numeric', 'Value', 11); app.ChanPosI.Layout.Row = 1; app.ChanPosI.Layout.Column = 2;
            
            lbl2 = uilabel(g, 'Text', '-I (Row 2):'); lbl2.Layout.Row = 1; lbl2.Layout.Column = 3;
            app.ChanNegI = uieditfield(g, 'numeric', 'Value', 14); app.ChanNegI.Layout.Row = 1; app.ChanNegI.Layout.Column = 4;
            
            lbl3 = uilabel(g, 'Text', '+V (Row 3):'); lbl3.Layout.Row = 2; lbl3.Layout.Column = 1;
            app.ChanPosV = uieditfield(g, 'numeric', 'Value', 12); app.ChanPosV.Layout.Row = 2; app.ChanPosV.Layout.Column = 2;
            
            lbl4 = uilabel(g, 'Text', '-V (Row 4):'); lbl4.Layout.Row = 2; lbl4.Layout.Column = 3;
            app.ChanNegV = uieditfield(g, 'numeric', 'Value', 13); app.ChanNegV.Layout.Row = 2; app.ChanNegV.Layout.Column = 4;
            
            addBtn = uibutton(g, 'Text', 'Add Set', 'ButtonPushedFcn', @(s,e) app.addChannelSet()); 
            addBtn.Layout.Row = 3; addBtn.Layout.Column = [1 2];
            
            remBtn = uibutton(g, 'Text', 'Remove', 'ButtonPushedFcn', @(s,e) app.removeChannelSet()); 
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
        
        %% --- Configuration & Hardware ---
        function saveConfig(app)
            [file, path] = uiputfile('*.mat', 'Save Configuration');
            if file == 0; return; end
            
            config = struct();
            config.AddrPPMS     = app.AddrPPMS.Value;
            config.AddrM81      = app.AddrM81.Value;
            config.AddrSwitch   = app.AddrSwitch.Value;
            config.StartField   = app.StartFieldEdit.Value;
            config.EndField     = app.EndFieldEdit.Value;
            config.Step         = app.StepEdit.Value;
            config.Rate         = app.RateEdit.Value;
            config.BackForth    = app.BackForthCheckBox.Value;
            config.Cycles       = app.CyclesEdit.Value;
            config.ZeroField    = app.ZeroFieldCheckBox.Value;
            config.FieldSettle  = app.FieldSettleEdit.Value; 
            config.Current      = app.CurrentEdit.Value;
            config.Freq         = app.FreqEdit.Value;
            config.TC           = app.TCEdit.Value;
            config.SrcRange     = app.SrcRangeEdit.Value;
            config.MeasRange    = app.MeasRangeEdit.Value;
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
                
                app.AddrPPMS.Value       = c.AddrPPMS;
                app.AddrM81.Value        = c.AddrM81;
                app.AddrSwitch.Value     = c.AddrSwitch;
                app.StartFieldEdit.Value = c.StartField;
                app.EndFieldEdit.Value   = c.EndField;
                try app.StepEdit.Value   = c.Step; catch; end
                app.RateEdit.Value       = c.Rate;
                try app.BackForthCheckBox.Value = c.BackForth; catch; end
                try app.CyclesEdit.Value = c.Cycles; catch; end
                try app.ZeroFieldCheckBox.Value = c.ZeroField; catch; end
                try app.FieldSettleEdit.Value = c.FieldSettle; catch; end 
                app.CurrentEdit.Value    = c.Current;
                app.FreqEdit.Value       = c.Freq;
                app.TCEdit.Value         = c.TC;
                try app.SrcRangeEdit.Value = c.SrcRange; catch; end
                try app.MeasRangeEdit.Value = c.MeasRange; catch; end
                try app.HotSwapCheckBox.Value = c.HotSwap; catch; end
                app.ChannelSets          = c.ChannelSets;
                app.ChannelListBox.Items = c.ChannelItems;
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
                
                if ~isobject(app.PPMS)
                    error('QDPPMS driver returned a %s instead of a class object in SIM mode.', class(app.PPMS));
                end
                
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
                app.PlotAxes.XLimMode = 'auto';
                app.PlotAxes.YLimMode = 'auto';
            else
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
            
            % Generate Field Target Array Dynamically
            startF = app.StartFieldEdit.Value;
            endF = app.EndFieldEdit.Value;
            stepF = abs(app.StepEdit.Value);
            if stepF == 0; stepF = 1; end 
            
            [currF, ~] = app.PPMS.getCurrentField();
            
            if startF <= endF
                s2e_step = stepF;
                e2s_step = -stepF;
            else
                s2e_step = -stepF;
                e2s_step = stepF;
            end
            
            if app.BackForthCheckBox.Value
                cycles = max(1, round(app.CyclesEdit.Value));
                
                if abs(currF - startF) <= abs(currF - endF)
                    leg1 = startF : s2e_step : endF; if isempty(leg1) || leg1(end) ~= endF; leg1(end+1) = endF; end
                    leg2 = endF : e2s_step : startF; if isempty(leg2) || leg2(end) ~= startF; leg2(end+1) = startF; end
                else
                    leg1 = endF : e2s_step : startF; if isempty(leg1) || leg1(end) ~= startF; leg1(end+1) = startF; end
                    leg2 = startF : s2e_step : endF; if isempty(leg2) || leg2(end) ~= endF; leg2(end+1) = endF; end
                end
                
                baseCycle = [leg1, leg2(2:end)];
                fieldTargets = baseCycle;
                for i = 2:cycles
                    fieldTargets = [fieldTargets, baseCycle(2:end)];
                end
            else
                fieldTargets = startF : s2e_step : endF; 
                if isempty(fieldTargets) || fieldTargets(end) ~= endF; fieldTargets(end+1) = endF; end
            end
            
            targetFile = app.FilePathEdit.Value;
            if isempty(targetFile)
                [file, path] = uiputfile('*.csv', 'Select File to Save Data');
                if file == 0; return; end 
                targetFile = fullfile(path, file);
                app.FilePathEdit.Value = targetFile;
            end
            app.CurrentFile = app.resolveFilename(targetFile);
            
            fileID = fopen(app.CurrentFile, 'w');
            fprintf(fileID, '%% Experiment Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Lock-In Current: %e A | Freq: %f Hz | TC: %f s\n', app.CurrentEdit.Value, app.FreqEdit.Value, app.TCEdit.Value);
            fprintf(fileID, '%% Src Range: %s | Meas Range: %s\n', app.SrcRangeEdit.Value, app.MeasRangeEdit.Value);
            fprintf(fileID, '%% Field Sweep: %d Targets | Rate: %f Oe/sec | Settle: %.1f s\n', length(fieldTargets), app.RateEdit.Value, app.FieldSettleEdit.Value);
            
            headerStr = 'Magnetic_Field_Oe';
            for c = 1:numChannels
                vec = app.ChannelSets{c};
                headerStr = sprintf('%s,Voltage_c%d_%d_%d_%d', headerStr, vec(1), vec(2), vec(3), vec(4));
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
                % Hardware Prep - STRICT ROUTING RESTORED
                app.M81.setSourceMode('AC', app.CurrentEdit.Value, 0.0, app.FreqEdit.Value);
                app.M81.setSourceRange(app.SrcRangeEdit.Value);
                app.M81.setMeasureMode('LIA');
                app.M81.setMeasureRange(app.MeasRangeEdit.Value);
                app.M81.setTimeConstant(app.TCEdit.Value);
                
                if numChannels == 1 || app.HotSwapCheckBox.Value == true
                    app.Switcher.closeChannels(app.ChannelSets{1});
                    pause(0.2);
                    
                    % Identify 2-Wire vs 4-Wire and Route the M81 properly
                    vec = app.ChannelSets{1};
                    if (vec(1) == vec(3)) && (vec(2) == vec(4))
                        targetMode = 'TWOWire';
                    else
                        targetMode = '4WIRE';
                    end
                    app.M81.configureResistanceMode(targetMode, 'AC');
                    
                    app.M81.setOutputState(true);
                    pause(max(app.TCEdit.Value * 10, 5.0));
                end
                
                activeChannel = 1;
                
                % ==========================================
                % OUTER LOOP: Step Field Targets
                % ==========================================
                for tIdx = 1:length(fieldTargets)
                    if ~app.IsRunning; break; end
                    
                    targetF = fieldTargets(tIdx);
                    title(app.PlotAxes, sprintf('Ramping Field to %.1f Oe...', targetF));
                    
                    app.PPMS.setMagneticField(targetF, app.RateEdit.Value, 'Linear', 'Driven');
                    
                    % Wait for Field to hit target
                    while app.IsRunning
                        [currentField, ~] = app.PPMS.getCurrentField();
                        tolerance = max(2.0, 0.01 * abs(targetF)); 
                        if abs(currentField - targetF) < tolerance
                            title(app.PlotAxes, sprintf('Field reached %.1f Oe. Waiting %.1fs to stabilize...', currentField, app.FieldSettleEdit.Value));
                            pause(app.FieldSettleEdit.Value); 
                            break;
                        end
                        pause(1.0);
                    end
                    
                    if ~app.IsRunning; break; end
                    
                    [stableF, ~] = app.PPMS.getCurrentField();
                    title(app.PlotAxes, sprintf('Measuring Voltage at %.1f Oe...', stableF));
                    
                    stepVoltages = zeros(1, numChannels);
                    
                    for c = 1:numChannels
                        if ~app.IsRunning; break; end
                        
                        % Multiplexing & M81 Routing Update
                        if activeChannel ~= c || (numChannels > 1 && c == 1 && tIdx == 1)
                            
                            % Determine correct force/sense routing
                            vec = app.ChannelSets{c};
                            if (vec(1) == vec(3)) && (vec(2) == vec(4))
                                targetMode = 'TWOWire';
                            else
                                targetMode = '4WIRE';
                            end
                            
                            if app.HotSwapCheckBox.Value == true
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                app.M81.configureResistanceMode(targetMode, 'AC'); % Enforce Route
                                pause(max(app.TCEdit.Value * 5, 5.0)); 
                            else
                                app.M81.setOutputState(false);                  
                                pause(0.5); 
                                app.Switcher.closeChannels(app.ChannelSets{c}); 
                                pause(0.2); 
                                app.M81.configureResistanceMode(targetMode, 'AC'); % Enforce Route
                                app.M81.setOutputState(true);    
                                pause(max(app.TCEdit.Value * 10, 5.0));
                            end
                            activeChannel = c;
                        end
                        
                        % Still record raw Lock-in Voltage despite routing via resistance mode
                        vVal = NaN;
                        for attempt = 1:4
                            try
                                [X_real, ~, ~, ~] = app.M81.readLockIn();
                                vVal = X_real; 
                                if ~isnan(vVal) && abs(vVal) < 1e6; break; end
                            catch
                                pause(0.5);
                            end
                        end
                        
                        stepVoltages(c) = vVal;
                        if abs(vVal) < 1e6 
                            addpoints(app.DataLines{c}, stableF, vVal);
                        end
                    end
                    
                    if app.AutoscaleBtn.Value
                        globalYMin = inf; globalYMax = -inf; validDataFound = false;
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
                    drawnow limitrate;
                    
                    if app.IsRunning
                        fprintf(fileID, '%f', stableF);
                        for c = 1:numChannels
                            fprintf(fileID, ',%e', stepVoltages(c));
                        end
                        fprintf(fileID, '\n');
                    end
                    
                end 
                
                % ==========================================
                % POST-EXPERIMENT FIELD LOGIC
                % ==========================================
                if app.IsRunning
                    % Finished normally
                    [finalF, ~] = app.PPMS.getCurrentField();
                    if app.ZeroFieldCheckBox.Value
                        title(app.PlotAxes, 'Ramping to 0 Oe and going Persistent...');
                        app.PPMS.setMagneticField(0.0, app.RateEdit.Value, 'Linear', 'Persistent');
                    else
                        title(app.PlotAxes, 'Setting Persistent Mode at current field...');
                        app.PPMS.setMagneticField(finalF, app.RateEdit.Value, 'Linear', 'Persistent');
                    end
                else
                    % User pressed STOP button
                    title(app.PlotAxes, 'Sweep stopped. Freezing field in Persistent mode...');
                    [stoppedF, ~] = app.PPMS.getCurrentField();
                    app.PPMS.setMagneticField(stoppedF, app.RateEdit.Value, 'Linear', 'Persistent');
                end
                
                fclose(fileID);
                try app.M81.setOutputState(false); pause(0.5); catch; end
                try app.Switcher.openAllChannels(); catch; end
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                
                if app.IsRunning
                    title(app.PlotAxes, 'Sweep Complete');
                    uialert(app.UIFigure, 'Field sweep finished successfully!', 'Complete');
                else
                    title(app.PlotAxes, 'Sweep Stopped by User');
                end
                
            catch ME
                % If an error occurs, still try to safely freeze the field
                if ~isempty(app.PPMS) && isobject(app.PPMS)
                    try
                        [errF, ~] = app.PPMS.getCurrentField();
                        app.PPMS.setMagneticField(errF, app.RateEdit.Value, 'Linear', 'Persistent');
                    catch
                    end
                end
                
                if exist('fileID', 'var') && fileID > 0; fclose(fileID); end
                if ~isempty(app.M81) && isobject(app.M81); try app.M81.setOutputState(false); pause(0.5); catch; end; end
                if ~isempty(app.Switcher) && isobject(app.Switcher); try app.Switcher.openAllChannels(); catch; end; end
                
                app.IsRunning = false;
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                
                if ~strcmp(ME.identifier, 'App:UserStop')
                    if ~isempty(ME.stack)
                        errorLoc = sprintf('\n\n(Bug found in file: %s, Line: %d)', ME.stack(1).name, ME.stack(1).line);
                    else
                        errorLoc = '';
                    end
                    uialert(app.UIFigure, sprintf('Error during measurement: %s%s', ME.message, errorLoc), 'Experiment Aborted');
                end
            end
        end
    end
end
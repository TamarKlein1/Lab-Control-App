classdef PPMSFieldSweepApp < handle
    % PPMSFieldSweepApp - Multiplexed R vs. Magnetic Field Sweep
    
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
        
        StartFieldEdit, EndFieldEdit, RateEdit, IntervalEdit
        CurrentEdit, FreqEdit, TCEdit
        
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
            app.UIFigure = uifigure('Name', 'PPMS Magnetoresistance (Field Sweep)', 'Position', [100, 100, 1150, 850]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [7, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x', 'fit', 'fit', 50});
            
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
            title(app.PlotAxes, 'Resistance vs. Magnetic Field');
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Resistance (\Omega)');
            grid(app.PlotAxes, 'on');
            
            enableDefaultInteractivity(app.PlotAxes);
        end
        
        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'PPMS DLL Path:'); app.AddrPPMS = uieditfield(g, 'text', 'Value', 'C:\MATLAB\Lab_Control_Project\Drivers\QDInstrument.dll');
            uilabel(g, 'Text', 'M81 Address:');  app.AddrM81 = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createSweepPanel(app, parent)
            p = uipanel(parent, 'Title', 'Magnetic Field Sweep');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', 100});
            
            uilabel(g, 'Text', 'Start Field (Oe):'); app.StartFieldEdit = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End Field (Oe):');   app.EndFieldEdit = uieditfield(g, 'numeric', 'Value', 10000.0);
            uilabel(g, 'Text', 'Rate (Oe/sec):');    app.RateEdit = uieditfield(g, 'numeric', 'Value', 50.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.IntervalEdit = uieditfield(g, 'numeric', 'Value', 1.0);
        end
        
        function createM81Panel(app, parent)
            p = uipanel(parent, 'Title', 'M81 Lock-In Settings');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', 100});
            
            uilabel(g, 'Text', 'AC Current (A):');    app.CurrentEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Frequency (Hz):');    app.FreqEdit = uieditfield(g, 'numeric', 'Value', 17.0);
            uilabel(g, 'Text', 'Time Constant (s):'); app.TCEdit = uieditfield(g, 'numeric', 'Value', 0.1);
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher Matrix');
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', '1x'}); 
            
            % Row 1
            lbl1 = uilabel(g, 'Text', '+I (Row 1):'); lbl1.Layout.Row = 1; lbl1.Layout.Column = 1;
            app.ChanPosI = uieditfield(g, 'numeric', 'Value', 11); app.ChanPosI.Layout.Row = 1; app.ChanPosI.Layout.Column = 2;
            
            lbl2 = uilabel(g, 'Text', '-I (Row 2):'); lbl2.Layout.Row = 1; lbl2.Layout.Column = 3;
            app.ChanNegI = uieditfield(g, 'numeric', 'Value', 14); app.ChanNegI.Layout.Row = 1; app.ChanNegI.Layout.Column = 4;
            
            % Row 2
            lbl3 = uilabel(g, 'Text', '+V (Row 3):'); lbl3.Layout.Row = 2; lbl3.Layout.Column = 1;
            app.ChanPosV = uieditfield(g, 'numeric', 'Value', 12); app.ChanPosV.Layout.Row = 2; app.ChanPosV.Layout.Column = 2;
            
            lbl4 = uilabel(g, 'Text', '-V (Row 4):'); lbl4.Layout.Row = 2; lbl4.Layout.Column = 3;
            app.ChanNegV = uieditfield(g, 'numeric', 'Value', 13); app.ChanNegV.Layout.Row = 2; app.ChanNegV.Layout.Column = 4;
            
            % Row 3: Buttons
            addBtn = uibutton(g, 'Text', 'Add Set', 'ButtonPushedFcn', @(s,e) app.addChannelSet()); 
            addBtn.Layout.Row = 3; addBtn.Layout.Column = [1 2];
            
            remBtn = uibutton(g, 'Text', 'Remove', 'ButtonPushedFcn', @(s,e) app.removeChannelSet()); 
            remBtn.Layout.Row = 3; remBtn.Layout.Column = [3 4];
            
            % Row 4: ListBox
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
            config.Rate         = app.RateEdit.Value;
            config.Interval     = app.IntervalEdit.Value;
            config.Current      = app.CurrentEdit.Value;
            config.Freq         = app.FreqEdit.Value;
            config.TC           = app.TCEdit.Value;
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
                app.RateEdit.Value       = c.Rate;
                app.IntervalEdit.Value   = c.Interval;
                app.CurrentEdit.Value    = c.Current;
                app.FreqEdit.Value       = c.Freq;
                app.TCEdit.Value         = c.TC;
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
            fprintf(fileID, '%% PPMS Sweep: %f Oe to %f Oe at %f Oe/sec\n', app.StartFieldEdit.Value, app.EndFieldEdit.Value, app.RateEdit.Value);
            
            headerStr = 'Magnetic_Field_Oe';
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
                % Hardware Prep
                app.M81.setSourceMode('AC', app.CurrentEdit.Value, 0.0, app.FreqEdit.Value);
                app.M81.setSourceRange('AUTO');    
                app.M81.setMeasureMode('LIA');
                app.M81.setMeasureRange('AUTO');   
                app.M81.setTimeConstant(app.TCEdit.Value);
                app.M81.configureResistanceMode('4WIRE', 'AC');
                app.M81.setOutputState(false); 
                
                % 1. PPMS: Go to Start Field and Wait
                app.PlotAxes.Title.String = sprintf('Ramping to Start Field (%.1f Oe)...', app.StartFieldEdit.Value);
                app.PPMS.setMagneticField(app.StartFieldEdit.Value, 100.0, 'Linear', 'Driven');
                
                while app.IsRunning
                    [currentField, ~] = app.PPMS.getCurrentField();
                    
                    % We consider it stable when within 2 Oe or 1% of the target
                    tolerance = max(2.0, 0.01 * abs(app.StartFieldEdit.Value));
                    if abs(currentField - app.StartFieldEdit.Value) < tolerance
                        break;
                    end
                    pause(1);
                end
                
                if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end
                
                % 2. PPMS: Begin the Field Sweep
                app.PlotAxes.Title.String = 'Resistance vs. Magnetic Field Sweep';
                app.PPMS.setMagneticField(app.EndFieldEdit.Value, app.RateEdit.Value, 'Linear', 'Driven');
                pause(2); 
                
                % 3. Main R vs H Multiplexed Measurement Loop
                while app.IsRunning
                    loopTimer = tic;
                    
                    % Grab Live Field
                    [currentField, ~] = app.PPMS.getCurrentField();
                    stepVoltages = zeros(1, numChannels);
                    
                    for c = 1:numChannels
                        if ~app.IsRunning; break; end
                        
                        % ==========================================
                        % COLD SWAP SEQUENCE
                        % ==========================================
                        app.M81.setOutputState(false);                  
                        app.Switcher.closeChannels(app.ChannelSets{c}); 
                        pause(0.2);                                     
                        
                        app.M81.setOutputState(true);                   
                        settleTime = max(app.TCEdit.Value * 5, 1.5);
                        pause(settleTime);                    
                        % ==========================================
                        
                        % Read and Parse with a SMART RETRY LOOP
                        rVal = NaN;
                        for attempt = 1:4
                            try
                                rVal = app.M81.readResistance();
                                if isnan(rVal)
                                    [~, ~, R_mag, ~] = app.M81.readLockIn();
                                    rVal = R_mag / app.CurrentEdit.Value;
                                end
                                if ~isnan(rVal) && abs(rVal) < 1e6
                                    break; 
                                end
                            catch ME_Read
                                if attempt == 4; rethrow(ME_Read); end
                                pause(0.5);
                            end
                        end
                        
                        % Record valid data
                        stepVoltages(c) = rVal;
                        if abs(rVal) < 1e6 
                            addpoints(app.DataLines{c}, currentField, rVal);
                        end
                        drawnow limitrate;
                    end
                    
                    % Write to CSV
                    if app.IsRunning
                        fprintf(fileID, '%f', currentField);
                        for c = 1:numChannels
                            fprintf(fileID, ',%e', stepVoltages(c));
                        end
                        fprintf(fileID, '\n');
                    end
                    
                    % Check if we've reached the target field
                    if abs(currentField - app.EndFieldEdit.Value) < max(2.0, 0.01 * abs(app.EndFieldEdit.Value))
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
                uialert(app.UIFigure, 'Field sweep finished successfully!', 'Complete');
                
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
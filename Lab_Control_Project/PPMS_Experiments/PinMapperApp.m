classdef PinMapperApp < handle
    % PinMapperApp - A lightweight utility to map Keithley 3706A columns to physical pins
    
    properties
        UIFigure
        GridLayout
        IsRunning = false
        
        % Hardware Objects
        M81
        Switcher
    end
    
    properties (Access = private)
        % UI Handles
        AddrM81, AddrSwitch
        ConnectBtn, DisconnectBtn
        
        CurrentEdit, FreqEdit, TCEdit
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        
        ReadoutLabel
        RunBtn, StopBtn
    end
    
    methods
        function app = PinMapperApp()
            % Construct the GUI
            app.UIFigure = uifigure('Name', 'PPMS Pin Mapper Utility', 'Position', [100, 100, 800, 500]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {350, '1x'});
            
            % Left Panel: Controls
            controlPanel = uipanel(app.GridLayout, 'Title', 'Hardware Setup');
            controlLayout = uigridlayout(controlPanel, [4, 1], 'RowHeight', {'fit', 'fit', 'fit', '1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createM81Panel(controlLayout);
            app.createChannelPanel(controlLayout);
            
            % Right Panel: Live Readout
            readoutPanel = uipanel(app.GridLayout, 'Title', 'Live M81 Reading');
            readoutLayout = uigridlayout(readoutPanel, [2, 1], 'RowHeight', {'1x', 60});
            
            app.ReadoutLabel = uilabel(readoutLayout, 'Text', 'Ready', ...
                'FontSize', 48, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            
            % Big Control Buttons
            btnLayout = uigridlayout(readoutLayout, [1, 2]);
            app.RunBtn = uibutton(btnLayout, 'Text', 'START TEST', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runMapping());
            app.StopBtn = uibutton(btnLayout, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopMapping());
        end
        
        %% --- UI Builders ---
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'M81 USB/GPIB:');  app.AddrM81 = uieditfield(g, 'text', 'Value', 'SIM');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'SIM');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end
        
        function createM81Panel(app, parent)
            p = uipanel(parent, 'Title', 'M81 Excitation Settings');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', 100});
            
            uilabel(g, 'Text', 'AC Current (A):');    app.CurrentEdit = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Frequency (Hz):');    app.FreqEdit = uieditfield(g, 'numeric', 'Value', 17.0);
            uilabel(g, 'Text', 'Time Constant (s):'); app.TCEdit = uieditfield(g, 'numeric', 'Value', 0.1);
        end
        
        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', 'Active 3706 Columns (1-16)');
            g = uigridlayout(p, [2, 4]); 
            
            uilabel(g, 'Text', '+I:'); app.ChanPosI = uieditfield(g, 'numeric', 'Value', 1); 
            uilabel(g, 'Text', '-I:'); app.ChanNegI = uieditfield(g, 'numeric', 'Value', 2); 
            uilabel(g, 'Text', '+V:'); app.ChanPosV = uieditfield(g, 'numeric', 'Value', 3); 
            uilabel(g, 'Text', '-V:'); app.ChanNegV = uieditfield(g, 'numeric', 'Value', 4); 
        end
        
        %% --- Hardware Connection ---
        function disconnectHardware(app)
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
        
        %% --- Mapping Execution Logic ---
        function stopMapping(app)
            app.IsRunning = false;
        end
        
        function runMapping(app)
            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            app.ReadoutLabel.Text = 'Initializing...';
            app.ReadoutLabel.FontColor = 'black';
            drawnow;
            
            try
                % 1. Setup Matrix Routing
                targetColumns = [app.ChanPosI.Value, app.ChanNegI.Value, app.ChanPosV.Value, app.ChanNegV.Value, 0, 0];
                app.Switcher.openAllChannels();
                pause(0.2);
                app.Switcher.closeChannels(targetColumns);
                pause(0.5);
                
                % 2. Setup M81 (Locked to safe range, continuous output)
                app.M81.setSourceMode('AC', app.CurrentEdit.Value, 0.0, app.FreqEdit.Value);
                app.M81.setMeasureMode('LIA');
                maxExpectedVoltage = app.CurrentEdit.Value * 5000; % Lock range for 5kOhm max limit
                app.M81.setMeasureRange(maxExpectedVoltage); 
                app.M81.setTimeConstant(app.TCEdit.Value);
                app.M81.configureResistanceMode('4WIRE', 'AC');
                
                app.M81.setOutputState(true);
                pause(max(app.TCEdit.Value * 10, 1.0)); % Wait for turn-on transient to settle
                
                % 3. Live Reading Loop
                while app.IsRunning
                    rVal = NaN;
                    
                    % Smart retry to grab data
                    for attempt = 1:3
                        try
                            rVal = app.M81.readResistance();
                            if isnan(rVal)
                                [~, ~, R_mag, ~] = app.M81.readLockIn();
                                rVal = R_mag / app.CurrentEdit.Value;
                            end
                            break; 
                        catch
                            pause(0.2);
                        end
                    end
                    
                    % Update massive UI label
                    if isnan(rVal) || abs(rVal) > 4000
                        app.ReadoutLabel.Text = 'OPEN CIRCUIT';
                        app.ReadoutLabel.FontColor = [0.8 0.2 0.2]; % Red text
                    else
                        app.ReadoutLabel.Text = sprintf('%.2f \\Omega', rVal);
                        app.ReadoutLabel.FontColor = [0.2 0.8 0.2]; % Green text
                    end
                    
                    drawnow limitrate;
                    pause(0.3); % Gentle loop timing
                end
                
                % Clean Shutdown
                app.M81.setOutputState(false);
                app.Switcher.openAllChannels();
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                app.ReadoutLabel.Text = 'Stopped';
                app.ReadoutLabel.FontColor = 'black';
                
            catch ME
                app.IsRunning = false;
                if ~isempty(app.M81); app.M81.setOutputState(false); end
                if ~isempty(app.Switcher); app.Switcher.openAllChannels(); end
                
                app.RunBtn.Enable = 'on';
                app.StopBtn.Enable = 'off';
                app.ReadoutLabel.Text = 'Error';
                app.ReadoutLabel.FontColor = [0.8 0.2 0.2];
                uialert(app.UIFigure, ME.message, 'Hardware Error');
            end
        end
    end
end
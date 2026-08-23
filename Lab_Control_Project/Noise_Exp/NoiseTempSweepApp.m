classdef NoiseTempSweepApp < handle
    % NoiseTempSweepApp - SR785 Noise Analysis vs. LS335 Step-by-Step Temp Sweep
    
    properties
        UIFigure
        GridLayout
        
        TC       
        SR       
        
        IsRunning = false
        PollTimer        % טיימר לקריאת טמפרטורה ברקע
        IntegralTempX = []
        IntegralValY = []
        
        LineTrace
        LineIntegral
    end
    
    properties (Access = private)
        AddrTC, AddrSR, ConnectBtn, DisconnectBtn
        SaveDirEdit, BaseNameEdit, SkipSaveCheckbox
        
        TempStart, TempEnd, TempStep, TempTol, WaitTimeEdit
        RampRateEdit, RampCheckbox, ApplyRampBtn, HeaterRangeDrop
        LabelLiveTemp
        
        % שדות PID
        PEdit, IEdit, DEdit, ApplyPIDBtn
        
        GainEdit, SpanEdit, FreqMin, FreqMax
        
        RunBtn, StopBtn, SaveIntBtn
        StatusLabel
        
        AxTrace, AxIntegral
    end
    
    methods
        function app = NoiseTempSweepApp()
            app.UIFigure = uifigure('Name', 'SR785 Noise vs. Temperature Sweep', 'Position', [100, 100, 1200, 880]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {390, '1x'});
            
            controlPanel = uipanel(app.GridLayout, 'Title', 'Experiment Setup');
            controlLayout = uigridlayout(controlPanel, [6, 1], 'RowHeight', {'fit','fit','fit','fit','fit','1x'});
            
            app.createConnectionPanel(controlLayout);
            app.createSavePanel(controlLayout);
            app.createSweepPanel(controlLayout);
            app.createSR785Panel(controlLayout);
            app.createControlButtons(controlLayout);
            
            plotPanel = uipanel(app.GridLayout, 'Title', 'Live Data Monitoring');
            plotLayout = uigridlayout(plotPanel, [2, 1], 'RowHeight', {'1x', '1x'});
            
            app.AxTrace = uiaxes(plotLayout);
            title(app.AxTrace, 'Last Measured Noise Trace (Despiked)');
            xlabel(app.AxTrace, 'Frequency (Hz)');
            ylabel(app.AxTrace, 'Noise (V_{rms} / \surd Hz)');
            grid(app.AxTrace, 'on');
            app.AxTrace.YScale = 'log'; 
            app.LineTrace = plot(app.AxTrace, NaN, NaN, 'LineWidth', 1.5, 'Color', [0 0.447 0.741]);
            
            app.AxIntegral = uiaxes(plotLayout);
            title(app.AxIntegral, 'Integrated RMS Noise vs. Temperature');
            xlabel(app.AxIntegral, 'Temperature (K)');
            ylabel(app.AxIntegral, 'Total RMS Noise (V^2)');
            grid(app.AxIntegral, 'on');
            app.LineIntegral = plot(app.AxIntegral, NaN, NaN, '-o', 'LineWidth', 1.5, 'Color', [0.85 0.325 0.098]);
            
            % איתחול טיימר הרקע
            app.PollTimer = timer('ExecutionMode', 'fixedRate', 'Period', 1.0, ...
                                  'TimerFcn', @(~,~) app.pollHardware());
                              
            app.UIFigure.CloseRequestFcn = @(src,event) app.closeApp();
        end
        
        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', '1. Hardware Connections');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', '1x'});
            
            uilabel(g, 'Text', 'LS 335 (Temp):'); app.AddrTC = uieditfield(g, 'text', 'Value', 'GPIB0::5::INSTR');
            uilabel(g, 'Text', 'SR785 (Noise):'); app.AddrSR = uieditfield(g, 'text', 'Value', 'GPIB0::10::INSTR');
            
            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.disconnectHardware());
        end
        
        function createSavePanel(app, parent)
            p = uipanel(parent, 'Title', '2. Data Logging');
            g = uigridlayout(p, [3, 2], 'ColumnWidth', {'1x', 80});
            
            uilabel(g, 'Text', 'Folder Path:');
            btn = uibutton(g, 'Text', 'Browse...', 'ButtonPushedFcn', @(s,e) app.browseFolder());
            
            app.SaveDirEdit = uieditfield(g, 'text', 'Value', pwd);
            app.SaveDirEdit.Layout.Column = [1 2];
            
            app.BaseNameEdit = uieditfield(g, 'text', 'Value', 'NoiseSweep');
            app.SkipSaveCheckbox = uicheckbox(g, 'Text', 'Skip Saving', 'Value', false);
        end
        
        function createSweepPanel(app, parent)
            p = uipanel(parent, 'Title', '3. TC335 Sweep & Control');
            g = uigridlayout(p, [7, 4], 'ColumnWidth', {'fit','1x','fit','1x'});
            
            uilabel(g, 'Text', 'Start (K):'); app.TempStart = uieditfield(g, 'numeric', 'Value', 290.0);
            uilabel(g, 'Text', 'End (K):');   app.TempEnd = uieditfield(g, 'numeric', 'Value', 310.0);
            
            uilabel(g, 'Text', 'Step (K):');  app.TempStep = uieditfield(g, 'numeric', 'Value', 2.0);
            uilabel(g, 'Text', 'Tol (\pm K):'); app.TempTol = uieditfield(g, 'numeric', 'Value', 0.2);
            
            % שדה חדש להגדרת זמן ההמתנה בחלון היציבות
            uilabel(g, 'Text', 'Wait (s):');  app.WaitTimeEdit = uieditfield(g, 'numeric', 'Value', 120);
            uilabel(g, 'Text', 'Ramp (K/m):'); app.RampRateEdit = uieditfield(g, 'numeric', 'Value', 1.0);
            
            app.RampCheckbox = uicheckbox(g, 'Text', 'Enable', 'Value', true);
            app.ApplyRampBtn = uibutton(g, 'Text', 'Apply Ramp', 'ButtonPushedFcn', @(s,e) app.applyRamp());
            
            uilabel(g, 'Text', 'Heater:');       
            app.HeaterRangeDrop = uidropdown(g, 'Items', {'OFF','LOW','MED','HIGH'}, 'Value', 'LOW', 'ValueChangedFcn', @(s,e) app.updateHeater());
            
            uilabel(g, 'Text', 'Live Temp:');
            app.LabelLiveTemp = uilabel(g, 'Text', '--- K', 'FontWeight', 'bold', 'FontColor', 'blue');
            app.LabelLiveTemp.Layout.Column = [2 4];
            
            % שורת PID
            uilabel(g, 'Text', 'P:'); app.PEdit = uieditfield(g, 'numeric', 'Value', 50);
            uilabel(g, 'Text', 'I:'); app.IEdit = uieditfield(g, 'numeric', 'Value', 20);
            uilabel(g, 'Text', 'D:'); app.DEdit = uieditfield(g, 'numeric', 'Value', 0);
            app.ApplyPIDBtn = uibutton(g, 'Text', 'Apply PID', 'ButtonPushedFcn', @(s,e) app.applyPID());
        end
        
        function createSR785Panel(app, parent)
            p = uipanel(parent, 'Title', '4. SR785 Analysis & Integration');
            g = uigridlayout(p, [2, 4], 'ColumnWidth', {'fit','1x','fit','1x'});
            
            uilabel(g, 'Text', 'Amp Gain:'); app.GainEdit = uieditfield(g, 'numeric', 'Value', 1000);
            uilabel(g, 'Text', 'SR Span (Hz):'); app.SpanEdit = uieditfield(g, 'numeric', 'Value', 48.8281);
            
            uilabel(g, 'Text', 'Min Freq (Hz):'); app.FreqMin = uieditfield(g, 'numeric', 'Value', 1.0);
            uilabel(g, 'Text', 'Max Freq (Hz):'); app.FreqMax = uieditfield(g, 'numeric', 'Value', 48.0);
        end
        
        function createControlButtons(app, parent)
            g = uigridlayout(parent, [3, 2], 'RowHeight', {30, 30, 'fit'});
            
            app.RunBtn = uibutton(g, 'Text', 'START SWEEP', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runExperiment());
            app.StopBtn = uibutton(g, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopExperiment());
            
            app.SaveIntBtn = uibutton(g, 'Text', 'Save Integral Graph Now', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.saveIntegralGraph(false));
            app.SaveIntBtn.Layout.Column = [1 2];
            
            app.StatusLabel = uilabel(g, 'Text', 'Status: Ready', 'WordWrap', 'on');
            app.StatusLabel.Layout.Column = [1 2];
        end
        
        %% --- Background Polling ---
        function pollHardware(app)
            if ~app.IsRunning && ~isempty(app.TC) && isvalid(app.TC)
                try
                    currTemp = app.TC.readTemp('A');
                    app.LabelLiveTemp.Text = sprintf('%.3f K', currTemp);
                catch
                end
            end
        end
        
        %% --- Hardware Callbacks ---
        function connectHardware(app)
            try
                app.ConnectBtn.Text = 'Connecting...'; drawnow;
                delete(visadevfind);
                
                app.TC = Lakeshore.Lakeshore335(app.AddrTC.Value, 'A', 1);
                app.SR = NI.SR785(app.AddrSR.Value);
                
                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ConnectBtn.Enable = 'off';
                app.DisconnectBtn.Enable = 'on';
                app.RunBtn.Enable = 'on';
                
                try
                    [p, i, d] = app.TC.getPID(1);
                    app.PEdit.Value = p;
                    app.IEdit.Value = i;
                    app.DEdit.Value = d;
                catch
                end
                
                if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                    if strcmp(app.PollTimer.Running, 'off')
                        start(app.PollTimer);
                    end
                end
                
            catch ME
                app.disconnectHardware();
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end
        
        function disconnectHardware(app)
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                if strcmp(app.PollTimer.Running, 'on')
                    stop(app.PollTimer);
                end
            end
            
            try delete(app.TC); catch; end
            try delete(app.SR); catch; end
            app.TC = []; app.SR = [];
            
            app.ConnectBtn.Text = 'Connect';
            app.ConnectBtn.BackgroundColor = [0.96 0.96 0.96];
            app.ConnectBtn.Enable = 'on';
            app.DisconnectBtn.Enable = 'off';
            app.RunBtn.Enable = 'off';
            app.LabelLiveTemp.Text = '--- K';
        end
        
        function updateHeater(app)
            if ~isempty(app.TC) && isvalid(app.TC)
                app.TC.setHeaterRange(app.HeaterRangeDrop.Value, 1);
            end
        end
        
        function applyPID(app)
            if ~isempty(app.TC) && isvalid(app.TC)
                try
                    app.TC.setPID(app.PEdit.Value, app.IEdit.Value, app.DEdit.Value, 1);
                    app.StatusLabel.Text = 'Status: PID Updated!';
                    app.StatusLabel.FontColor = [0 0.5 0];
                catch ME
                    uialert(app.UIFigure, ME.message, 'PID Update Error');
                end
            end
        end
        
        function applyRamp(app)
            if ~isempty(app.TC) && isvalid(app.TC)
                try
                    app.TC.setRamp(app.RampCheckbox.Value, app.RampRateEdit.Value, 1);
                    app.StatusLabel.Text = sprintf('Status: Ramp Rate updated to %.2f K/min!', app.RampRateEdit.Value);
                    app.StatusLabel.FontColor = [0 0.5 0];
                catch ME
                    uialert(app.UIFigure, ME.message, 'Ramp Update Error');
                end
            end
        end
        
        function browseFolder(app)
            selpath = uigetdir(app.SaveDirEdit.Value, 'Select Folder to Save Data');
            if selpath ~= 0
                app.SaveDirEdit.Value = selpath;
            end
        end
        
        function stopExperiment(app)
            app.IsRunning = false;
            app.StatusLabel.Text = 'Status: Stopping...';
            
            if ~isempty(app.TC) && isvalid(app.TC)
                try
                    app.TC.setHeaterRange('OFF', 1);
                    app.TC.setRamp(false, 0, 1);
                    app.HeaterRangeDrop.Value = 'OFF';
                catch
                end
            end
            
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                if strcmp(app.PollTimer.Running, 'off')
                    start(app.PollTimer);
                end
            end
        end
        
        function runExperiment(app)
            if ~app.SkipSaveCheckbox.Value && ~exist(app.SaveDirEdit.Value, 'dir')
                uialert(app.UIFigure, 'The specified save directory does not exist.', 'Path Error');
                return;
            end
            
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                if strcmp(app.PollTimer.Running, 'on')
                    stop(app.PollTimer);
                end
            end
            
            app.StatusLabel.Text = 'Status: Validating SR785 frequency span...'; drawnow;
            
            [test_f, ~] = app.SR.readTrace(0, app.SpanEdit.Value);
            
            if isnan(test_f)
                uialert(app.UIFigure, 'Failed to read from SR785. Check connection.', 'Error');
                if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                    if strcmp(app.PollTimer.Running, 'off'); start(app.PollTimer); end
                end
                return;
            end
            
            if app.FreqMin.Value < min(test_f) || app.FreqMax.Value > max(test_f)
                uialert(app.UIFigure, sprintf('Integration bounds (%.1f-%.1f Hz) are outside the SR785 current span (%.1f-%.1f Hz).', app.FreqMin.Value, app.FreqMax.Value, min(test_f), max(test_f)), 'Frequency Bound Error');
                if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                    if strcmp(app.PollTimer.Running, 'off'); start(app.PollTimer); end
                end
                return;
            end
            
            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            app.SaveIntBtn.Enable = 'on';
            
            app.IntegralTempX = [];
            app.IntegralValY = [];
            set(app.LineTrace, 'XData', NaN, 'YData', NaN);
            set(app.LineIntegral, 'XData', NaN, 'YData', NaN);
            
            stepSign = sign(app.TempEnd.Value - app.TempStart.Value);
            stepSize = abs(app.TempStep.Value);
            if stepSign == 0
                targets = app.TempStart.Value;
            else
                targets = app.TempStart.Value : (stepSign * stepSize) : app.TempEnd.Value;
            end
            
            % ==========================================
            % SETUP STEP-BY-STEP SWEEP
            % ==========================================
            app.TC.setRamp(false, 0, 1);
            app.TC.setHeaterRange(app.HeaterRangeDrop.Value, 1);
            pause(0.5);
            app.TC.setRamp(app.RampCheckbox.Value, app.RampRateEdit.Value, 1);
            
            try
                for tIdx = 1:length(targets)
                    target = targets(tIdx);
                    if ~app.IsRunning; break; end
                    
                    % --- עדכון ה-Setpoint באופן ישיר לתחנה הנוכחית בלבד ---
                    app.StatusLabel.Text = sprintf('Status: Setting target to %.2f K...', target);
                    app.TC.setSetpoint(target, 1);
                    % --------------------------------------------------------
                    
                    inWindowTimer = 0;
                    windowEntered = false;
                    lastTick = tic;
                    
                    while app.IsRunning
                        currTemp = app.TC.readTemp('A');
                        app.LabelLiveTemp.Text = sprintf('%.3f K', currTemp);
                        
                        dt = toc(lastTick);
                        lastTick = tic;
                        
                        % בדיקה האם הגענו קרוב מספיק ליעד
                        if abs(currTemp - target) <= app.TempTol.Value
                            if ~windowEntered
                                windowEntered = true;
                                inWindowTimer = 0;
                                app.StatusLabel.Text = sprintf('Status: In Window. Waiting %.0fs... (Target: %.2fK)', app.WaitTimeEdit.Value, target);
                                app.StatusLabel.FontColor = [0 0.5 0]; 
                                
                                % איפוס המיצוע ברגע הכניסה לחלון היציבות
                                try
                                    app.SR.restartAveraging();
                                catch
                                    app.StatusLabel.Text = 'Status: WARNING - Failed to restart SR785 avg';
                                end
                            else
                                inWindowTimer = inWindowTimer + dt;
                            end
                            
                            % ממתינים את אורך החלון שהוגדר ב-WaitTimeEdit
                            if inWindowTimer >= app.WaitTimeEdit.Value
                                break; 
                            end
                        else
                            % אם הטמפרטורה יוצאת מהחלון - נאפס את הטיימר
                            if windowEntered
                                app.StatusLabel.Text = 'Status: WARNING - Temp left window! Restarting timer...';
                                app.StatusLabel.FontColor = 'red';
                                windowEntered = false;
                                inWindowTimer = 0;
                            else
                                app.StatusLabel.Text = sprintf('Status: Ramping towards %.2f K...', target);
                                app.StatusLabel.FontColor = 'black';
                            end
                        end
                        
                        pause(0.2); 
                        drawnow limitrate;
                    end
                    
                    if ~app.IsRunning; break; end
                    
                    app.StatusLabel.Text = 'Status: Triggering SR785 Measurement...';
                    app.StatusLabel.FontColor = 'black'; drawnow;
                    
                    [f, raw_noise] = app.SR.readTrace(0, app.SpanEdit.Value);
                    
                    if isnan(f)
                        error('Failed to retrieve trace from SR785 at %.2f K', currTemp);
                    end
                    
                    noise_normalized = raw_noise / app.GainEdit.Value;
                    noise_normalized = filloutliers(noise_normalized, 'center', 'movmedian', 25);
                    
                    set(app.LineTrace, 'XData', f, 'YData', noise_normalized);
                    
                    mask = (f >= app.FreqMin.Value) & (f <= app.FreqMax.Value);
                    freq_masked = f(mask);
                    noise_masked = noise_normalized(mask);
                    
                    psd = noise_masked.^2;
                    total_noise_squared = trapz(freq_masked, psd);
                    
                    intVal = total_noise_squared;
                    
                    titleStr = sprintf('Last Trace (%.2f K) | Integral: %.2e V^2', currTemp, intVal);
                    title(app.AxTrace, titleStr);
                    
                    app.IntegralTempX(end+1) = currTemp;
                    app.IntegralValY(end+1) = intVal;
                    set(app.LineIntegral, 'XData', app.IntegralTempX, 'YData', app.IntegralValY);
                    
                    drawnow;
                    
                    if ~app.SkipSaveCheckbox.Value
                        fileNameBase = sprintf('%s_%.1fK', app.BaseNameEdit.Value, target);
                        fullFilePath = fullfile(app.SaveDirEdit.Value, fileNameBase);
                        
                        save([fullFilePath '.mat'], 'f', 'noise_normalized', 'intVal', 'currTemp', 'target');
                        app.saveTraceFig(f, noise_normalized, titleStr, [fullFilePath '.fig']);
                    end
                end
                
                try
                    app.TC.setHeaterRange('OFF', 1);
                    app.TC.setRamp(false, 0, 1);
                    app.HeaterRangeDrop.Value = 'OFF';
                catch
                end
                
                if app.IsRunning && ~app.SkipSaveCheckbox.Value
                    app.saveIntegralGraph(true);
                end
                
                app.StatusLabel.Text = 'Status: Experiment Complete (Heater OFF).';
                app.StatusLabel.FontColor = [0 0.5 0];
                
            catch ME
                if ~isempty(app.TC) && isvalid(app.TC)
                    try
                        app.TC.setHeaterRange('OFF', 1);
                        app.TC.setRamp(false, 0, 1);
                        app.HeaterRangeDrop.Value = 'OFF';
                    catch
                    end
                end
                
                app.StatusLabel.Text = 'Status: Error occurred (Heater turned OFF).';
                app.StatusLabel.FontColor = 'red';
                uialert(app.UIFigure, sprintf('Error during sweep: %s', ME.message), 'Sweep Aborted');
            end
            
            app.IsRunning = false;
            app.RunBtn.Enable = 'on';
            app.StopBtn.Enable = 'off';
            
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                if strcmp(app.PollTimer.Running, 'off')
                    start(app.PollTimer);
                end
            end
        end
        
        %% --- Save Utility ---
        
        function saveTraceFig(~, f, noise_normalized, titleStr, savePath)
            hiddenFig = figure('Visible', 'off');
            plot(f, noise_normalized, 'LineWidth', 1.5, 'Color', [0 0.447 0.741]);
            grid on;
            if max(f) > 1; xlim([1, max(f)]); end
            set(gca, 'YScale', 'log'); 
            title(titleStr);
            xlabel('Frequency (Hz)');
            ylabel('Noise (V_{rms} / \surd Hz)');
            set(hiddenFig, 'CreateFcn', 'set(gcf, ''Visible'', ''on'')');
            savefig(hiddenFig, savePath);
            close(hiddenFig);
        end
        
        function saveIntFig(~, tempX, intY, savePath)
            hiddenFig = figure('Visible', 'off');
            plot(tempX, intY, '-o', 'LineWidth', 1.5, 'Color', [0.85 0.325 0.098]);
            grid on;
            title('Integrated RMS Noise vs. Temperature');
            xlabel('Temperature (K)');
            ylabel('Total RMS Noise (V^2)'); 
            set(hiddenFig, 'CreateFcn', 'set(gcf, ''Visible'', ''on'')');
            savefig(hiddenFig, savePath);
            close(hiddenFig);
        end
        
        function saveIntegralGraph(app, isAutoSave)
            if isempty(app.IntegralTempX); return; end
            
            if isAutoSave
                name = sprintf('%s_Final_Integral', app.BaseNameEdit.Value);
            else
                name = sprintf('%s_ManualSave_Integral', app.BaseNameEdit.Value);
            end
            fullFilePath = fullfile(app.SaveDirEdit.Value, name);
            
            T = app.IntegralTempX;
            Integral = app.IntegralValY;
            save([fullFilePath '.mat'], 'T', 'Integral');
            
            app.saveIntFig(app.IntegralTempX, app.IntegralValY, [fullFilePath '.fig']);
            
            if ~isAutoSave
                uialert(app.UIFigure, sprintf('Integral graph saved manually to:\n%s', app.SaveDirEdit.Value), 'Saved');
            end
        end
        
        function closeApp(app)
            app.IsRunning = false;
            app.disconnectHardware();
            
            if ~isempty(app.PollTimer) && isvalid(app.PollTimer)
                stop(app.PollTimer);
                delete(app.PollTimer);
            end
            
            delete(app.UIFigure);
        end
    end
end
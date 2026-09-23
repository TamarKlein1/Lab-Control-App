classdef PPMSDeltaTamarController < handle
    % PPMSDeltaTamarController - Queue-based runner for PPMS experiments.

    properties
        UIFigure
        GridLayout

        % Hardware Objects
        PPMS
        DeltaMode
        Switcher

        % Queue State
        ExperimentQueue = {}
        IsRunning = false
    end

    properties (Access = private)
        AddrPPMS, AddrDelta, AddrSwitch
        ConnectBtn, DisconnectBtn
        EmailEdit
        GmailLogin = ''
        GmailPassword = ''
        OutputFolderEdit
        ExperimentListBox
        AddExperimentBtn, LoadExperimentBtn, RemoveExperimentBtn, MoveUpBtn, MoveDownBtn
        RenameExperimentBtn, DuplicateExperimentBtn
        ShutdownCheckbox
        HeliumThresholdEdit
        RunBtn, StopBtn
        HeliumTimer
        PlotAxes
        LogTextArea
        LastClosedChannel = []
    end

    methods
        function app = PPMSDeltaTamarController()
            app.UIFigure = uifigure('Name', 'PPMS Tamar Controller', 'Position', [100, 100, 1150, 650], ...
                'CloseRequestFcn', @(s,e) app.onAppClose());
            movegui(app.UIFigure, 'center');
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {380, '1x'});

            leftPanel = uipanel(app.GridLayout, 'Title', 'Controller');
            leftLayout = uigridlayout(leftPanel, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', 280, 'fit'}, 'Scrollable', 'on');

            app.createConnectionPanel(leftLayout);
            app.createNotificationPanel(leftLayout);
            app.createOutputFolderPanel(leftLayout);
            app.createQueuePanel(leftLayout);
            app.createRunPanel(leftLayout);

            rightPanel = uipanel(app.GridLayout, 'Title', 'Live Data & Log');
            rightLayout = uigridlayout(rightPanel, [2, 1], 'RowHeight', {'1x', '1x'});

            plotContainer = uipanel(rightLayout, 'Title', 'Live Data');
            plotLayout = uigridlayout(plotContainer, [1, 1]);
            app.PlotAxes = uiaxes(plotLayout);
            title(app.PlotAxes, 'Live Data');
            grid(app.PlotAxes, 'on');
            enableDefaultInteractivity(app.PlotAxes);

            logContainer = uipanel(rightLayout, 'Title', 'Log');
            logLayout = uigridlayout(logContainer, [1, 1]);
            app.LogTextArea = uitextarea(logLayout, 'Editable', 'off');

            app.loadGmailCredentials();
        end

        function createConnectionPanel(app, parent)
            p = uipanel(parent, 'Title', 'Hardware Connections');
            g = uigridlayout(p, [4, 2], 'ColumnWidth', {'1x', '1x'});

            uilabel(g, 'Text', 'PPMS DLL Path:'); app.AddrPPMS  = uieditfield(g, 'text', 'Value', 'C:\MATLAB\Lab_Control_Project\Drivers\QDInstrument.dll');
            uilabel(g, 'Text', '6221/2182A:');    app.AddrDelta = uieditfield(g, 'text', 'Value', 'GPIB1::12::INSTR');
            uilabel(g, 'Text', '3706 Switch:');   app.AddrSwitch = uieditfield(g, 'text', 'Value', 'GPIB1::16::INSTR');

            app.ConnectBtn = uibutton(g, 'Text', 'Connect', 'ButtonPushedFcn', @(s,e) app.connectHardware());
            app.DisconnectBtn = uibutton(g, 'Text', 'Disconnect', 'ButtonPushedFcn', @(s,e) app.disconnectHardware(), 'Enable', 'off');
        end

        function createNotificationPanel(app, parent)
            p = uipanel(parent, 'Title', 'Email Notifications');
            g = uigridlayout(p, [2, 1], 'RowHeight', {'fit', 'fit'});

            addrRow = uigridlayout(g, [1, 2], 'ColumnWidth', {'fit', '1x'});
            uilabel(addrRow, 'Text', 'Send updates to:');
            app.EmailEdit = uieditfield(addrRow, 'text', 'Placeholder', 'name@example.com');

            btnRow = uigridlayout(g, [1, 2]);
            uibutton(btnRow, 'Text', 'Send Test Email', 'ButtonPushedFcn', @(s,e) app.sendTestEmail());
            uibutton(btnRow, 'Text', 'Forget Saved Login', 'ButtonPushedFcn', @(s,e) app.forgetGmailCredentials());
        end

        function sendTestEmail(app)
            recipient = strtrim(app.EmailEdit.Value);
            if isempty(recipient)
                uialert(app.UIFigure, 'Enter a recipient email address first.', 'Missing Address');
                return;
            end

            if ~app.ensureGmailCredentials()
                app.logMessage('Test email skipped (no credentials provided).');
                return;
            end

            app.sendNotification('PPMS: Test Email', 'This is a test email from PPMS Tamar Controller.');
        end

        function createOutputFolderPanel(app, parent)
            p = uipanel(parent, 'Title', 'Output Folder');
            g = uigridlayout(p, [1, 2], 'ColumnWidth', {'1x', 70});
            app.OutputFolderEdit = uieditfield(g, 'text', 'Placeholder', 'Base folder for all experiment data...');
            uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(s,e) app.browseOutputFolder());
        end

        function browseOutputFolder(app)
            folder = uigetdir(app.OutputFolderEdit.Value, 'Select Base Output Folder');
            if ~isequal(folder, 0)
                app.OutputFolderEdit.Value = folder;
            end
        end

        function createQueuePanel(app, parent)
            p = uipanel(parent, 'Title', 'Experiment Queue');
            g = uigridlayout(p, [5, 1], 'RowHeight', {'fit', '1x', 'fit', 'fit', 'fit'});

            addRow = uigridlayout(g, [1, 2]);
            app.AddExperimentBtn = uibutton(addRow, 'Text', 'New Experiment...', 'ButtonPushedFcn', @(s,e) app.openExperimentEditor());
            app.LoadExperimentBtn = uibutton(addRow, 'Text', 'Load Experiment...', 'ButtonPushedFcn', @(s,e) app.loadExperiment());

            app.ExperimentListBox = uilistbox(g, 'Items', {}, 'DoubleClickedFcn', @(s,e) app.editSelectedExperiment());

            moveRow = uigridlayout(g, [1, 2]);
            app.MoveUpBtn = uibutton(moveRow, 'Text', 'Up', 'ButtonPushedFcn', @(s,e) app.moveExperimentUp());
            app.MoveDownBtn = uibutton(moveRow, 'Text', 'Down', 'ButtonPushedFcn', @(s,e) app.moveExperimentDown());

            editRow = uigridlayout(g, [1, 3]);
            app.RenameExperimentBtn = uibutton(editRow, 'Text', 'Rename', 'ButtonPushedFcn', @(s,e) app.renameExperiment());
            app.DuplicateExperimentBtn = uibutton(editRow, 'Text', 'Duplicate', 'ButtonPushedFcn', @(s,e) app.duplicateExperiment());
            app.RemoveExperimentBtn = uibutton(editRow, 'Text', 'Remove', 'ButtonPushedFcn', @(s,e) app.removeExperiment());

            app.ShutdownCheckbox = uicheckbox(g, 'Text', 'Shutdown after running all', 'Value', false);
        end

        function createRunPanel(app, parent)
            g = uigridlayout(parent, [2, 1], 'RowHeight', {'fit', 'fit'});

            thresholdRow = uigridlayout(g, [1, 2], 'ColumnWidth', {'1x', 80});
            uilabel(thresholdRow, 'Text', 'Helium Shutdown Threshold (%):');
            app.HeliumThresholdEdit = uieditfield(thresholdRow, 'numeric', 'Value', 60, 'Limits', [0 100]);

            btnRow = uigridlayout(g, [1, 2]);
            app.RunBtn = uibutton(btnRow, 'Text', 'RUN QUEUE', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.runQueue());
            app.StopBtn = uibutton(btnRow, 'Text', 'STOP', 'BackgroundColor', [0.8 0.2 0.2], 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.stopQueue());
        end

        function disconnectHardware(app)
            try delete(app.PPMS); app.PPMS = []; catch; end
            try delete(app.DeltaMode); app.DeltaMode = []; catch; end
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

                app.PPMS      = QuantumDesign.QDPPMS(app.AddrPPMS.Value);
                app.DeltaMode = Keithley.Keithley6221_2182A(app.AddrDelta.Value);
                app.Switcher  = Keithley.Keithley3706(app.AddrSwitch.Value);

                app.ConnectBtn.Text = 'Connected';
                app.ConnectBtn.BackgroundColor = [0.2 0.8 0.2];
                app.ConnectBtn.Enable = 'off';
                app.DisconnectBtn.Enable = 'on';
                app.RunBtn.Enable = 'on';
                app.logMessage('Hardware connected.');
            catch ME
                app.disconnectHardware();
                app.ConnectBtn.Text = 'Retry Connection';
                app.ConnectBtn.BackgroundColor = [0.8 0.2 0.2];
                app.logMessage(sprintf('Connection error: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Connection Error');
            end
        end

        function openExperimentEditor(app)
            def = PPMSDeltaExperimentEditor.run();
            if isempty(def); return; end
            app.addExperimentToQueue(def);
        end

        function editSelectedExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = PPMSDeltaExperimentEditor.run(app.ExperimentQueue{idx});
            if isempty(def); return; end

            app.ExperimentQueue{idx} = def;
            app.ExperimentListBox.Items{idx} = app.formatQueueLabel(def);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx};
        end

        function addExperimentToQueue(app, definition)
            label = app.formatQueueLabel(definition);
            app.ExperimentQueue{end+1} = definition;
            app.ExperimentListBox.Items{end+1} = label;
            app.ExperimentListBox.Value = label;
        end

        function label = formatQueueLabel(~, definition)
            label = sprintf('%s [%s]', definition.Name, definition.Type);
        end

        function loadExperiment(app)
            [file, path] = uigetfile('*.mat', 'Load Experiment Definition');
            if isequal(file, 0); return; end

            try
                data = load(fullfile(path, file), 'experiment');
                def = data.experiment;
                def.DefinitionFile = fullfile(path, file);
                app.addExperimentToQueue(def);
            catch ME
                uialert(app.UIFigure, sprintf('Failed to load experiment file: %s', ME.message), 'Load Error');
            end
        end

        function renameExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = app.ExperimentQueue{idx};
            answer = inputdlg('New name:', 'Rename Experiment', [1 50], {def.Name});
            if isempty(answer); return; end

            newName = strtrim(answer{1});
            if isempty(newName); return; end

            def.Name = newName;
            def = app.renameDefinitionFile(def);

            app.ExperimentQueue{idx} = def;
            app.ExperimentListBox.Items{idx} = app.formatQueueLabel(def);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx};
        end

        function duplicateExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end

            def = app.ExperimentQueue{idx};
            def.Name = [def.Name ' (Copy)'];

            if isfield(def, 'DefinitionFile') && ~isempty(def.DefinitionFile)
                def.DefinitionFile = app.resolveDuplicateFilename(def.DefinitionFile);
                app.resaveDefinitionFile(def);
            end

            label = app.formatQueueLabel(def);
            app.ExperimentQueue = [app.ExperimentQueue(1:idx), {def}, app.ExperimentQueue(idx+1:end)];
            app.ExperimentListBox.Items = [app.ExperimentListBox.Items(1:idx), {label}, app.ExperimentListBox.Items(idx+1:end)];
            app.ExperimentListBox.Value = label;
        end

        function resaveDefinitionFile(app, def)
            if ~isfield(def, 'DefinitionFile') || isempty(def.DefinitionFile); return; end
            try
                experiment = def; %#ok<NASGU>
                save(def.DefinitionFile, 'experiment');
            catch ME
                app.logMessage(sprintf('Could not update saved experiment file: %s', ME.message));
            end
        end

        function def = renameDefinitionFile(app, def)
            if ~isfield(def, 'DefinitionFile') || isempty(def.DefinitionFile)
                return;
            end

            [filepath, ~, ext] = fileparts(def.DefinitionFile);
            safeName = regexprep(def.Name, '[^\w\- ]', '');
            if isempty(safeName); safeName = 'Experiment'; end
            desiredFile = fullfile(filepath, [safeName ext]);
            newFile = app.resolveUniqueFilename(desiredFile, def.DefinitionFile);

            try
                if ~strcmp(newFile, def.DefinitionFile) && isfile(def.DefinitionFile)
                    movefile(def.DefinitionFile, newFile);
                end
                def.DefinitionFile = newFile;
                app.resaveDefinitionFile(def);
            catch ME
                app.logMessage(sprintf('Could not rename saved experiment file: %s', ME.message));
            end
        end

        function candidate = resolveUniqueFilename(~, desiredFile, currentFile)
            if strcmp(desiredFile, currentFile)
                candidate = desiredFile;
                return;
            end
            [filepath, name, ext] = fileparts(desiredFile);
            candidate = desiredFile;
            counter = 1;
            while isfile(candidate) && ~strcmp(candidate, currentFile)
                counter = counter + 1;
                candidate = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
            end
        end

        function candidate = resolveDuplicateFilename(~, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            candidate = fullfile(filepath, [name '_copy' ext]);
            counter = 1;
            while isfile(candidate)
                counter = counter + 1;
                candidate = fullfile(filepath, sprintf('%s_copy%d%s', name, counter, ext));
            end
        end

        function removeExperiment(app)
            idx = app.selectedQueueIndex();
            if isempty(idx); return; end
            app.ExperimentQueue(idx) = [];
            app.ExperimentListBox.Items(idx) = [];
            if ~isempty(app.ExperimentListBox.Items)
                app.ExperimentListBox.Value = app.ExperimentListBox.Items{min(idx, end)};
            end
        end

        function moveExperimentUp(app)
            idx = app.selectedQueueIndex();
            if isempty(idx) || idx == 1; return; end
            app.swapQueueItems(idx, idx - 1);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx - 1};
        end

        function moveExperimentDown(app)
            idx = app.selectedQueueIndex();
            if isempty(idx) || idx == numel(app.ExperimentListBox.Items); return; end
            app.swapQueueItems(idx, idx + 1);
            app.ExperimentListBox.Value = app.ExperimentListBox.Items{idx + 1};
        end

        function idx = selectedQueueIndex(app)
            idx = find(strcmp(app.ExperimentListBox.Items, app.ExperimentListBox.Value));
        end

        function swapQueueItems(app, i, j)
            app.ExperimentQueue([i j]) = app.ExperimentQueue([j i]);
            app.ExperimentListBox.Items([i j]) = app.ExperimentListBox.Items([j i]);
        end

        function stopQueue(app)
            app.IsRunning = false;
            app.logMessage('Stop requested by user.');
        end

        function runQueue(app)
            if isempty(app.ExperimentQueue)
                uialert(app.UIFigure, 'Add at least one experiment to the queue.', 'Queue Empty');
                return;
            end

            if isempty(strtrim(app.OutputFolderEdit.Value))
                uialert(app.UIFigure, 'Set a base output folder before running the queue.', 'Output Folder Missing');
                return;
            end

            if ~isempty(strtrim(app.EmailEdit.Value)) && ~app.ensureGmailCredentials()
                app.logMessage('Email notifications skipped (no credentials provided).');
            end

            app.IsRunning = true;
            app.RunBtn.Enable = 'off';
            app.StopBtn.Enable = 'on';
            app.logMessage(sprintf('Starting queue: %d experiment(s).', numel(app.ExperimentQueue)));

            app.startHeliumWatchdog();
            watchdogCleanup = onCleanup(@() app.stopHeliumWatchdog()); %#ok<NASGU>

            try
                for i = 1:numel(app.ExperimentQueue)
                    if ~app.IsRunning; break; end
                    def = app.ExperimentQueue{i};
                    name = app.ExperimentListBox.Items{i};
                    app.logMessage(sprintf('Running experiment %d/%d: %s', i, numel(app.ExperimentQueue), name));

                    switch def.Type
                        case 'FieldSweep'
                            app.runFieldSweepExperiment(def);
                        case {'AngleSweep', 'RotatorSweep'}
                            app.runAngleSweepExperiment(def);
                        case 'CurrentSweep'
                            app.runCurrentSweepExperiment(def);
                        otherwise
                            app.logMessage(sprintf('Experiment type "%s" is not implemented yet - skipping.', def.Type));
                    end

                    if ~app.IsRunning; break; end

                    app.sendNotification(sprintf('PPMS: Experiment Finished - %s', name), ...
                        sprintf('Experiment %d/%d "%s" has finished.', i, numel(app.ExperimentQueue), name));
                end

                if app.IsRunning
                    app.sendNotification('PPMS: Queue Finished', ...
                        sprintf('The experiment queue completed all %d experiment(s).', numel(app.ExperimentQueue)));
                else
                    app.sendNotification('PPMS: Queue Stopped', ...
                        sprintf('The experiment queue was stopped by the user (%d experiment(s) in the list).', numel(app.ExperimentQueue)));
                end

                if app.IsRunning && app.ShutdownCheckbox.Value
                    app.performShutdown();
                end

                app.logMessage('Queue finished.');
            catch ME
                if strcmp(ME.identifier, 'App:UserStop')
                    app.logMessage('Queue stopped by user during experiment execution.');
                    app.sendNotification('PPMS: Queue Stopped', ...
                        sprintf('The experiment queue was stopped by the user (%d experiment(s) in the list).', numel(app.ExperimentQueue)));
                else
                    app.logMessage(sprintf('Queue aborted: %s', ME.message));
                    app.sendNotification('PPMS: Queue Error', sprintf('The experiment queue aborted with an error: %s', ME.message));
                    uialert(app.UIFigure, ME.message, 'Queue Error');
                end
            end

            app.IsRunning = false;
            app.RunBtn.Enable = 'on';
            app.StopBtn.Enable = 'off';
        end

        %% --- Experiment Execution: Field Sweep ---
        function runFieldSweepExperiment(app, def)
            if isempty(app.PPMS) || isempty(app.DeltaMode) || isempty(app.Switcher)
                error('Hardware is not connected.');
            end

            numChannels = length(def.ChannelSets);
            if numChannels == 0
                error('Experiment "%s" has no channel sets configured.', def.Name);
            end

            app.LastClosedChannel = [];

            dataFile = app.resolveExperimentDataFile(def);
            fileID = fopen(dataFile, 'w');
            if fileID < 0
                error('Could not open data file: %s', dataFile);
            end
            fileCleanup = onCleanup(@() app.safeCloseFile(fileID)); %#ok<NASGU>
            hwCleanup = onCleanup(@() app.safeStopMeasurement()); %#ok<NASGU>

            p = def.Params;
            staticTemp = def.Static.Temperature;
            staticAngle = def.Static.Angle;
            fromZero = isfield(p, 'FromZero') && p.FromZero;

            tempRate = 10.0;
            tempApproach = 'FastSettle';
            if isfield(def.Static, 'TempRate') && ~isempty(def.Static.TempRate)
                tempRate = def.Static.TempRate;
            end
            if isfield(def.Static, 'TempApproach') && ~isempty(def.Static.TempApproach)
                tempApproach = def.Static.TempApproach;
            end

            if isfield(def, 'Delta')
                posI    = def.Delta.PosI;
                negI    = def.Delta.NegI;
                repeats = def.Delta.Repeats;
                delay   = def.Delta.Delay;
                vRange  = def.Delta.Range;
            else
                posI    = 10e-6;
                negI    = -10e-6;
                repeats = 3;
                delay   = 0.1;
                vRange  = 'Auto';
            end

            fprintf(fileID, '%% Experiment: %s\n', def.Name);
            fprintf(fileID, '%% Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Delta Current (+I): %e A | (-I): %e A\n', posI, negI);
            fprintf(fileID, '%% Delta Repeats: %d | Delay: %f s | Range: %s\n', repeats, delay, vRange);
            fprintf(fileID, '%% Static Temperature: %f K (Rate: %f K/min, Approach: %s)\n', staticTemp, tempRate, tempApproach);
            fprintf(fileID, '%% Static Angle: %f deg\n', staticAngle);
            fprintf(fileID, '%% PPMS Sweep: %f Oe to %f Oe at %f Oe/sec\n', p.StartField, p.EndField, p.Rate);
            fprintf(fileID, '%% Repetitions: %d | Back-and-forth: %d\n', def.Repeat.Repetitions, def.Repeat.BackAndForth);
            fprintf(fileID, '%% Start from zero: %d (Repetition 0 = 0 Oe to start field)\n', fromZero);

            headerParts = {'Time_s', 'Repetition'};
            for c = 1:numChannels
                vec = def.ChannelSets{c};
                chanLabel = sprintf('%d_%d_%d_%d', vec(1), vec(2), vec(3), vec(4));
                headerParts{end+1} = sprintf('Field_Oe_%s', chanLabel); %#ok<AGROW>
                headerParts{end+1} = sprintf('V_Delta_%s', chanLabel); %#ok<AGROW>
            end
            fprintf(fileID, '%s\n', strjoin(headerParts, ','));

            cla(app.PlotAxes);
            title(app.PlotAxes, sprintf('%s - Delta Voltage vs. Magnetic Field', def.Name));
            xlabel(app.PlotAxes, 'Magnetic Field (Oe)');
            ylabel(app.PlotAxes, 'Delta Voltage (V)');
            grid(app.PlotAxes, 'on');
            dataLines = cell(1, numChannels);
            colors = lines(numChannels);
            for c = 1:numChannels
                dataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            legend(app.PlotAxes, def.ChannelItems, 'Location', 'best');

            try
                app.DeltaMode.disarmDeltaMode();
                pause(0.2);
            catch
            end

            if ismethod(app.DeltaMode, 'setVoltageRange')
                app.DeltaMode.setVoltageRange(vRange);
            end

            app.DeltaMode.setupDeltaMode(posI, negI, repeats, 'oneshot', delay);
            app.DeltaMode.armDeltaMode();

            app.logMessage(sprintf('Setting static temperature to %.2f K (Rate: %.1f K/min, Mode: %s)...', staticTemp, tempRate, tempApproach));
            app.PPMS.setTemperature(staticTemp, tempRate, tempApproach);
            while app.IsRunning
                if app.PPMS.waitConditionReached(true, false, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end
            app.logMessage(sprintf('Temperature stabilized at %.2f K.', staticTemp));

            app.logMessage(sprintf('Setting static angle to %.2f deg...', staticAngle));
            app.PPMS.setRotatorAngle(staticAngle, 5.0);
            loggedMoveStatus = false;
            while app.IsRunning
                [currentAngle, moveStatus, ~] = app.PPMS.getMovePosition();
                if ~loggedMoveStatus && ~isnan(moveStatus)
                    app.logMessage(sprintf('Rotator MOVE? status code observed: %g.', moveStatus));
                    loggedMoveStatus = true;
                end

                stoppedByStatus = ~isnan(moveStatus) && moveStatus == 1;
                stoppedByTolerance = ~isnan(currentAngle) && abs(currentAngle - staticAngle) < 1.0;
                if stoppedByStatus || stoppedByTolerance
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end
            app.logMessage(sprintf('Angle stabilized at %.2f deg.', staticAngle));

            % With "start from zero", the initial ramp goes to 0 Oe and the
            % 0 -> StartField approach is measured as Repetition 0.
            if fromZero
                initialField = 0;
            else
                initialField = p.StartField;
            end

            app.logMessage(sprintf('Ramping to initial field (%.1f Oe)...', initialField));
            app.PPMS.setMagneticField(initialField, 100.0, 'Linear', 'Driven');
            pause(10);
            while app.IsRunning
                if app.PPMS.waitConditionReached(false, true, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            totalReps = def.Repeat.Repetitions;
            backForth = def.Repeat.BackAndForth;
            turnaroundSettleSec = 60;

            app.logMessage(sprintf('Settling at initial field (%.1f Oe) for %d seconds...', initialField, turnaroundSettleSec));
            pause(turnaroundSettleSec);
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            expStartTimer = tic;
            segmentIndex = 0;

            if fromZero
                if p.StartField == 0
                    app.logMessage('Start field is 0 Oe; skipping the from-zero leg.');
                else
                    app.runFieldSweepLeg(fileID, dataLines, def, p.StartField, p.Rate, p.Interval, ...
                        'Rep 0 (from zero)', 0, expStartTimer);
                    app.logMessage(sprintf('Settling at start field (%.1f Oe) for %d seconds before Rep 1/%d...', p.StartField, turnaroundSettleSec, totalReps));
                    pause(turnaroundSettleSec);
                    if ~app.IsRunning
                        throw(MException('App:UserStop', 'Stopped by user.'));
                    end
                end
            end

            for rep = 1:totalReps
                if ~app.IsRunning; break; end

                if rep > 1
                    app.logMessage(sprintf('Settling at start field (%.1f Oe) for %d seconds before Rep %d/%d...', p.StartField, turnaroundSettleSec, rep, totalReps));
                    pause(turnaroundSettleSec);
                    if ~app.IsRunning; break; end
                end

                segmentIndex = segmentIndex + 1;
                legLabel = sprintf('Rep %d/%d (forward)', rep, totalReps);
                app.runFieldSweepLeg(fileID, dataLines, def, p.EndField, p.Rate, p.Interval, legLabel, segmentIndex, expStartTimer);

                if backForth
                    if ~app.IsRunning; break; end
                    app.logMessage(sprintf('Settling at peak field (%.1f Oe) for %d seconds...', p.EndField, turnaroundSettleSec));
                    pause(turnaroundSettleSec);

                    if ~app.IsRunning; break; end

                    segmentIndex = segmentIndex + 1;
                    legLabel = sprintf('Rep %d/%d (reverse)', rep, totalReps);
                    app.runFieldSweepLeg(fileID, dataLines, def, p.StartField, p.Rate, p.Interval, legLabel, segmentIndex, expStartTimer);
                end
            end

            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            backForthNote = '';
            if backForth; backForthNote = ' back-and-forth'; end
            if fromZero; backForthNote = [backForthNote, ', from zero']; end

            app.logMessage(sprintf('Field sweep "%s" complete (%d repetition(s)%s). Data saved to %s', ...
                def.Name, totalReps, backForthNote, dataFile));
        end

        function runFieldSweepLeg(app, fileID, dataLines, def, targetField, rate, interval, legLabel, repIndex, expStartTimer)
            numChannels = length(def.ChannelSets);

            app.logMessage(sprintf('%s: sweeping to %.1f Oe...', legLabel, targetField));
            app.PPMS.setMagneticField(targetField, rate, 'Linear', 'Driven');

            overrunCount = 0;
            worstOverrun = 0;

            while app.IsRunning
                loopTimer = tic;
                stepFields = NaN(1, numChannels);
                stepValues = NaN(1, numChannels);

                for c = 1:numChannels
                    if ~app.IsRunning; break; end

                    thisChannel = def.ChannelSets{c};

                    app.Switcher.closeChannels(thisChannel);
                    pause(0.2);
                    app.LastClosedChannel = thisChannel;

                    [chanField, ~] = app.PPMS.getCurrentField();

                    measV = NaN;
                    for attempt = 1:4
                        try
                            measV = app.DeltaMode.runDeltaMeasurement();
                            if isfinite(measV)
                                break;
                            end
                        catch ME_Read
                            if attempt == 4; rethrow(ME_Read); end
                            pause(0.2);
                        end
                    end

                    stepFields(c) = chanField;
                    stepValues(c) = measV;
                    if isfinite(measV)
                        addpoints(dataLines{c}, chanField, measV);
                    end
                    drawnow limitrate;
                end

                if app.IsRunning
                    elapsedSeconds = toc(expStartTimer);
                    rowParts = cell(1, 2 + numChannels * 2);
                    rowParts{1} = sprintf('%.2f', elapsedSeconds);
                    rowParts{2} = sprintf('%d', repIndex);

                    for c = 1:numChannels
                        rowParts{2 + 2*c - 1} = sprintf('%f', stepFields(c));
                        rowParts{2 + 2*c}     = sprintf('%e', stepValues(c));
                    end
                    fprintf(fileID, '%s\n', strjoin(rowParts, ','));
                end

                if app.PPMS.waitConditionReached(false, true, false, false)
                    break;
                end

                timeTaken = toc(loopTimer);
                remainingWait = interval - timeTaken;
                if remainingWait > 0
                    pause(remainingWait);
                else
                    overrunCount = overrunCount + 1;
                    worstOverrun = max(worstOverrun, -remainingWait);
                    drawnow;
                end
            end

            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            if overrunCount > 0
                app.logMessage(sprintf(['%s: %d interval(s) ran over the %.1fs budget ', ...
                    '(worst overrun: %.1fs). Measurement is taking longer than the configured interval.'], ...
                    legLabel, overrunCount, interval, worstOverrun));
            end

            app.logMessage(sprintf('%s complete.', legLabel));
        end

        %% --- Experiment Execution: Angle Sweep ---
        function runAngleSweepExperiment(app, def)
            if isempty(app.PPMS) || isempty(app.DeltaMode) || isempty(app.Switcher)
                error('Hardware is not connected.');
            end
        
            numChannels = length(def.ChannelSets);
            if numChannels == 0
                error('Experiment "%s" has no channel sets configured.', def.Name);
            end
        
            app.LastClosedChannel = [];
        
            dataFile = app.resolveExperimentDataFile(def);
            fileID = fopen(dataFile, 'w');
            if fileID < 0
                error('Could not open data file: %s', dataFile);
            end
            fileCleanup = onCleanup(@() app.safeCloseFile(fileID));
            hwCleanup = onCleanup(@() app.safeStopMeasurement());
        
            p = def.Params;
        
            if isfield(def, 'Static') && isfield(def.Static, 'Temperature') && ~isempty(def.Static.Temperature)
                staticTemp = def.Static.Temperature;
            elseif isfield(p, 'Temperature') && ~isempty(p.Temperature)
                staticTemp = p.Temperature;
            else
                staticTemp = 300;
            end

            tempRate = 10.0;
            tempApproach = 'FastSettle';
            if isfield(def.Static, 'TempRate') && ~isempty(def.Static.TempRate)
                tempRate = def.Static.TempRate;
            end
            if isfield(def.Static, 'TempApproach') && ~isempty(def.Static.TempApproach)
                tempApproach = def.Static.TempApproach;
            end

            if isfield(def, 'Static') && isfield(def.Static, 'Field') && ~isempty(def.Static.Field)
                staticField = def.Static.Field;
            elseif isfield(p, 'Field') && ~isempty(p.Field)
                staticField = p.Field;
            else
                staticField = 0;
            end
        
            if isfield(p, 'StartAngle'); startAngle = p.StartAngle;
            elseif isfield(p, 'StartPosition'); startAngle = p.StartPosition;
            else; startAngle = 0; end
        
            if isfield(p, 'EndAngle'); endAngle = p.EndAngle;
            elseif isfield(p, 'EndPosition'); endAngle = p.EndPosition;
            else; endAngle = 360; end
        
            if isfield(p, 'Speed'); sweepRate = p.Speed;
            elseif isfield(p, 'Rate'); sweepRate = p.Rate;
            else; sweepRate = 2.0; end
        
            if isfield(p, 'StepAngle') && ~isempty(p.StepAngle) && p.StepAngle > 0
                stepAngle = p.StepAngle;
            elseif isfield(p, 'Step') && ~isempty(p.Step) && p.Step > 0
                stepAngle = p.Step;
            elseif isfield(p, 'Interval') && ~isempty(p.Interval)
                stepAngle = max(0.5, sweepRate * p.Interval);
            else
                stepAngle = 1.0;
            end
        
            if startAngle <= endAngle
                angleList = startAngle : abs(stepAngle) : endAngle;
                if angleList(end) < endAngle; angleList(end+1) = endAngle; end
            else
                angleList = startAngle : -abs(stepAngle) : endAngle;
                if angleList(end) > endAngle; angleList(end+1) = endAngle; end
            end
        
            if isfield(def, 'Delta')
                posI    = def.Delta.PosI;
                negI    = def.Delta.NegI;
                repeats = def.Delta.Repeats;
                delay   = def.Delta.Delay;
                vRange  = def.Delta.Range;
            else
                posI    = 10e-6;
                negI    = -10e-6;
                repeats = 3;
                delay   = 0.1;
                vRange  = 'Auto';
            end
        
            fprintf(fileID, '%% Experiment: %s\n', def.Name);
            fprintf(fileID, '%% Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Delta Current (+I): %e A | (-I): %e A\n', posI, negI);
            fprintf(fileID, '%% Delta Repeats: %d | Delay: %f s | Range: %s\n', repeats, delay, vRange);
            fprintf(fileID, '%% Static Temperature: %f K (Rate: %f K/min, Approach: %s) | Static Field: %f Oe\n', staticTemp, tempRate, tempApproach, staticField);
            fprintf(fileID, '%% Rotator Sweep: %f deg to %f deg (Step: %f deg, Speed: %f deg/sec)\n', startAngle, endAngle, stepAngle, sweepRate);
        
            headerParts = {'Time_s', 'Repetition', 'Angle_deg'};
            for c = 1:numChannels
                vec = def.ChannelSets{c};
                chanLabel = sprintf('%d_%d_%d_%d', vec(1), vec(2), vec(3), vec(4));
                headerParts{end+1} = sprintf('V_Delta_%s', chanLabel); %#ok<AGROW>
            end
            fprintf(fileID, '%s\n', strjoin(headerParts, ','));
        
            cla(app.PlotAxes);
            title(app.PlotAxes, sprintf('%s - Delta Voltage vs. Rotator Angle', def.Name));
            xlabel(app.PlotAxes, 'Angle (deg)');
            ylabel(app.PlotAxes, 'Delta Voltage (V)');
            grid(app.PlotAxes, 'on');
            dataLines = cell(1, numChannels);
            colors = lines(numChannels);
            for c = 1:numChannels
                dataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            if isfield(def, 'ChannelItems') && ~isempty(def.ChannelItems)
                legend(app.PlotAxes, def.ChannelItems, 'Location', 'best');
            end
        
            try
                app.DeltaMode.disarmDeltaMode();
                pause(0.2);
            catch
            end
        
            if ismethod(app.DeltaMode, 'setVoltageRange')
                app.DeltaMode.setVoltageRange(vRange);
            end
        
            app.DeltaMode.setupDeltaMode(posI, negI, repeats, 'oneshot', delay);
            app.DeltaMode.armDeltaMode();
        
            app.logMessage(sprintf('Setting static temperature to %.2f K (Rate: %.1f K/min, Mode: %s)...', staticTemp, tempRate, tempApproach));
            app.PPMS.setTemperature(staticTemp, tempRate, tempApproach);
            while app.IsRunning
                if app.PPMS.waitConditionReached(true, false, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end
            app.logMessage(sprintf('Temperature stabilized at %.2f K.', staticTemp));
        
            app.logMessage(sprintf('Setting static magnetic field to %.1f Oe...', staticField));
            app.PPMS.setMagneticField(staticField, 100.0, 'Linear', 'Driven');
            pause(5);
            while app.IsRunning
                if app.PPMS.waitConditionReached(false, true, false, false)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end
            app.logMessage(sprintf('Magnetic field stabilized at %.1f Oe.', staticField));
        
            expStartTimer = tic;
            totalReps = 1;
            if isfield(def, 'Repeat') && isfield(def.Repeat, 'Repetitions')
                totalReps = def.Repeat.Repetitions;
            end

            for rep = 1:totalReps
                if ~app.IsRunning; break; end
                app.logMessage(sprintf('Starting angle sweep rep %d/%d (%.1f deg to %.1f deg)...', rep, totalReps, startAngle, endAngle));

                for idx = 1:numel(angleList)
                    if ~app.IsRunning; break; end

                    targetAngle = angleList(idx);
                    app.logMessage(sprintf('Step %d/%d: Moving rotator to %.2f deg...', idx, numel(angleList), targetAngle));
                    app.PPMS.setRotatorAngle(targetAngle, sweepRate);

                    while app.IsRunning
                        [currentAngle, moveStatus, ~] = app.PPMS.getMovePosition();
                        stoppedByStatus = ~isnan(moveStatus) && moveStatus == 1;
                        stoppedByTolerance = ~isnan(currentAngle) && abs(currentAngle - targetAngle) < 0.5;
                        if stoppedByStatus || stoppedByTolerance
                            break;
                        end
                        pause(0.5);
                    end
                    if ~app.IsRunning; break; end

                    [actualAngle, ~, ~] = app.PPMS.getMovePosition();
                    if isnan(actualAngle); actualAngle = targetAngle; end

                    stepValues = NaN(1, numChannels);

                    for c = 1:numChannels
                        if ~app.IsRunning; break; end

                        thisChannel = def.ChannelSets{c};
                        app.Switcher.closeChannels(thisChannel);
                        pause(0.2);
                        app.LastClosedChannel = thisChannel;

                        measV = NaN;
                        for attempt = 1:4
                            try
                                measV = app.DeltaMode.runDeltaMeasurement();
                                if isfinite(measV); break; end
                            catch ME_Read
                                if attempt == 4; rethrow(ME_Read); end
                                pause(0.2);
                            end
                        end

                        stepValues(c) = measV;
                        if isfinite(measV)
                            addpoints(dataLines{c}, actualAngle, measV);
                        end
                        drawnow limitrate;
                    end

                    if app.IsRunning
                        elapsedSeconds = toc(expStartTimer);
                        rowParts = cell(1, 3 + numChannels);
                        rowParts{1} = sprintf('%.2f', elapsedSeconds);
                        rowParts{2} = sprintf('%d', rep);
                        rowParts{3} = sprintf('%f', actualAngle);
                        for c = 1:numChannels
                            rowParts{c + 3} = sprintf('%e', stepValues(c));
                        end
                        fprintf(fileID, '%s\n', strjoin(rowParts, ','));
                    end
                end
            end
        
            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end
        
            app.logMessage(sprintf('Angle sweep "%s" complete. Data saved to %s', def.Name, dataFile));
        end

        %% --- Experiment Execution: Current Sweep (DC I-V) ---
        function runCurrentSweepExperiment(app, def)
            if isempty(app.PPMS) || isempty(app.DeltaMode) || isempty(app.Switcher)
                error('Hardware is not connected.');
            end

            numChannels = length(def.ChannelSets);
            if numChannels == 0
                error('Experiment "%s" has no channel sets configured.', def.Name);
            end

            app.LastClosedChannel = [];

            dataFile = app.resolveExperimentDataFile(def);
            fileID = fopen(dataFile, 'w');
            if fileID < 0
                error('Could not open data file: %s', dataFile);
            end

            fileCleanup = onCleanup(@() app.safeCloseFile(fileID));
            hwCleanup   = onCleanup(@() app.safeStopCurrentSweep());

            p = def.Params;
            staticTemp  = def.Static.Temperature;
            staticField = def.Static.Field;
            staticAngle = def.Static.Angle;

            tempRate = 10.0;
            tempApproach = 'FastSettle';
            if isfield(def.Static, 'TempRate') && ~isempty(def.Static.TempRate)
                tempRate = def.Static.TempRate;
            end
            if isfield(def.Static, 'TempApproach') && ~isempty(def.Static.TempApproach)
                tempApproach = def.Static.TempApproach;
            end

            complianceVolts = 10.0;
            if isfield(p, 'Compliance') && ~isempty(p.Compliance)
                complianceVolts = p.Compliance;
            end

            fprintf(fileID, '%% Experiment: %s\n', def.Name);
            fprintf(fileID, '%% Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fileID, '%% Sweep Current: %e A to %e A (%d steps, delay: %f s, compliance: %f V)\n', ...
                p.StartCurrent, p.EndCurrent, p.Steps, p.Delay, complianceVolts);
            fprintf(fileID, '%% Static Temperature: %f K (Rate: %f K/min, Approach: %s)\n', staticTemp, tempRate, tempApproach);
            fprintf(fileID, '%% Static Magnetic Field: %f Oe\n', staticField);
            fprintf(fileID, '%% Static Angle: %f deg\n', staticAngle);
            fprintf(fileID, '%% Repetitions: %d | Back-and-forth: %d\n', def.Repeat.Repetitions, def.Repeat.BackAndForth);

            % Header setup matching parallel channel columns
            headerParts = {'Time_s', 'Repetition', 'I_Applied_A'};
            for c = 1:numChannels
                vec = def.ChannelSets{c};
                chanLabel = sprintf('%d_%d_%d_%d', vec(1), vec(2), vec(3), vec(4));
                headerParts{end+1} = sprintf('V_Meas_%s', chanLabel); %#ok<AGROW>
            end
            fprintf(fileID, '%s\n', strjoin(headerParts, ','));

            cla(app.PlotAxes);
            title(app.PlotAxes, sprintf('%s - I-V Curve (T=%.1fK, H=%.1fOe, \\theta=%.1f\\circ)', ...
                def.Name, staticTemp, staticField, staticAngle));
            xlabel(app.PlotAxes, 'Applied Current (A)');
            ylabel(app.PlotAxes, 'Measured Voltage (V)');
            grid(app.PlotAxes, 'on');
            dataLines = cell(1, numChannels);
            colors = lines(numChannels);
            for c = 1:numChannels
                dataLines{c} = animatedline(app.PlotAxes, 'Color', colors(c,:), 'LineWidth', 1.5, 'Marker', '.');
            end
            if isfield(def, 'ChannelItems') && ~isempty(def.ChannelItems)
                legend(app.PlotAxes, def.ChannelItems, 'Location', 'best');
            end

            app.logMessage(sprintf('Setting temperature to %.2f K...', staticTemp));
            app.PPMS.setTemperature(staticTemp, tempRate, tempApproach);
            while app.IsRunning
                if app.PPMS.waitConditionReached(true, false, false, false); break; end
                pause(1);
            end
            if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end

            app.logMessage(sprintf('Setting magnetic field to %.1f Oe...', staticField));
            app.PPMS.setMagneticField(staticField, 100.0, 'Linear', 'Driven');
            pause(2);
            while app.IsRunning
                if app.PPMS.waitConditionReached(false, true, false, false); break; end
                pause(1);
            end
            if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end

            app.logMessage(sprintf('Setting rotator angle to %.2f deg...', staticAngle));
            app.PPMS.setRotatorAngle(staticAngle, 5.0);
            while app.IsRunning
                [currentAngle, moveStatus, ~] = app.PPMS.getMovePosition();
                if (~isnan(moveStatus) && moveStatus == 1) || (~isnan(currentAngle) && abs(currentAngle - staticAngle) < 0.5)
                    break;
                end
                pause(1);
            end
            if ~app.IsRunning; throw(MException('App:UserStop', 'Stopped by user.')); end
            app.logMessage('Environment set (Temperature, Field, Angle stabilized).');

            %% --- Prep Keithley 6221 for DC Current Sweep ---
            try
                % Disarm Delta Mode if previously active from Field/Angle sweeps
                app.DeltaMode.disarmDeltaMode();
                pause(0.2);
            catch
            end

            % Clear GPIB error queue (*CLS) and set compliance
            if ismethod(app.DeltaMode, 'clearErrorQueue')
                app.DeltaMode.clearErrorQueue();
            end
            app.DeltaMode.setCompliance(complianceVolts);

            currentArray = linspace(p.StartCurrent, p.EndCurrent, p.Steps);
            totalReps = def.Repeat.Repetitions;
            backForth = def.Repeat.BackAndForth;
            expStartTimer = tic;

            for rep = 1:totalReps
                if ~app.IsRunning; break; end

                app.runSingleCurrentSweepPass(fileID, dataLines, def, currentArray, rep, expStartTimer);

                if backForth && app.IsRunning
                    app.runSingleCurrentSweepPass(fileID, dataLines, def, fliplr(currentArray), rep, expStartTimer);
                end
            end

            app.safeZeroAndDisableCurrent();

            if ~app.IsRunning
                throw(MException('App:UserStop', 'Stopped by user.'));
            end

            app.logMessage(sprintf('Current sweep "%s" complete. Data saved to %s', def.Name, dataFile));
        end

        function runSingleCurrentSweepPass(app, fileID, dataLines, def, currentArray, repIdx, expStartTimer)
            numChannels = length(def.ChannelSets);
            p = def.Params;

            restTime = 0;
            if isfield(p, 'RestTime') && ~isempty(p.RestTime)
                restTime = p.RestTime;
            end

            app.DeltaMode.setOutput('ON');
            passCleanup = onCleanup(@() app.safeZeroAndDisableCurrent()); %#ok<NASGU>

            % Step current array on outer loop for parallel channel measurement
            for i = 1:length(currentArray)
                if ~app.IsRunning; break; end

                iApply = currentArray(i);

                % Set applied current and wait stabilization delay
                app.DeltaMode.setCurrent(iApply);
                pause(p.Delay);

                stepValues = NaN(1, numChannels);

                % Cycle through channel sets in parallel for current step i
                for c = 1:numChannels
                    if ~app.IsRunning; break; end

                    thisChannel = def.ChannelSets{c};
                    app.Switcher.closeChannels(thisChannel);
                    pause(0.1); % Debounce / settling delay for switch relay
                    app.LastClosedChannel = thisChannel;

                    measV = app.DeltaMode.getReading();
                    stepValues(c) = measV;

                    if isfinite(measV)
                        addpoints(dataLines{c}, iApply, measV);
                    end
                    drawnow limitrate;
                end

                if restTime > 0
                    app.DeltaMode.setCurrent(0);
                    pause(restTime);
                end

                % Write a single row formatted identically across all channels
                if app.IsRunning
                    elapsedSeconds = toc(expStartTimer);
                    rowParts = cell(1, 3 + numChannels);
                    rowParts{1} = sprintf('%.2f', elapsedSeconds);
                    rowParts{2} = sprintf('%d', repIdx);
                    rowParts{3} = sprintf('%e', iApply);

                    for c = 1:numChannels
                        rowParts{c + 3} = sprintf('%e', stepValues(c));
                    end
                    fprintf(fileID, '%s\n', strjoin(rowParts, ','));
                end
            end
        end

        function safeZeroAndDisableCurrent(app)
            try
                if ~isempty(app.DeltaMode)
                    app.DeltaMode.setCurrent(0.0);
                    app.DeltaMode.setOutput('OFF');
                end
            catch; end
        end

        function safeCloseFile(~, fileID)
            try fclose(fileID); catch; end
        end

        function safeStopMeasurement(app)
            try app.DeltaMode.disarmDeltaMode(); catch; end
            try app.Switcher.openAllChannels(); catch; end
        end

        function safeStopCurrentSweep(app)
            app.safeZeroAndDisableCurrent();
            try
                if ~isempty(app.Switcher)
                    app.Switcher.openAllChannels();
                end
            catch; end
        end

        function safeFile = resolveUniqueDataFilename(~, baseFile)
            [filepath, name, ext] = fileparts(baseFile);
            safeFile = baseFile;
            counter = 1;
            while isfile(safeFile)
                safeFile = fullfile(filepath, sprintf('%s_%d%s', name, counter, ext));
                counter = counter + 1;
            end
        end

        function dataFile = resolveExperimentDataFile(app, def)
            baseFolder = strtrim(app.OutputFolderEdit.Value);
            safeName = regexprep(def.Name, '[^\w\- ]', '');
            if isempty(safeName); safeName = 'Experiment'; end

            expFolder = fullfile(baseFolder, safeName);
            if ~isfolder(expFolder)
                mkdir(expFolder);
            end

            dataFile = app.resolveUniqueDataFilename(fullfile(expFolder, [safeName '.csv']));
        end

        function performShutdown(app)
            app.logMessage('Beginning shutdown sequence...');
            try
                try app.DeltaMode.disarmDeltaMode(); catch; end
                app.logMessage('Keithley 6221/2182A Delta Mode disarmed.');

                app.PPMS.setMagneticField(0.0, 100.0, 'Linear', 'Driven');
                while true
                    if app.PPMS.waitConditionReached(false, true, false, false); break; end
                    pause(1);
                end
                app.logMessage('Magnetic field ramped to 0 Oe.');

                app.logMessage('Setting magnet to persistent mode...');
                app.PPMS.setMagneticField(0.0, 100.0, 'Linear', 'Persistent');
                while true
                    if app.PPMS.waitConditionReached(false, true, false, false); break; end
                    pause(1);
                end
                app.logMessage('Magnet successfully placed in persistent mode.');

                try
                    app.PPMS.shutdownTemperatureController();
                    app.logMessage('Temperature controller placed in standby.');
                catch ME_Temp
                    app.logMessage(sprintf('Could not set temperature standby: %s', ME_Temp.message));
                end

                app.disconnectHardware();
                app.logMessage('Shutdown complete - hardware disconnected.');
                app.sendNotification('PPMS: Shutdown Complete', 'The post-queue shutdown sequence has finished; hardware disconnected.');
            catch ME
                app.logMessage(sprintf('Shutdown error: %s', ME.message));
                app.sendNotification('PPMS: CRITICAL ERROR! Shutdown Failed', ...
                    sprintf('The shutdown sequence encountered an error and may not have completed safely: %s\n\nCheck the PPMS, Delta Mode, and switcher state manually as soon as possible.', ME.message));
            end
        end

        function logMessage(app, msg)
            timestamp = datestr(now, 'HH:MM:SS');
            line = sprintf('[%s] %s', timestamp, msg);
            app.LogTextArea.Value = [app.LogTextArea.Value; {line}];
            scroll(app.LogTextArea, 'bottom');
        end

        function sendNotification(app, subject, content)
            recipient = strtrim(app.EmailEdit.Value);
            if isempty(recipient); return; end
            if isempty(app.GmailLogin) || isempty(app.GmailPassword); return; end

            timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            body = sprintf('[%s]\n\n%s', timestamp, content);

            try
                SendGmail(app.GmailLogin, app.GmailPassword, recipient, subject, body);
                app.logMessage(sprintf('Email sent to %s: %s', recipient, subject));
            catch ME
                app.logMessage(sprintf('Failed to send email: %s', ME.message));
                app.GmailLogin = '';
                app.GmailPassword = '';
            end
        end

        function ok = ensureGmailCredentials(app)
            if ~isempty(app.GmailLogin) && ~isempty(app.GmailPassword)
                ok = true;
                return;
            end

            answer = inputdlg({'Sending Gmail address:', 'Gmail App Password:'}, ...
                'Email Notification Credentials', [1 50; 1 50]);
            if isempty(answer) || isempty(strtrim(answer{1})) || isempty(answer{2})
                ok = false;
                return;
            end

            app.GmailLogin = strtrim(answer{1});
            app.GmailPassword = answer{2};
            ok = true;

            choice = uiconfirm(app.UIFigure, ...
                'Remember this login securely on this PC for future sessions?', ...
                'Save Credentials', 'Options', {'Yes', 'No'}, 'DefaultOption', 2, 'CancelOption', 2);
            if strcmp(choice, 'Yes')
                app.saveGmailCredentials();
            end
        end

        function filePath = gmailCredentialFile(~)
            folder = fullfile(getenv('LOCALAPPDATA'), 'PPMSTamarController');
            if ~isfolder(folder); mkdir(folder); end
            filePath = fullfile(folder, 'gmail_credentials.dat');
        end

        function entropy = gmailCredentialEntropy(~)
            entropy = uint8(System.Text.Encoding.UTF8.GetBytes('PPMSTamarController.GmailCred.v1'));
        end

        function saveGmailCredentials(app)
            try
                NET.addAssembly('System.Security');
                plainText = sprintf('%s\n%s', app.GmailLogin, app.GmailPassword);
                plainBytes = uint8(System.Text.Encoding.UTF8.GetBytes(plainText));
                entropy = app.gmailCredentialEntropy();
                scope = System.Security.Cryptography.DataProtectionScope.CurrentUser;
                encrypted = System.Security.Cryptography.ProtectedData.Protect(plainBytes, entropy, scope);

                fid = fopen(app.gmailCredentialFile(), 'w');
                fwrite(fid, uint8(encrypted), 'uint8');
                fclose(fid);
                app.logMessage('Gmail credentials saved (encrypted, this PC/user only).');
            catch ME
                app.logMessage(sprintf('Could not save Gmail credentials: %s', ME.message));
            end
        end

        function loadGmailCredentials(app)
            filePath = app.gmailCredentialFile();
            if ~isfile(filePath); return; end

            try
                NET.addAssembly('System.Security');
                fid = fopen(filePath, 'r');
                encrypted = fread(fid, Inf, 'uint8=>uint8')';
                fclose(fid);

                entropy = app.gmailCredentialEntropy();
                scope = System.Security.Cryptography.DataProtectionScope.CurrentUser;
                decrypted = System.Security.Cryptography.ProtectedData.Unprotect(encrypted, entropy, scope);
                plainText = char(System.Text.Encoding.UTF8.GetString(decrypted));

                parts = strsplit(plainText, newline, 'CollapseDelimiters', false);
                if numel(parts) >= 2
                    app.GmailLogin = parts{1};
                    app.GmailPassword = parts{2};
                    app.logMessage('Loaded saved Gmail credentials for this PC/user.');
                end
            catch ME
                app.logMessage(sprintf('Could not load saved Gmail credentials: %s', ME.message));
            end
        end

        function forgetGmailCredentials(app)
            app.GmailLogin = '';
            app.GmailPassword = '';
            filePath = app.gmailCredentialFile();
            if isfile(filePath)
                try delete(filePath);
                catch ME
                    app.logMessage(sprintf('Could not delete saved credentials file: %s', ME.message));
                    return;
                end
            end
            app.logMessage('Saved Gmail credentials forgotten.');
        end

        function startHeliumWatchdog(app)
            app.stopHeliumWatchdog();
            app.HeliumTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 60, ...
                'TimerFcn', @(~,~) app.checkHeliumLevel());
            start(app.HeliumTimer);
            app.logMessage(sprintf('Helium watchdog started (threshold %.1f%%).', app.HeliumThresholdEdit.Value));
        end

        function stopHeliumWatchdog(app)
            if ~isempty(app.HeliumTimer) && isvalid(app.HeliumTimer)
                stop(app.HeliumTimer);
                delete(app.HeliumTimer);
            end
            app.HeliumTimer = [];
        end

        function checkHeliumLevel(app)
            if isempty(app.PPMS); return; end

            try
                app.PPMS.setHeliumLevelMeter(0);
                pause(10);
                [level, ~] = app.PPMS.getHeliumLevel();
            catch ME
                app.logMessage(sprintf('Helium level check failed: %s', ME.message));
                return;
            end

            if isnan(level); return; end

            threshold = app.HeliumThresholdEdit.Value;
            app.logMessage(sprintf('Helium level: %.1f%% (threshold %.1f%%)', level, threshold));

            if level < threshold
                app.logMessage(sprintf('CRITICAL: Helium level %.1f%% below threshold %.1f%% - forcing shutdown.', level, threshold));
                app.sendNotification('PPMS: EMERGENCY - Low Helium Level', ...
                    sprintf('Helium level dropped to %.1f%% (threshold %.1f%%). Forcing an emergency shutdown.', level, threshold));
                app.IsRunning = false;
                app.performShutdown();
            end
        end

        function onAppClose(app)
            app.stopHeliumWatchdog();
            app.disconnectHardware();
            delete(app.UIFigure);
        end
    end
end
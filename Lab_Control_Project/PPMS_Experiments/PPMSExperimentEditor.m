classdef PPMSExperimentEditor < handle
    % PPMSExperimentEditor - Modal editor for a single queued experiment.
    % Opened by PPMSTamarController ("New Experiment..." / double-click to
    % edit). Blocks the caller (uiwait) until Save or Cancel, then returns
    % the experiment definition struct (or [] if cancelled).
    %
    % Every experiment type has two parameter groups: a "Sweep" panel for
    % the quantity being swept, and a shared "Static Environment" panel
    % for the quantities being held constant (Field / Temperature / Angle).
    % The static excitation current lives in the shared M81 Lock-In panel
    % (not applicable to Current Sweep, which sweeps current itself).
    %
    % Usage:
    %   def = PPMSExperimentEditor.run();            % create new
    %   def = PPMSExperimentEditor.run(existingDef);  % edit existing

    properties (Access = private)
        UIFigure
        Result = []
        ExistingFilePath = ''

        % Name / Type
        NameEdit
        TypeDrop

        % Type-specific sweep panels (toggled by TypeDrop)
        AnglePanel
        AS_StartAngle, AS_EndAngle, AS_Speed, AS_Interval

        FieldSweepPanel
        FS_StartField, FS_EndField, FS_Rate, FS_Interval

        CurrentSweepPanel
        CS_StartCurrent, CS_EndCurrent, CS_Steps, CS_Delay

        TempSweepPanel
        TS_StartTemp, TS_EndTemp, TS_Rate, TS_Interval

        % Shared "held constant" environment panel
        StaticPanel
        SE_FieldLabel, SE_Field
        SE_TempLabel, SE_Temp
        SE_AngleLabel, SE_Angle

        % Shared repeat/back-and-forth panel
        RepeatPanel
        BackForthCheckbox, RepetitionsEdit

        % Shared AC Lock-In panel (not used by Current Sweep - DC measurement)
        LockInPanel
        AC_Current, AC_Freq, AC_TC

        % Channel sets (shared by all types)
        ChannelSets = {}
        ChanPosI, ChanNegI, ChanPosV, ChanNegV
        ChannelListBox

        SaveBtn, CancelBtn
    end

    methods (Static)
        function def = run(existingDef)
            if nargin < 1
                existingDef = [];
            end
            editor = PPMSExperimentEditor(existingDef);
            uiwait(editor.UIFigure);
            def = editor.Result;
            if isvalid(editor.UIFigure)
                delete(editor.UIFigure);
            end
        end
    end

    methods (Access = private)
        function app = PPMSExperimentEditor(existingDef)
            app.UIFigure = uifigure('Name', 'Experiment Editor', 'Position', [200, 80, 520, 700], ...
                'WindowStyle', 'modal', 'CloseRequestFcn', @(s,e) app.onCancel());
            movegui(app.UIFigure, 'center');

            layout = uigridlayout(app.UIFigure, [8, 1], ...
                'RowHeight', {'fit', 'fit', 190, 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Scrollable', 'on');

            app.createNamePanel(layout);
            app.createTypePanel(layout);
            app.createSweepPanels(layout);
            app.createStaticPanel(layout);
            app.createRepeatPanel(layout);
            app.createLockInPanel(layout);
            app.createChannelPanel(layout);
            app.createButtonRow(layout);

            if ~isempty(existingDef)
                app.populateFrom(existingDef);
            else
                app.onTypeChanged();
            end
        end

        %% --- UI Builders ---
        function createNamePanel(app, parent)
            g = uigridlayout(parent, [1, 2], 'ColumnWidth', {'fit', '1x'});
            uilabel(g, 'Text', 'Experiment Name:');
            app.NameEdit = uieditfield(g, 'text', 'Value', 'New Experiment');
        end

        function createTypePanel(app, parent)
            g = uigridlayout(parent, [1, 2], 'ColumnWidth', {'fit', '1x'});
            uilabel(g, 'Text', 'Experiment Type:');
            app.TypeDrop = uidropdown(g, ...
                'Items', {'Angle Sweep', 'Field Sweep', 'Current Sweep', 'Temperature Sweep'}, ...
                'ItemsData', {'AngleSweep', 'FieldSweep', 'CurrentSweep', 'TemperatureSweep'}, ...
                'Value', 'AngleSweep', 'ValueChangedFcn', @(s,e) app.onTypeChanged());
        end

        function createSweepPanels(app, parent)
            container = uipanel(parent, 'Title', 'Sweep Parameters');
            containerLayout = uigridlayout(container, [1, 1]);
            containerLayout.Padding = [0 0 0 0];

            % Each type gets its own panel stacked in the same cell; only
            % the active one is made Visible in onTypeChanged().
            app.AnglePanel = uipanel(containerLayout, 'Title', 'Angle Sweep');
            g = uigridlayout(app.AnglePanel, [4, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Angle (deg):'); app.AS_StartAngle = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End Angle (deg):');   app.AS_EndAngle = uieditfield(g, 'numeric', 'Value', 360.0);
            uilabel(g, 'Text', 'Speed (deg/sec):');   app.AS_Speed = uieditfield(g, 'numeric', 'Value', 1.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.AS_Interval = uieditfield(g, 'numeric', 'Value', 1.0);
            app.AnglePanel.Layout.Row = 1; app.AnglePanel.Layout.Column = 1;

            app.FieldSweepPanel = uipanel(containerLayout, 'Title', 'Field Sweep');
            g = uigridlayout(app.FieldSweepPanel, [4, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Field (Oe):'); app.FS_StartField = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End Field (Oe):');   app.FS_EndField = uieditfield(g, 'numeric', 'Value', 10000.0);
            uilabel(g, 'Text', 'Rate (Oe/sec):');    app.FS_Rate = uieditfield(g, 'numeric', 'Value', 50.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.FS_Interval = uieditfield(g, 'numeric', 'Value', 1.0);
            app.FieldSweepPanel.Layout.Row = 1; app.FieldSweepPanel.Layout.Column = 1;

            app.CurrentSweepPanel = uipanel(containerLayout, 'Title', 'Current Sweep (DC I-V)');
            g = uigridlayout(app.CurrentSweepPanel, [4, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Current (A):'); app.CS_StartCurrent = uieditfield(g, 'numeric', 'Value', -10e-6);
            uilabel(g, 'Text', 'End Current (A):');   app.CS_EndCurrent = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Steps:');              app.CS_Steps = uieditfield(g, 'numeric', 'Value', 51);
            uilabel(g, 'Text', 'Delay/Pt (s):');       app.CS_Delay = uieditfield(g, 'numeric', 'Value', 0.2);
            app.CurrentSweepPanel.Layout.Row = 1; app.CurrentSweepPanel.Layout.Column = 1;

            app.TempSweepPanel = uipanel(containerLayout, 'Title', 'Temperature Sweep');
            g = uigridlayout(app.TempSweepPanel, [4, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Temp (K):'); app.TS_StartTemp = uieditfield(g, 'numeric', 'Value', 300.0);
            uilabel(g, 'Text', 'End Temp (K):');   app.TS_EndTemp = uieditfield(g, 'numeric', 'Value', 10.0);
            uilabel(g, 'Text', 'Rate (K/min):');   app.TS_Rate = uieditfield(g, 'numeric', 'Value', 2.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.TS_Interval = uieditfield(g, 'numeric', 'Value', 1.0);
            app.TempSweepPanel.Layout.Row = 1; app.TempSweepPanel.Layout.Column = 1;
        end

        function createStaticPanel(app, parent)
            % Holds whichever of Field / Temperature / Angle are NOT being
            % swept; the row for the swept quantity is hidden per type.
            app.StaticPanel = uipanel(parent, 'Title', 'Static Environment (held constant)');
            g = uigridlayout(app.StaticPanel, [3, 2], 'ColumnWidth', {'1x', 100});

            app.SE_FieldLabel = uilabel(g, 'Text', 'Field (Oe):'); app.SE_Field = uieditfield(g, 'numeric', 'Value', 0.0);
            app.SE_TempLabel = uilabel(g, 'Text', 'Temperature (K):'); app.SE_Temp = uieditfield(g, 'numeric', 'Value', 300.0);
            app.SE_AngleLabel = uilabel(g, 'Text', 'Angle (deg):'); app.SE_Angle = uieditfield(g, 'numeric', 'Value', 0.0);
        end

        function createRepeatPanel(app, parent)
            app.RepeatPanel = uipanel(parent, 'Title', 'Repeat');
            g = uigridlayout(app.RepeatPanel, [1, 3], 'ColumnWidth', {'1x', 'fit', 80});
            app.BackForthCheckbox = uicheckbox(g, 'Text', 'Back and forth (round trip)', 'Value', false, ...
                'ValueChangedFcn', @(s,e) app.onBackForthChanged());
            uilabel(g, 'Text', 'Repetitions:');
            app.RepetitionsEdit = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 Inf], ...
                'RoundFractionalValues', 'on', 'Enable', 'off');
        end

        function onBackForthChanged(app)
            if app.BackForthCheckbox.Value
                app.RepetitionsEdit.Enable = 'on';
            else
                app.RepetitionsEdit.Value = 1;
                app.RepetitionsEdit.Enable = 'off';
            end
        end

        function createLockInPanel(app, parent)
            % Shared AC lock-in settings; not applicable to CurrentSweep (DC).
            app.LockInPanel = uipanel(parent, 'Title', 'M81 Lock-In Settings');
            g = uigridlayout(app.LockInPanel, [3, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'AC Current (A):');    app.AC_Current = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Frequency (Hz):');    app.AC_Freq = uieditfield(g, 'numeric', 'Value', 17.0);
            uilabel(g, 'Text', 'Time Constant (s):'); app.AC_TC = uieditfield(g, 'numeric', 'Value', 0.1);
        end

        function createChannelPanel(app, parent)
            p = uipanel(parent, 'Title', '3706 Switcher Matrix');
            g = uigridlayout(p, [4, 4], 'RowHeight', {'fit', 'fit', 'fit', 80});

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

        function createButtonRow(app, parent)
            g = uigridlayout(parent, [1, 2]);
            app.SaveBtn = uibutton(g, 'Text', 'Save', 'BackgroundColor', [0.2 0.8 0.2], 'FontWeight', 'bold', 'ButtonPushedFcn', @(s,e) app.onSave());
            app.CancelBtn = uibutton(g, 'Text', 'Cancel', 'ButtonPushedFcn', @(s,e) app.onCancel());
        end

        %% --- Type Switching ---
        function onTypeChanged(app)
            app.AnglePanel.Visible = 'off';
            app.FieldSweepPanel.Visible = 'off';
            app.CurrentSweepPanel.Visible = 'off';
            app.TempSweepPanel.Visible = 'off';

            % Static Environment rows: show all three, then hide whichever
            % quantity is the one being swept for this type.
            app.SE_FieldLabel.Visible = 'on'; app.SE_Field.Visible = 'on';
            app.SE_TempLabel.Visible = 'on';  app.SE_Temp.Visible = 'on';
            app.SE_AngleLabel.Visible = 'on'; app.SE_Angle.Visible = 'on';

            switch app.TypeDrop.Value
                case 'AngleSweep'
                    app.AnglePanel.Visible = 'on';
                    app.SE_AngleLabel.Visible = 'off'; app.SE_Angle.Visible = 'off';
                case 'FieldSweep'
                    app.FieldSweepPanel.Visible = 'on';
                    app.SE_FieldLabel.Visible = 'off'; app.SE_Field.Visible = 'off';
                case 'CurrentSweep'
                    app.CurrentSweepPanel.Visible = 'on';
                    % Current itself is swept; Field/Temp/Angle all stay static.
                case 'TemperatureSweep'
                    app.TempSweepPanel.Visible = 'on';
                    app.SE_TempLabel.Visible = 'off'; app.SE_Temp.Visible = 'off';
            end

            % Current Sweep is a DC measurement - the AC lock-in panel doesn't apply.
            if strcmp(app.TypeDrop.Value, 'CurrentSweep')
                app.LockInPanel.Visible = 'off';
            else
                app.LockInPanel.Visible = 'on';
            end
        end

        %% --- Channel Set List ---
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

        %% --- Populate from an existing definition (edit mode) ---
        function populateFrom(app, def)
            app.NameEdit.Value = def.Name;
            app.TypeDrop.Value = def.Type;
            app.ExistingFilePath = def.DefinitionFile;
            app.ChannelSets = def.ChannelSets;
            app.ChannelListBox.Items = def.ChannelItems;

            p = def.Params;
            switch def.Type
                case 'AngleSweep'
                    app.AS_StartAngle.Value = p.StartAngle; app.AS_EndAngle.Value = p.EndAngle;
                    app.AS_Speed.Value = p.Speed; app.AS_Interval.Value = p.Interval;
                case 'FieldSweep'
                    app.FS_StartField.Value = p.StartField; app.FS_EndField.Value = p.EndField;
                    app.FS_Rate.Value = p.Rate; app.FS_Interval.Value = p.Interval;
                case 'CurrentSweep'
                    app.CS_StartCurrent.Value = p.StartCurrent; app.CS_EndCurrent.Value = p.EndCurrent;
                    app.CS_Steps.Value = p.Steps; app.CS_Delay.Value = p.Delay;
                case 'TemperatureSweep'
                    app.TS_StartTemp.Value = p.StartTemp; app.TS_EndTemp.Value = p.EndTemp;
                    app.TS_Rate.Value = p.Rate; app.TS_Interval.Value = p.Interval;
            end

            if isfield(def, 'Static')
                app.SE_Field.Value = def.Static.Field;
                app.SE_Temp.Value = def.Static.Temperature;
                app.SE_Angle.Value = def.Static.Angle;
            end

            if isfield(def, 'LockIn')
                app.AC_Current.Value = def.LockIn.Current;
                app.AC_Freq.Value = def.LockIn.Freq;
                app.AC_TC.Value = def.LockIn.TC;
            end

            if isfield(def, 'Repeat')
                app.BackForthCheckbox.Value = def.Repeat.BackAndForth;
                app.RepetitionsEdit.Value = def.Repeat.Repetitions;
                app.onBackForthChanged();
            end

            app.onTypeChanged();
        end

        %% --- Save / Cancel ---
        function def = collectDefinition(app)
            def = struct();
            def.Name = app.NameEdit.Value;
            def.Type = app.TypeDrop.Value;
            def.ChannelSets = app.ChannelSets;
            def.ChannelItems = app.ChannelListBox.Items;

            switch def.Type
                case 'AngleSweep'
                    def.Params = struct('StartAngle', app.AS_StartAngle.Value, 'EndAngle', app.AS_EndAngle.Value, ...
                        'Speed', app.AS_Speed.Value, 'Interval', app.AS_Interval.Value);
                case 'FieldSweep'
                    def.Params = struct('StartField', app.FS_StartField.Value, 'EndField', app.FS_EndField.Value, ...
                        'Rate', app.FS_Rate.Value, 'Interval', app.FS_Interval.Value);
                case 'CurrentSweep'
                    def.Params = struct('StartCurrent', app.CS_StartCurrent.Value, 'EndCurrent', app.CS_EndCurrent.Value, ...
                        'Steps', app.CS_Steps.Value, 'Delay', app.CS_Delay.Value);
                case 'TemperatureSweep'
                    def.Params = struct('StartTemp', app.TS_StartTemp.Value, 'EndTemp', app.TS_EndTemp.Value, ...
                        'Rate', app.TS_Rate.Value, 'Interval', app.TS_Interval.Value);
            end

            % Static environment: whichever quantity isn't in Params above.
            def.Static = struct('Field', app.SE_Field.Value, 'Temperature', app.SE_Temp.Value, 'Angle', app.SE_Angle.Value);

            def.Repeat = struct('BackAndForth', app.BackForthCheckbox.Value, ...
                'Repetitions', round(app.RepetitionsEdit.Value));

            if ~strcmp(def.Type, 'CurrentSweep')
                def.LockIn = struct('Current', app.AC_Current.Value, 'Freq', app.AC_Freq.Value, 'TC', app.AC_TC.Value);
            end
        end

        function onSave(app)
            if isempty(app.NameEdit.Value)
                uialert(app.UIFigure, 'Please enter an experiment name.', 'Missing Name');
                return;
            end
            if isempty(app.ChannelSets)
                uialert(app.UIFigure, 'Please add at least one channel set.', 'Missing Channels');
                return;
            end

            targetFile = app.ExistingFilePath;
            if isempty(targetFile)
                defaultName = [regexprep(app.NameEdit.Value, '[^\w\- ]', ''), '.mat'];
                [file, path] = uiputfile('*.mat', 'Save Experiment Definition', defaultName);
                if isequal(file, 0); return; end
                targetFile = fullfile(path, file);

                % Auto-sync Name from the chosen filename if it still
                % looks like the untouched default, so the queue label
                % matches the file you actually picked.
                if strcmp(strtrim(app.NameEdit.Value), 'New Experiment')
                    [~, baseName, ~] = fileparts(file);
                    app.NameEdit.Value = baseName;
                end
            end

            % Safety net for any other case where Name still looks
            % unedited (e.g. editing an existing experiment that was
            % never renamed).
            if strcmp(strtrim(app.NameEdit.Value), 'New Experiment')
                choice = uiconfirm(app.UIFigure, ...
                    'The experiment name is still "New Experiment" - are you sure that''s what you want to call it?', ...
                    'Confirm Name', 'Options', {'Save Anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Save Anyway')
                    return;
                end
            end

            def = app.collectDefinition();
            def.DefinitionFile = targetFile;
            experiment = def; %#ok<NASGU>
            save(targetFile, 'experiment');

            app.Result = def;
            uiresume(app.UIFigure);
        end

        function onCancel(app)
            app.Result = [];
            uiresume(app.UIFigure);
        end
    end
end

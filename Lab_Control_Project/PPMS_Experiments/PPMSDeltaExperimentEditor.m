classdef PPMSDeltaExperimentEditor < handle
    % PPMSExperimentEditor - Modal editor for a single queued experiment.

    properties (Access = private)
        UIFigure
        Result = []
        ExistingFilePath = ''

        % Name / Type
        NameEdit
        TypeDrop

        % Type-specific sweep panels
        AnglePanel
        AS_StartAngle, AS_EndAngle, AS_Speed, AS_Interval

        FieldSweepPanel
        FS_StartField, FS_EndField, FS_Rate, FS_Interval, FS_FromZero

        CurrentSweepPanel
        CS_StartCurrent, CS_EndCurrent, CS_Steps, CS_Delay, CS_Compliance, CS_RestTime

        TempSweepPanel
        TS_StartTemp, TS_EndTemp, TS_Rate, TS_Interval

        % Shared "held constant" environment panel
        StaticPanel
        SE_FieldLabel, SE_Field
        SE_TempLabel, SE_Temp, SE_TempRateLabel, SE_TempRate, SE_TempApproachLabel, SE_TempApproach
        SE_AngleLabel, SE_Angle

        % Shared repeat/back-and-forth panel
        RepeatPanel
        BackForthCheckbox, RepetitionsEdit

        % Shared Keithley Delta Mode panel
        DeltaPanel
        Delta_PosI, Delta_NegI, Delta_Repeats, Delta_Delay, Delta_Range

        % Channel sets
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
            editor = PPMSDeltaExperimentEditor(existingDef);
            uiwait(editor.UIFigure);
            def = editor.Result;
            if isvalid(editor.UIFigure)
                delete(editor.UIFigure);
            end
        end
    end

    methods (Access = private)
        function app = PPMSDeltaExperimentEditor(existingDef)
            app.UIFigure = uifigure('Name', 'Experiment Editor', 'Position', [200, 50, 540, 780], ...
                'WindowStyle', 'modal', 'CloseRequestFcn', @(s,e) app.onCancel());
            movegui(app.UIFigure, 'center');

            layout = uigridlayout(app.UIFigure, [8, 1], ...
                'RowHeight', {'fit', 'fit', 220, 'fit', 'fit', 'fit', 'fit', 'fit'}, 'Scrollable', 'on');

            app.createNamePanel(layout);
            app.createTypePanel(layout);
            app.createSweepPanels(layout);
            app.createStaticPanel(layout);
            app.createRepeatPanel(layout);
            app.createDeltaPanel(layout);
            app.createChannelPanel(layout);
            app.createButtonRow(layout);

            if ~isempty(existingDef)
                app.populateFrom(existingDef);
            else
                app.onTypeChanged();
            end
        end

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

            app.AnglePanel = uipanel(containerLayout, 'Title', 'Angle Sweep');
            g = uigridlayout(app.AnglePanel, [4, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Angle (deg):'); app.AS_StartAngle = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End Angle (deg):');   app.AS_EndAngle = uieditfield(g, 'numeric', 'Value', 360.0);
            uilabel(g, 'Text', 'Speed (deg/sec):');   app.AS_Speed = uieditfield(g, 'numeric', 'Value', 1.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.AS_Interval = uieditfield(g, 'numeric', 'Value', 1.0);
            app.AnglePanel.Layout.Row = 1; app.AnglePanel.Layout.Column = 1;

            app.FieldSweepPanel = uipanel(containerLayout, 'Title', 'Field Sweep');
            g = uigridlayout(app.FieldSweepPanel, [5, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Field (Oe):'); app.FS_StartField = uieditfield(g, 'numeric', 'Value', 0.0);
            uilabel(g, 'Text', 'End Field (Oe):');   app.FS_EndField = uieditfield(g, 'numeric', 'Value', 10000.0);
            uilabel(g, 'Text', 'Rate (Oe/sec):');    app.FS_Rate = uieditfield(g, 'numeric', 'Value', 50.0);
            uilabel(g, 'Text', 'Read Interval (s):'); app.FS_Interval = uieditfield(g, 'numeric', 'Value', 1.0);
            app.FS_FromZero = uicheckbox(g, 'Text', 'Start measuring from 0 Oe (0 → Start Field as Repetition 0)', 'Value', false);
            app.FS_FromZero.Layout.Column = [1 2];
            app.FieldSweepPanel.Layout.Row = 1; app.FieldSweepPanel.Layout.Column = 1;

            app.CurrentSweepPanel = uipanel(containerLayout, 'Title', 'Current Sweep (DC I-V)');
            g = uigridlayout(app.CurrentSweepPanel, [6, 2], 'ColumnWidth', {'1x', 100});
            uilabel(g, 'Text', 'Start Current (A):'); app.CS_StartCurrent = uieditfield(g, 'numeric', 'Value', -10e-6);
            uilabel(g, 'Text', 'End Current (A):');   app.CS_EndCurrent   = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', 'Steps:');             app.CS_Steps        = uieditfield(g, 'numeric', 'Value', 51);
            uilabel(g, 'Text', 'Delay/Pt (s):');      app.CS_Delay        = uieditfield(g, 'numeric', 'Value', 0.2);
            uilabel(g, 'Text', 'Compliance (V):');    app.CS_Compliance   = uieditfield(g, 'numeric', 'Value', 10.0);
            uilabel(g, 'Text', 'Rest Time (s):');     app.CS_RestTime     = uieditfield(g, 'numeric', 'Value', 0.0);
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
            app.StaticPanel = uipanel(parent, 'Title', 'Static Environment (held constant)');
            g = uigridlayout(app.StaticPanel, [5, 2], 'ColumnWidth', {'1x', 120});

            app.SE_FieldLabel = uilabel(g, 'Text', 'Field (Oe):'); app.SE_Field = uieditfield(g, 'numeric', 'Value', 0.0);
            app.SE_TempLabel = uilabel(g, 'Text', 'Temperature (K):'); app.SE_Temp = uieditfield(g, 'numeric', 'Value', 300.0);
            app.SE_TempRateLabel = uilabel(g, 'Text', 'Temp Rate (K/min):'); app.SE_TempRate = uieditfield(g, 'numeric', 'Value', 10.0);
            app.SE_TempApproachLabel = uilabel(g, 'Text', 'Temp Approach:'); app.SE_TempApproach = uidropdown(g, 'Items', {'FastSettle', 'NoOvershoot', 'Linear'}, 'Value', 'FastSettle');
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

        function createDeltaPanel(app, parent)
            app.DeltaPanel = uipanel(parent, 'Title', 'Keithley Delta Mode Settings');
            g = uigridlayout(app.DeltaPanel, [3, 4], 'ColumnWidth', {90, '1x', 90, '1x'});

            uilabel(g, 'Text', '+I Current (A):'); app.Delta_PosI = uieditfield(g, 'numeric', 'Value', 10e-6);
            uilabel(g, 'Text', '-I Current (A):'); app.Delta_NegI = uieditfield(g, 'numeric', 'Value', -10e-6);
            uilabel(g, 'Text', 'Repeats:');        app.Delta_Repeats = uieditfield(g, 'numeric', 'Value', 3, 'Limits', [1 100], 'RoundFractionalValues', 'on');
            uilabel(g, 'Text', 'Delay (s):');       app.Delta_Delay = uieditfield(g, 'numeric', 'Value', 0.1, 'Limits', [0 Inf]);
            uilabel(g, 'Text', 'V Range:');        app.Delta_Range = uidropdown(g, 'Items', {'Auto', '10mV', '100mV', '1V', '10V', '100V'}, 'Value', 'Auto');
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

        function onTypeChanged(app)
            app.AnglePanel.Visible = 'off';
            app.FieldSweepPanel.Visible = 'off';
            app.CurrentSweepPanel.Visible = 'off';
            app.TempSweepPanel.Visible = 'off';

            app.SE_FieldLabel.Visible = 'on'; app.SE_Field.Visible = 'on';
            app.SE_TempLabel.Visible = 'on';  app.SE_Temp.Visible = 'on';
            app.SE_TempRateLabel.Visible = 'on'; app.SE_TempRate.Visible = 'on';
            app.SE_TempApproachLabel.Visible = 'on'; app.SE_TempApproach.Visible = 'on';
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
                case 'TemperatureSweep'
                    app.TempSweepPanel.Visible = 'on';
                    app.SE_TempLabel.Visible = 'off'; app.SE_Temp.Visible = 'off';
                    app.SE_TempRateLabel.Visible = 'off'; app.SE_TempRate.Visible = 'off';
                    app.SE_TempApproachLabel.Visible = 'off'; app.SE_TempApproach.Visible = 'off';
            end

            if strcmp(app.TypeDrop.Value, 'CurrentSweep')
                app.DeltaPanel.Visible = 'off';
            else
                app.DeltaPanel.Visible = 'on';
            end
        end

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
                    if isfield(p, 'FromZero'), app.FS_FromZero.Value = logical(p.FromZero); else, app.FS_FromZero.Value = false; end
                case 'CurrentSweep'
                    app.CS_StartCurrent.Value = p.StartCurrent; app.CS_EndCurrent.Value = p.EndCurrent;
                    app.CS_Steps.Value = p.Steps; app.CS_Delay.Value = p.Delay;
                    if isfield(p, 'Compliance'), app.CS_Compliance.Value = p.Compliance; else, app.CS_Compliance.Value = 10.0; end
                    if isfield(p, 'RestTime'),   app.CS_RestTime.Value   = p.RestTime;   else, app.CS_RestTime.Value   = 0.0;  end
                case 'TemperatureSweep'
                    app.TS_StartTemp.Value = p.StartTemp; app.TS_EndTemp.Value = p.EndTemp;
                    app.TS_Rate.Value = p.Rate; app.TS_Interval.Value = p.Interval;
            end

            if isfield(def, 'Static')
                app.SE_Field.Value = def.Static.Field;
                app.SE_Temp.Value = def.Static.Temperature;
                if isfield(def.Static, 'TempRate'); app.SE_TempRate.Value = def.Static.TempRate; end
                if isfield(def.Static, 'TempApproach'); app.SE_TempApproach.Value = def.Static.TempApproach; end
                app.SE_Angle.Value = def.Static.Angle;
            end

            if isfield(def, 'Delta')
                app.Delta_PosI.Value = def.Delta.PosI;
                app.Delta_NegI.Value = def.Delta.NegI;
                app.Delta_Repeats.Value = def.Delta.Repeats;
                app.Delta_Delay.Value = def.Delta.Delay;
                app.Delta_Range.Value = def.Delta.Range;
            elseif isfield(def, 'LockIn')
                app.Delta_PosI.Value = def.LockIn.Current;
                app.Delta_NegI.Value = -def.LockIn.Current;
            end

            if isfield(def, 'Repeat')
                app.BackForthCheckbox.Value = def.Repeat.BackAndForth;
                app.RepetitionsEdit.Value = def.Repeat.Repetitions;
                app.onBackForthChanged();
            end

            app.onTypeChanged();
        end

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
                        'Rate', app.FS_Rate.Value, 'Interval', app.FS_Interval.Value, ...
                        'FromZero', app.FS_FromZero.Value);
                case 'CurrentSweep'
                    def.Params = struct(...
                        'StartCurrent', app.CS_StartCurrent.Value, ...
                        'EndCurrent',   app.CS_EndCurrent.Value, ...
                        'Steps',        app.CS_Steps.Value, ...
                        'Delay',        app.CS_Delay.Value, ...
                        'Compliance',   app.CS_Compliance.Value, ...
                        'RestTime',     app.CS_RestTime.Value);
                case 'TemperatureSweep'
                    def.Params = struct('StartTemp', app.TS_StartTemp.Value, 'EndTemp', app.TS_EndTemp.Value, ...
                        'Rate', app.TS_Rate.Value, 'Interval', app.TS_Interval.Value);
            end

            def.Static = struct('Field', app.SE_Field.Value, ...
                'Temperature', app.SE_Temp.Value, ...
                'TempRate', app.SE_TempRate.Value, ...
                'TempApproach', app.SE_TempApproach.Value, ...
                'Angle', app.SE_Angle.Value);

            def.Repeat = struct('BackAndForth', app.BackForthCheckbox.Value, ...
                'Repetitions', round(app.RepetitionsEdit.Value));

            if ~strcmp(def.Type, 'CurrentSweep')
                def.Delta = struct(...
                    'PosI', app.Delta_PosI.Value, ...
                    'NegI', app.Delta_NegI.Value, ...
                    'Repeats', app.Delta_Repeats.Value, ...
                    'Delay', app.Delta_Delay.Value, ...
                    'Range', app.Delta_Range.Value);
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

                if strcmp(strtrim(app.NameEdit.Value), 'New Experiment')
                    [~, baseName, ~] = fileparts(file);
                    app.NameEdit.Value = baseName;
                end
            end

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
classdef ExperimentDataRecorder < handle
    % ExperimentDataRecorder - Records one experiment's data on the local disk.
    % Every row is kept in memory and also appended to a CSV on the local
    % disk as it is measured, so nothing depends on a network drive while
    % an experiment runs. finish() closes the CSV and writes the .mat
    % straight from the rows in memory.

    properties (SetAccess = private)
        CsvFile = ''
        MatFile = ''
        NumRows = 0
        IsFinished = false
    end

    properties (Access = private)
        FileID = -1
        Metadata = {}
        Columns = {}
        RowFormat = ''
        Rows = zeros(0, 0)
    end

    methods
        function obj = ExperimentDataRecorder(csvFile)
            obj.CsvFile = csvFile;
            [folder, name] = fileparts(csvFile);
            obj.MatFile = fullfile(folder, [name '.mat']);
            obj.FileID = fopen(csvFile, 'w');
            if obj.FileID < 0
                error('Could not open local data file: %s', csvFile);
            end
        end

        function addMetadata(obj, fmt, varargin)
            % One "% ..." header line, e.g. addMetadata('Experiment: %s', name).
            line = ['% ' sprintf(fmt, varargin{:})];
            obj.Metadata{end+1, 1} = line;
            fprintf(obj.FileID, '%s\n', line);
        end

        function setColumns(obj, columns, rowFormat)
            % rowFormat is the fprintf format of one row, e.g. '%.2f,%d,%f,%e'.
            obj.Columns = columns;
            obj.RowFormat = [rowFormat '\n'];
            obj.Rows = NaN(1024, numel(columns));
            fprintf(obj.FileID, '%s\n', strjoin(columns, ','));
        end

        function addRow(obj, values)
            if obj.NumRows == size(obj.Rows, 1)
                obj.Rows = [obj.Rows; NaN(size(obj.Rows))];
            end
            obj.NumRows = obj.NumRows + 1;
            obj.Rows(obj.NumRows, :) = values;
            fprintf(obj.FileID, obj.RowFormat, values);
        end

        function finish(obj, experiment)
            % Closes the CSV and saves data, columns, metadata and the
            % experiment definition to the .mat. Only the first call acts.
            if obj.IsFinished; return; end
            obj.IsFinished = true;
            try fclose(obj.FileID); catch; end

            data = obj.Rows(1:obj.NumRows, :);
            columns = obj.Columns;
            metadata = obj.Metadata;
            save(obj.MatFile, 'data', 'columns', 'metadata', 'experiment');
        end
    end
end

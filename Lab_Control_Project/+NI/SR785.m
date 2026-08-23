classdef SR785 < handle
    % SR785 - Object-Oriented MATLAB Wrapper for Stanford Research Systems SR785
    
    properties (Access = private)
        VisaObj             
        IsSimulated = false 
    end
    
    methods
        function obj = SR785(resourceString)
            if strcmpi(resourceString, 'SIM')
                obj.IsSimulated = true;
                return;
            end
            
            try
                obj.VisaObj = visadev(resourceString);
                writeline(obj.VisaObj, '*CLS');
                idn = writeread(obj.VisaObj, '*IDN?');
                fprintf('Successfully connected to SR785 at %s\n', resourceString);
            catch ME
                error('Failed to open VISA connection to SR785 at %s. Error: %s', resourceString, ME.message);
            end
        end
        
        function restartAveraging(obj)
            % שולח פקודה לאיפוס המיצוע והתחלת דגימה חדשה
            if obj.IsSimulated
                fprintf('[SIM SR785] Averaging Restarted.\n');
                return;
            end
            try
                writeline(obj.VisaObj, 'STRT');
            catch ME
                warning('Failed to restart SR785 averaging: %s', ME.message);
            end
        end
        
        function delete(obj)
            if obj.IsSimulated
                return;
            end
            if ~isempty(obj.VisaObj) && isvalid(obj.VisaObj)
                delete(obj.VisaObj);
                obj.VisaObj = [];
            end
        end
        
        % הפונקציה עודכנה לקבל את ה-span (כמו ב-extractor)
        function [freq, amplitude] = readTrace(obj, traceNum, spanFreq)
            if nargin < 2; traceNum = 0; end
            if nargin < 3; spanFreq = 100000; end % Default
            
            if obj.IsSimulated
                freq = linspace(0, spanFreq, 400)';
                amplitude = -100 + 20*log10(abs(sin(2*pi*freq/(spanFreq/10)) + randn(400, 1)*0.1));
                return;
            end
            
            try
                rawData = writeread(obj.VisaObj, sprintf('DSPY ? %d', traceNum));
                amplitude = str2double(split(rawData, ','));
                numPoints = length(amplitude);
                
                % בניית ציר תדר מ-0 ועד ה-Span שהוגדר ידנית בממשק
                freq = linspace(0, spanFreq, numPoints)';
                
            catch ME
                warning('Failed to fetch trace data: %s', ME.message);
                freq = NaN;
                amplitude = NaN;
            end
        end
        
        function autoRange(obj, chNum)
            if nargin < 2; chNum = 1; end
            if obj.IsSimulated; return; end
            writeline(obj.VisaObj, sprintf('A1RG %d', chNum - 1)); 
        end
    end
end
%% ME 395 Measurement Error and Uncertainty Analysis
% Open this file in MATLAB and click Run. If inputFile is empty, MATLAB
% opens a picker that accepts native tab-delimited lab exports (including
% files with no extension) and structured .xls/.xlsx workbooks.

inputFile = "";
outputFile = "";

% ME 395 allows one or two significant digits in the uncertainty. The 2026
% slides say one digit is generally best, so that is the default here.
uncertaintySignificantDigits = 1;

% For a native lab export, leave labOptions empty to choose the channel,
% steady analysis interval, unit, accuracy error, and resolution in dialogs.
labOptions = struct();

% For a repeatable, noninteractive run, use a settings table such as the
% illustrative example below. Replace error values with verified values.
%
% labOptions.TimeRange = [0 10]; % Example only; choose a steady interval.
% labOptions.ChannelSettings = table( ...
%     "Thermocouple", "Thermocouple temperature", "degC", 0.5, 0.01, ...
%     'VariableNames', {'Channel','Quantity','Unit', ...
%     'AccuracyError','Resolution'});

%% Run the analysis
[results, analysisInfo] = ME395_uncertainty_analysis( ...
    inputFile, outputFile, uncertaintySignificantDigits, labOptions);

%% Final report strings
results(:, {'Quantity', 'SourceColumn', 'FinalReport', 'DominantErrorSource'})

%% Full numerical results
results

%% Output workbook location
analysisInfo.OutputFile

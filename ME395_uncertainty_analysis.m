function [results, analysisInfo] = ME395_uncertainty_analysis(inputFile, outputFile, uncertaintySigDigits, labOptions)
%ME395_UNCERTAINTY_ANALYSIS Calculate ME 395 measurement uncertainty.
%
%   RESULTS = ME395_UNCERTAINTY_ANALYSIS(INPUTFILE) accepts either:
%     1. A native tab-delimited ME 395 lab export, including files with no
%        extension. The function detects the metadata and channel headers,
%        then asks which channel(s), time interval, units, accuracy error,
%        and resolution to use.
%     2. The original structured .xls/.xlsx input format. Its first sheet
%        must contain these columns:
%
%       Quantity | Unit | Measurement | AccuracyError | Resolution
%
%   One row represents one repeated reading. AccuracyError is the absolute
%   accuracy uncertainty in the listed unit. Resolution is the instrument's
%   smallest recorded increment; this function calculates ResolutionError
%   as Resolution/2. Repeated metadata may be entered on every row or only
%   once within each Quantity group.
%
%   [RESULTS, INFO] = ME395_UNCERTAINTY_ANALYSIS(INPUTFILE, OUTPUTFILE,
%   UNCERTAINTYSIGDIGITS, LABOPTIONS) also selects the output workbook, the
%   number of significant digits used to report uncertainty (1 or 2;
%   default 1), and noninteractive settings for a native lab export.
%
%   LABOPTIONS may contain:
%       TimeRange       [startTime endTime], inclusive
%       ChannelSettings table with columns:
%           Channel, Quantity, Unit, AccuracyError, Resolution
%   If ChannelSettings is omitted for a native export, dialogs collect the
%   settings. AccuracyError and Resolution are absolute values in Unit.
%
%   With no INPUTFILE, an interactive file picker opens. Results are written
%   to an .xlsx workbook unless OUTPUTFILE is supplied.
%
%   ME 395 conventions implemented here:
%       sample standard deviation       s
%       standard deviation of the mean  s/sqrt(N)
%       precision error, one reading    2*s
%       precision error, mean           2*s/sqrt(N)
%       resolution error                Resolution/2
%       final uncertainty               sqrt(ea^2 + ep^2 + er^2)
%
%   The final reported value uses the uncertainty of the mean. Accuracy and
%   resolution errors are not divided by sqrt(N). No outliers are removed.

    if nargin < 1 || isBlankPath(inputFile)
        [fileName, folderName] = uigetfile( ...
            {'*', 'All files, including extensionless lab exports'}, ...
            'Select the ME 395 measurement data file');
        if isequal(fileName, 0)
            error('ME395:NoInputSelected', 'No input data file was selected.');
        end
        inputFile = fullfile(folderName, fileName);
    end

    inputFile = char(inputFile);
    if ~isfile(inputFile)
        error('ME395:InputNotFound', 'Input file does not exist: %s', inputFile);
    end

    [inputFolder, inputBase, inputExtension] = fileparts(inputFile);
    if nargin < 2 || isBlankPath(outputFile)
        outputFile = fullfile(inputFolder, [inputBase '_uncertainty_results.xlsx']);
    end
    outputFile = char(outputFile);
    [outputFolder, ~, outputExtension] = fileparts(outputFile);
    if isempty(outputFolder)
        outputFolder = pwd;
        outputFile = fullfile(outputFolder, outputFile);
    end
    if ~isfolder(outputFolder)
        error('ME395:OutputFolderNotFound', ...
            'Output folder does not exist: %s', outputFolder);
    end
    if ~any(strcmpi(outputExtension, {'.xls', '.xlsx'}))
        error('ME395:UnsupportedOutput', ...
            'Output must use the .xls or .xlsx extension.');
    end
    if strcmpi(canonicalPath(inputFile), canonicalPath(outputFile))
        error('ME395:SameInputAndOutput', ...
            'The output workbook must not overwrite the input workbook.');
    end

    if nargin < 3 || isempty(uncertaintySigDigits)
        uncertaintySigDigits = 1;
    end
    validateattributes(uncertaintySigDigits, {'numeric'}, ...
        {'scalar', 'integer', '>=', 1, '<=', 2}, mfilename, ...
        'uncertaintySigDigits');

    if nargin < 4 || isempty(labOptions)
        labOptions = struct();
    end
    if ~isstruct(labOptions)
        error('ME395:InvalidLabOptions', 'labOptions must be a structure.');
    end

    if any(strcmpi(inputExtension, {'.xls', '.xlsx', '.xlsm'}))
        raw = readInputTable(inputFile);
        sourceMetadata = table( ...
            ["InputFormat"; "SourceFile"; "RowsRead"], ...
            ["Structured workbook"; string(inputFile); string(height(raw))], ...
            'VariableNames', {'Field', 'Value'});
    else
        [raw, sourceMetadata] = readNativeLabExport(inputFile, labOptions);
    end
    if height(raw) == 0
        error('ME395:EmptyInput', 'The input file contains no data rows.');
    end

    quantityName = findColumn(raw, {'Quantity', 'Variable', 'Name'});
    unitName = findColumn(raw, {'Unit', 'Units'});
    measurementName = findColumn(raw, {'Measurement', 'Reading', 'Value', 'Data'});
    accuracyName = findColumn(raw, ...
        {'AccuracyError', 'Accuracy Error', 'AccuracyUncertainty', 'ea'});
    resolutionName = findColumn(raw, ...
        {'Resolution', 'SmallestIncrement', 'InstrumentResolution'});

    quantity = string(raw.(quantityName));
    unit = string(raw.(unitName));
    measurement = numericColumn(raw.(measurementName), measurementName);
    accuracy = numericColumn(raw.(accuracyName), accuracyName);
    resolution = numericColumn(raw.(resolutionName), resolutionName);
    if any(strcmp(raw.Properties.VariableNames, 'SourceColumn'))
        sourceColumn = string(raw.SourceColumn);
    else
        sourceColumn = quantity;
    end

    quantity = strtrim(quantity);
    unit = strtrim(unit);
    sourceColumn = strtrim(sourceColumn);
    quantityMissing = missingText(quantity);
    unitMissing = missingText(unit);

    entirelyBlank = quantityMissing & unitMissing & isnan(measurement) & ...
        isnan(accuracy) & isnan(resolution);
    quantity(entirelyBlank) = [];
    unit(entirelyBlank) = [];
    sourceColumn(entirelyBlank) = [];
    measurement(entirelyBlank) = [];
    accuracy(entirelyBlank) = [];
    resolution(entirelyBlank) = [];
    quantityMissing(entirelyBlank) = [];

    if any(quantityMissing)
        badRows = find(quantityMissing);
        error('ME395:MissingQuantity', ...
            'Quantity is missing in data row(s): %s', rowList(badRows));
    end
    if any(~isfinite(measurement))
        badRows = find(~isfinite(measurement));
        error('ME395:InvalidMeasurement', ...
            'Measurement must be finite in data row(s): %s', rowList(badRows));
    end

    quantities = unique(quantity, 'stable');
    numberOfQuantities = numel(quantities);

    resultQuantity = strings(numberOfQuantities, 1);
    resultSourceColumn = strings(numberOfQuantities, 1);
    resultUnit = strings(numberOfQuantities, 1);
    numberOfReadings = zeros(numberOfQuantities, 1);
    averageValue = nan(numberOfQuantities, 1);
    standardDeviation = nan(numberOfQuantities, 1);
    standardDeviationOfMean = nan(numberOfQuantities, 1);
    accuracyError = nan(numberOfQuantities, 1);
    precisionErrorSingle = nan(numberOfQuantities, 1);
    precisionErrorMean = nan(numberOfQuantities, 1);
    instrumentResolution = nan(numberOfQuantities, 1);
    resolutionError = nan(numberOfQuantities, 1);
    finalUncertaintySingle = nan(numberOfQuantities, 1);
    finalUncertaintyMean = nan(numberOfQuantities, 1);
    accuracyContributionPercent = nan(numberOfQuantities, 1);
    precisionContributionPercent = nan(numberOfQuantities, 1);
    resolutionContributionPercent = nan(numberOfQuantities, 1);
    dominantErrorSource = strings(numberOfQuantities, 1);
    roundedAverage = nan(numberOfQuantities, 1);
    roundedFinalUncertainty = nan(numberOfQuantities, 1);
    finalReport = strings(numberOfQuantities, 1);

    for k = 1:numberOfQuantities
        groupRows = quantity == quantities(k);
        values = measurement(groupRows);

        resultQuantity(k) = quantities(k);
        resultSourceColumn(k) = oneTextSetting(sourceColumn(groupRows), ...
            'SourceColumn', quantities(k));
        resultUnit(k) = oneTextSetting(unit(groupRows), 'Unit', quantities(k));
        accuracyError(k) = oneNumericSetting(accuracy(groupRows), ...
            'AccuracyError', quantities(k));
        instrumentResolution(k) = oneNumericSetting(resolution(groupRows), ...
            'Resolution', quantities(k));

        if accuracyError(k) < 0
            error('ME395:NegativeAccuracyError', ...
                'AccuracyError must be nonnegative for Quantity "%s".', quantities(k));
        end
        if instrumentResolution(k) < 0
            error('ME395:NegativeResolution', ...
                'Resolution must be nonnegative for Quantity "%s".', quantities(k));
        end

        numberOfReadings(k) = numel(values);
        averageValue(k) = mean(values);
        resolutionError(k) = instrumentResolution(k) / 2;

        if numberOfReadings(k) < 2
            warning('ME395:TooFewReadings', ...
                ['Quantity "%s" has only one reading. Standard deviation, ' ...
                 'precision error, and final uncertainty cannot be estimated.'], ...
                quantities(k));
            finalReport(k) = "N < 2: precision and final uncertainty unavailable";
            dominantErrorSource(k) = "Unavailable";
            continue
        end

        standardDeviation(k) = std(values, 0);
        standardDeviationOfMean(k) = standardDeviation(k) / ...
            sqrt(numberOfReadings(k));
        precisionErrorSingle(k) = 2 * standardDeviation(k);
        precisionErrorMean(k) = 2 * standardDeviationOfMean(k);

        finalUncertaintySingle(k) = rss3(accuracyError(k), ...
            precisionErrorSingle(k), resolutionError(k));
        finalUncertaintyMean(k) = rss3(accuracyError(k), ...
            precisionErrorMean(k), resolutionError(k));

        squaredTotal = finalUncertaintyMean(k)^2;
        if squaredTotal > 0
            accuracyContributionPercent(k) = ...
                100 * accuracyError(k)^2 / squaredTotal;
            precisionContributionPercent(k) = ...
                100 * precisionErrorMean(k)^2 / squaredTotal;
            resolutionContributionPercent(k) = ...
                100 * resolutionError(k)^2 / squaredTotal;
        else
            accuracyContributionPercent(k) = 0;
            precisionContributionPercent(k) = 0;
            resolutionContributionPercent(k) = 0;
        end

        dominantErrorSource(k) = dominantSource(accuracyError(k), ...
            precisionErrorMean(k), resolutionError(k));

        [roundedAverage(k), roundedFinalUncertainty(k), valueText, errorText] = ...
            roundForReport(averageValue(k), finalUncertaintyMean(k), ...
            uncertaintySigDigits);
        finalReport(k) = string(sprintf('%s %c %s %s', ...
            valueText, char(177), errorText, char(resultUnit(k))));
    end

    results = table(resultQuantity, resultSourceColumn, resultUnit, numberOfReadings, ...
        averageValue, standardDeviation, standardDeviationOfMean, ...
        accuracyError, precisionErrorSingle, precisionErrorMean, ...
        instrumentResolution, resolutionError, finalUncertaintySingle, ...
        finalUncertaintyMean, accuracyContributionPercent, ...
        precisionContributionPercent, resolutionContributionPercent, ...
        dominantErrorSource, roundedAverage, roundedFinalUncertainty, ...
        finalReport, ...
        'VariableNames', {'Quantity', 'SourceColumn', 'Unit', 'N', 'Average', ...
        'StandardDeviation', 'StandardDeviationOfMean', 'AccuracyError', ...
        'PrecisionErrorSingle', 'PrecisionErrorMean', 'Resolution', ...
        'ResolutionError', 'FinalUncertaintySingle', ...
        'FinalUncertaintyMean', 'AccuracyContributionPercent', ...
        'PrecisionContributionPercent', 'ResolutionContributionPercent', ...
        'DominantErrorSource', 'RoundedAverage', ...
        'RoundedFinalUncertainty', 'FinalReport'});

    method = buildMethodTable(uncertaintySigDigits);
    writeResults(results, method, sourceMetadata, outputFile);

    analysisInfo = struct();
    analysisInfo.InputFile = inputFile;
    analysisInfo.OutputFile = outputFile;
    analysisInfo.UncertaintySignificantDigits = uncertaintySigDigits;
    analysisInfo.FinalReportUses = 'uncertainty of the mean';
    analysisInfo.OutliersRemoved = false;
    analysisInfo.SourceMetadata = sourceMetadata;

    fprintf('\nME 395 uncertainty analysis\n');
    fprintf('Input:  %s\n', inputFile);
    fprintf('Output: %s\n\n', outputFile);
    for k = 1:height(results)
        fprintf('%s: %s\n', char(results.Quantity(k)), char(results.FinalReport(k)));
    end
end


function [raw, metadata] = readNativeLabExport(inputFile, labOptions)
    fileText = fileread(inputFile);
    fileText = strrep(fileText, sprintf('\r\n'), sprintf('\n'));
    fileText = strrep(fileText, sprintf('\r'), sprintf('\n'));
    lines = split(string(fileText), newline);

    headerIndex = find(contains(lines, char(9)), 1, 'first');
    if isempty(headerIndex)
        error('ME395:LabHeaderNotFound', ...
            'No tab-delimited channel header was found in the lab export.');
    end

    channelHeaders = strtrim(split(lines(headerIndex), char(9)));
    numberOfColumns = numel(channelHeaders);
    if numberOfColumns < 2
        error('ME395:LabColumnsMissing', ...
            'The lab export must contain a time column and at least one data channel.');
    end

    dataLines = lines(headerIndex + 1:end);
    dataLines = dataLines(~missingText(dataLines));
    if isempty(dataLines)
        error('ME395:LabDataMissing', 'The lab export contains no numeric data rows.');
    end

    formatSpec = repmat('%f', 1, numberOfColumns);
    parsed = textscan(char(strjoin(dataLines, newline)), formatSpec, ...
        'Delimiter', char(9), 'CollectOutput', true, ...
        'ReturnOnError', false, 'EmptyValue', NaN);
    data = parsed{1};
    if size(data, 1) ~= numel(dataLines) || size(data, 2) ~= numberOfColumns
        error('ME395:MalformedLabData', ...
            ['The numeric data section does not consistently match the ' ...
             '%d detected channel headers.'], numberOfColumns);
    end
    if any(~isfinite(data), 'all')
        error('ME395:InvalidLabData', ...
            'The lab export contains missing or nonfinite numeric values.');
    end

    preamble = strtrim(lines(1:headerIndex - 1));
    preamble = preamble(~missingText(preamble));
    experimentTitle = "";
    recordedAt = "";
    if numel(preamble) >= 1
        experimentTitle = preamble(1);
    end
    if numel(preamble) >= 2
        recordedAt = preamble(2);
    end

    sampleRateHz = NaN;
    for k = 1:numel(preamble)
        token = regexp(char(preamble(k)), ...
            'Sample\s*Rate.*?=\s*([-+0-9.eE]+)', 'tokens', 'once');
        if ~isempty(token)
            sampleRateHz = str2double(token{1});
            break
        end
    end

    normalizedHeaders = strings(numberOfColumns, 1);
    for k = 1:numberOfColumns
        normalizedHeaders(k) = string(normalizeName(channelHeaders(k)));
    end
    timeIndex = find(startsWith(normalizedHeaders, "time"), 1, 'first');
    if isempty(timeIndex)
        timeValues = (0:size(data, 1) - 1)';
        timeHeader = "Row index";
        candidateIndices = 1:numberOfColumns;
    else
        timeValues = data(:, timeIndex);
        timeHeader = channelHeaders(timeIndex);
        candidateIndices = setdiff(1:numberOfColumns, timeIndex, 'stable');
    end

    if isfield(labOptions, 'TimeRange') && ~isempty(labOptions.TimeRange)
        timeRange = double(labOptions.TimeRange);
        validateattributes(timeRange, {'numeric'}, ...
            {'vector', 'numel', 2, 'finite'}, mfilename, ...
            'labOptions.TimeRange');
        timeRange = timeRange(:)';
        if timeRange(2) < timeRange(1)
            error('ME395:InvalidTimeRange', ...
                'TimeRange end must be greater than or equal to its start.');
        end
    else
        timeRange = promptTimeRange(timeValues, timeHeader);
    end

    selectedRows = timeValues >= timeRange(1) & timeValues <= timeRange(2);
    if nnz(selectedRows) < 2
        error('ME395:TooFewSelectedRows', ...
            'The selected interval contains fewer than two data rows.');
    end

    if isfield(labOptions, 'ChannelSettings') && ...
            ~isempty(labOptions.ChannelSettings)
        settings = normalizeChannelSettings(labOptions.ChannelSettings);
    else
        settings = promptChannelSettings(channelHeaders, candidateIndices);
    end

    numberOfChannels = height(settings);
    columnIndices = zeros(numberOfChannels, 1);
    for k = 1:numberOfChannels
        matches = find(strcmpi(strtrim(channelHeaders), ...
            strtrim(settings.Channel(k))));
        if isempty(matches)
            normalizedTarget = normalizeName(settings.Channel(k));
            matches = find(strcmp(normalizedHeaders, normalizedTarget));
        end
        if numel(matches) ~= 1
            error('ME395:ChannelNotFound', ...
                'Channel "%s" does not uniquely match a source column.', ...
                settings.Channel(k));
        end
        if ~ismember(matches, candidateIndices)
            error('ME395:TimeChannelSelected', ...
                'The time column cannot be analyzed as a measurement channel.');
        end
        columnIndices(k) = matches;
        settings.Channel(k) = channelHeaders(matches);
    end

    if numel(unique(settings.Quantity)) ~= numberOfChannels
        error('ME395:DuplicateOutputQuantity', ...
            'Each selected channel must have a unique output Quantity name.');
    end

    numberOfSelectedRows = nnz(selectedRows);
    pieces = cell(numberOfChannels, 1);
    for k = 1:numberOfChannels
        Quantity = repmat(settings.Quantity(k), numberOfSelectedRows, 1);
        SourceColumn = repmat(settings.Channel(k), numberOfSelectedRows, 1);
        Unit = repmat(settings.Unit(k), numberOfSelectedRows, 1);
        Measurement = data(selectedRows, columnIndices(k));
        AccuracyError = repmat(settings.AccuracyError(k), numberOfSelectedRows, 1);
        Resolution = repmat(settings.Resolution(k), numberOfSelectedRows, 1);
        pieces{k} = table(Quantity, SourceColumn, Unit, Measurement, ...
            AccuracyError, Resolution);
    end
    raw = vertcat(pieces{:});

    metadataFields = [
        "InputFormat"
        "SourceFile"
        "ExperimentTitle"
        "RecordedAt"
        "SampleRateHz"
        "TimeColumn"
        "SelectedStartTime"
        "SelectedEndTime"
        "RowsInFile"
        "RowsUsedPerChannel"
        "SelectedChannels"
        "AnalysisNote"
        ];
    metadataValues = [
        "Native tab-delimited lab export"
        string(inputFile)
        experimentTitle
        recordedAt
        numberText(sampleRateHz)
        timeHeader
        numberText(min(timeValues(selectedRows)))
        numberText(max(timeValues(selectedRows)))
        string(size(data, 1))
        string(numberOfSelectedRows)
        strjoin(settings.Channel, ", ")
        "Use a nominally steady interval when estimating precision uncertainty."
        ];
    metadata = table(metadataFields, metadataValues, ...
        'VariableNames', {'Field', 'Value'});
end


function timeRange = promptTimeRange(timeValues, timeHeader)
    prompts = {
        sprintf('Start %s (choose a nominally steady interval):', char(timeHeader))
        sprintf('End %s (inclusive):', char(timeHeader))
        };
    defaults = {
        sprintf('%.15g', min(timeValues))
        sprintf('%.15g', max(timeValues))
        };
    answer = inputdlg(prompts, 'Select analysis interval', [1 68], defaults);
    if isempty(answer)
        error('ME395:IntervalCancelled', 'Analysis interval selection was cancelled.');
    end
    timeRange = [str2double(answer{1}), str2double(answer{2})];
    if any(~isfinite(timeRange)) || timeRange(2) < timeRange(1)
        error('ME395:InvalidTimeRange', ...
            'Start and end must be finite numbers with end greater than or equal to start.');
    end
end


function settings = promptChannelSettings(channelHeaders, candidateIndices)
    candidates = channelHeaders(candidateIndices);
    derived = contains(lower(candidates), "std") | ...
        contains(lower(candidates), "variance");
    initialSelection = find(~derived);
    if isempty(initialSelection)
        initialSelection = 1:numel(candidates);
    end

    [selected, accepted] = listdlg( ...
        'PromptString', {'Select the measurement channel(s) to analyze.', ...
        'Time is used only to select the interval.'}, ...
        'SelectionMode', 'multiple', 'ListString', cellstr(candidates), ...
        'InitialValue', initialSelection, 'ListSize', [520 320], ...
        'Name', 'ME 395 channels');
    if ~accepted || isempty(selected)
        error('ME395:ChannelSelectionCancelled', ...
            'No measurement channel was selected.');
    end

    selectedChannels = candidates(selected);
    count = numel(selectedChannels);
    Channel = strings(count, 1);
    Quantity = strings(count, 1);
    Unit = strings(count, 1);
    AccuracyError = zeros(count, 1);
    Resolution = zeros(count, 1);

    for k = 1:count
        Channel(k) = selectedChannels(k);
        defaultQuantity = regexprep(char(Channel(k)), '\s*\([^)]*\)\s*$', '');
        defaultUnit = inferUnit(Channel(k));
        prompts = {
            'Output quantity name:'
            'Unit:'
            'Absolute accuracy error:'
            'Instrument resolution (smallest recorded increment):'
            };
        defaults = {defaultQuantity, char(defaultUnit), '', ''};

        while true
            answer = inputdlg(prompts, ...
                sprintf('Settings: %s', char(Channel(k))), [1 70], defaults);
            if isempty(answer)
                error('ME395:ChannelSettingsCancelled', ...
                    'Channel settings entry was cancelled.');
            end

            quantityValue = strtrim(string(answer{1}));
            unitValue = strtrim(string(answer{2}));
            accuracyValue = str2double(answer{3});
            resolutionValue = str2double(answer{4});
            valid = ~missingText(quantityValue) && ~missingText(unitValue) && ...
                isfinite(accuracyValue) && accuracyValue >= 0 && ...
                isfinite(resolutionValue) && resolutionValue >= 0;
            if valid
                break
            end
            defaults = answer;
            warning('ME395:InvalidInteractiveSettings', ...
                ['Quantity and Unit are required. AccuracyError and ' ...
                 'Resolution must be finite, nonnegative numbers.']);
        end

        Quantity(k) = quantityValue;
        Unit(k) = unitValue;
        AccuracyError(k) = accuracyValue;
        Resolution(k) = resolutionValue;
    end
    settings = table(Channel, Quantity, Unit, AccuracyError, Resolution);
end


function settings = normalizeChannelSettings(settings)
    if ~istable(settings) || height(settings) == 0
        error('ME395:InvalidChannelSettings', ...
            'labOptions.ChannelSettings must be a nonempty table.');
    end

    channelName = findColumn(settings, {'Channel', 'SourceColumn', 'Column'});
    quantityName = findOptionalColumn(settings, {'Quantity', 'OutputQuantity', 'Name'});
    unitName = findColumn(settings, {'Unit', 'Units'});
    accuracyName = findColumn(settings, ...
        {'AccuracyError', 'Accuracy Error', 'AccuracyUncertainty', 'ea'});
    resolutionName = findColumn(settings, ...
        {'Resolution', 'SmallestIncrement', 'InstrumentResolution'});

    Channel = strtrim(string(settings.(channelName)));
    if isempty(quantityName)
        Quantity = Channel;
    else
        Quantity = strtrim(string(settings.(quantityName)));
    end
    Unit = strtrim(string(settings.(unitName)));
    AccuracyError = numericColumn(settings.(accuracyName), accuracyName);
    Resolution = numericColumn(settings.(resolutionName), resolutionName);

    if any(missingText(Channel) | missingText(Quantity) | missingText(Unit))
        error('ME395:MissingChannelSettingText', ...
            'Channel, Quantity, and Unit must not be blank.');
    end
    if any(~isfinite(AccuracyError) | AccuracyError < 0 | ...
            ~isfinite(Resolution) | Resolution < 0)
        error('ME395:InvalidChannelSettingNumber', ...
            'AccuracyError and Resolution must be finite and nonnegative.');
    end
    settings = table(Channel, Quantity, Unit, AccuracyError, Resolution);
end


function columnName = findOptionalColumn(dataTable, aliases)
    names = dataTable.Properties.VariableNames;
    normalizedNames = cellfun(@normalizeName, names, 'UniformOutput', false);
    normalizedAliases = cellfun(@normalizeName, aliases, 'UniformOutput', false);
    matches = find(ismember(normalizedNames, normalizedAliases));
    if isempty(matches)
        columnName = '';
        return
    end
    if numel(matches) > 1
        error('ME395:AmbiguousColumn', ...
            'More than one column matches: %s.', strjoin(names(matches), ', '));
    end
    columnName = names{matches};
end


function unit = inferUnit(channelName)
    token = regexp(char(channelName), '\(([^)]*)\)', 'tokens', 'once');
    if ~isempty(token)
        unit = string(token{1});
    elseif contains(lower(channelName), "temp") || ...
            contains(lower(channelName), "thermocouple")
        unit = "degC";
    else
        unit = "";
    end
end


function text = numberText(value)
    if isfinite(value)
        text = string(sprintf('%.15g', value));
    else
        text = "Unavailable";
    end
end


function raw = readInputTable(inputFile)
    try
        raw = readtable(inputFile, 'VariableNamingRule', 'preserve');
    catch firstError
        % VariableNamingRule is unavailable in older MATLAB releases.
        try
            raw = readtable(inputFile);
        catch
            rethrow(firstError)
        end
    end
end


function columnName = findColumn(dataTable, aliases)
    names = dataTable.Properties.VariableNames;
    normalizedNames = cellfun(@normalizeName, names, 'UniformOutput', false);
    normalizedAliases = cellfun(@normalizeName, aliases, 'UniformOutput', false);
    matches = find(ismember(normalizedNames, normalizedAliases));
    if isempty(matches)
        error('ME395:MissingColumn', ...
            'Required column missing. Accepted names: %s.', strjoin(aliases, ', '));
    end
    if numel(matches) > 1
        error('ME395:AmbiguousColumn', ...
            'More than one column matches: %s.', strjoin(names(matches), ', '));
    end
    columnName = names{matches};
end


function normalized = normalizeName(name)
    normalized = lower(regexprep(char(name), '[^a-zA-Z0-9]', ''));
end


function values = numericColumn(column, columnName)
    if isnumeric(column) || islogical(column)
        values = double(column);
        return
    end

    if iscell(column)
        values = nan(size(column));
        for row = 1:numel(column)
            item = column{row};
            if isempty(item)
                continue
            elseif (isnumeric(item) || islogical(item)) && isscalar(item)
                values(row) = double(item);
            else
                itemText = string(item);
                if numel(itemText) ~= 1 || missingText(itemText)
                    continue
                end
                values(row) = str2double(itemText);
                if isnan(values(row))
                    error('ME395:NonNumericValue', ...
                        'Column "%s" contains nonnumeric data in row %d.', ...
                        columnName, row + 1);
                end
            end
        end
        return
    end

    textValues = string(column);
    blank = missingText(textValues);
    values = str2double(textValues);
    invalid = isnan(values) & ~blank;
    if any(invalid)
        badRows = find(invalid);
        error('ME395:NonNumericValue', ...
            'Column "%s" contains nonnumeric data in row(s): %s', ...
            columnName, rowList(badRows));
    end
    values(blank) = NaN;
end


function tf = missingText(values)
    tf = ismissing(values) | strlength(strtrim(values)) == 0;
end


function value = oneNumericSetting(values, settingName, quantityName)
    if any(isinf(values))
        error('ME395:InvalidSetting', ...
            '%s must be finite for Quantity "%s".', settingName, quantityName);
    end
    values = values(~isnan(values));
    if isempty(values)
        error('ME395:MissingSetting', ...
            '%s is missing for Quantity "%s".', settingName, quantityName);
    end

    reference = values(1);
    tolerance = max(1, abs(reference)) * 100 * eps;
    if any(abs(values - reference) > tolerance)
        error('ME395:InconsistentSetting', ...
            '%s is inconsistent within Quantity "%s".', settingName, quantityName);
    end
    value = reference;
end


function value = oneTextSetting(values, settingName, quantityName)
    values = strtrim(values(~missingText(values)));
    values = unique(values, 'stable');
    if isempty(values)
        error('ME395:MissingSetting', ...
            '%s is missing for Quantity "%s".', settingName, quantityName);
    end
    if numel(values) > 1
        error('ME395:InconsistentSetting', ...
            '%s is inconsistent within Quantity "%s".', settingName, quantityName);
    end
    value = values(1);
end


function value = rss3(a, b, c)
    value = sqrt(a^2 + b^2 + c^2);
end


function label = dominantSource(accuracy, precision, resolution)
    contributions = [accuracy, precision, resolution];
    labels = ["Accuracy", "Precision", "Resolution"];
    largest = max(contributions);
    tolerance = max(1, largest) * 100 * eps;
    tied = abs(contributions - largest) <= tolerance;
    label = strjoin(labels(tied), " + ");
end


function [roundedValue, roundedError, valueText, errorText] = ...
        roundForReport(value, uncertainty, significantDigits)
    if uncertainty < 0 || ~isfinite(uncertainty)
        error('ME395:InvalidUncertainty', ...
            'Uncertainty must be a finite, nonnegative number.');
    end

    if uncertainty == 0
        roundedValue = value;
        roundedError = 0;
        valueText = sprintf('%.15g', value);
        errorText = '0';
        return
    end

    place = floor(log10(abs(uncertainty))) - significantDigits + 1;
    step = 10^place;
    roundedError = roundHalfToEven(uncertainty, step);

    % A value such as 9.96 can round to 10, changing the reporting place.
    adjustedPlace = floor(log10(abs(roundedError))) - significantDigits + 1;
    if adjustedPlace ~= place
        place = adjustedPlace;
        step = 10^place;
        roundedError = roundHalfToEven(uncertainty, step);
    end

    roundedValue = roundHalfToEven(value, step);
    decimalPlaces = max(0, -place);
    valueText = sprintf(['%.' num2str(decimalPlaces) 'f'], roundedValue);
    errorText = sprintf(['%.' num2str(decimalPlaces) 'f'], roundedError);
end


function rounded = roundHalfToEven(value, step)
    scaled = value / step;
    signValue = sign(scaled);
    absoluteScaled = abs(scaled);
    lowerInteger = floor(absoluteScaled);
    fraction = absoluteScaled - lowerInteger;
    tolerance = 8 * eps(max(1, absoluteScaled));

    if fraction > 0.5 + tolerance
        roundedInteger = lowerInteger + 1;
    elseif fraction < 0.5 - tolerance
        roundedInteger = lowerInteger;
    elseif mod(lowerInteger, 2) == 0
        roundedInteger = lowerInteger;
    else
        roundedInteger = lowerInteger + 1;
    end

    rounded = signValue * roundedInteger * step;
    if rounded == 0
        rounded = 0; % Avoid displaying negative zero.
    end
end


function method = buildMethodTable(significantDigits)
    metric = [
        "Average"
        "StandardDeviation"
        "StandardDeviationOfMean"
        "AccuracyError"
        "PrecisionErrorSingle"
        "PrecisionErrorMean"
        "ResolutionError"
        "FinalUncertaintySingle"
        "FinalUncertaintyMean"
        "FinalReport"
        "Outliers"
        ];

    definition = [
        "mean of repeated readings"
        "sample standard deviation using N-1"
        "StandardDeviation/sqrt(N)"
        "absolute value supplied from calibration, documentation, or course instructions; not reduced by N"
        "2*StandardDeviation (approximately 95% confidence)"
        "2*StandardDeviationOfMean (approximately 95% confidence)"
        "Resolution/2"
        "sqrt(AccuracyError^2 + PrecisionErrorSingle^2 + ResolutionError^2)"
        "sqrt(AccuracyError^2 + PrecisionErrorMean^2 + ResolutionError^2)"
        sprintf(['Average +/- FinalUncertaintyMean; uncertainty has %d ' ...
            'significant digit(s), and average is rounded to the same place'], ...
            significantDigits)
        "none removed automatically"
        ];

    method = table(metric, definition, 'VariableNames', {'Metric', 'Definition'});
end


function writeResults(results, method, sourceMetadata, outputFile)
    try
        writetable(results, outputFile, 'Sheet', 'Summary', ...
            'WriteMode', 'overwritesheet');
        writetable(method, outputFile, 'Sheet', 'Method', ...
            'WriteMode', 'overwritesheet');
        writetable(sourceMetadata, outputFile, 'Sheet', 'SourceMetadata', ...
            'WriteMode', 'overwritesheet');
    catch firstError
        % Fall back for MATLAB releases that predate WriteMode=overwritesheet.
        try
            writetable(results, outputFile, 'Sheet', 'Summary');
            writetable(method, outputFile, 'Sheet', 'Method');
            writetable(sourceMetadata, outputFile, 'Sheet', 'SourceMetadata');
        catch
            rethrow(firstError)
        end
    end
end


function pathText = canonicalPath(pathText)
    fileObject = java.io.File(pathText);
    pathText = char(fileObject.getCanonicalPath());
end


function tf = isBlankPath(value)
    if isstring(value)
        tf = isempty(value) || all(ismissing(value) | ...
            strlength(strtrim(value)) == 0);
    elseif ischar(value)
        tf = isempty(strtrim(value));
    else
        tf = isempty(value);
    end
end


function text = rowList(rows)
    % Add one because row 1 of the worksheet contains the variable names.
    worksheetRows = rows(:)' + 1;
    text = strtrim(sprintf('%d ', worksheetRows));
end

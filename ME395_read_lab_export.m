function [data, headers, lines, headerRow, importInfo] = ME395_read_lab_export(inputFile, options)
% Read a rectangular numeric LabVIEW text export without assuming captions.
% Overrides: Delimiter, HeaderRow (0 for none), DataStartRow (1-based).
% Text/binary, mixed tables, and changing schemas require format-specific import.
    if nargin < 2, options = struct(); end
    content = fileread(inputFile);
    content = erase(string(content), char(65279));
    lines = split(regexprep(content, '\r\n?', '\n'), newline);
    delimiters = {char(9), ',', ';', 'whitespace'};
    if isfield(options, 'Delimiter')
        delimiters = {char(options.Delimiter)};
    end
    startRow = [];
    delimiter = '';
    for d = 1:numel(delimiters)
        candidateDelimiter = delimiters{d};
        if isfield(options, 'DataStartRow')
            candidates = options.DataStartRow;
            validateattributes(candidates, {'numeric'}, ...
                {'scalar','integer','positive','<=',numel(lines)});
        else
            candidates = 1:numel(lines);
        end
        for r = candidates
            fields = splitFields(lines(r), candidateDelimiter);
            if ~numericFields(fields), continue; end
            following = r + 1;
            while following <= numel(lines) && strlength(strtrim(lines(following))) == 0
                following = following + 1;
            end
            if isfield(options, 'DataStartRow') || ...
                    (following <= numel(lines) && ...
                    numel(splitFields(lines(following), candidateDelimiter)) == numel(fields) && ...
                    numericFields(splitFields(lines(following), candidateDelimiter)))
                startRow = r;
                delimiter = candidateDelimiter;
                break
            end
        end
        if ~isempty(startRow), break; end
    end
    if isempty(startRow)
        error('ME395:LabDataMissing', ['No numeric table detected. Set labOptions.Delimiter, ' ...
            'HeaderRow and DataStartRow for an unfamiliar text layout. Binary LabVIEW files are unsupported.']);
    end
    width = numel(splitFields(lines(startRow), delimiter));
    headerRow = 0;
    if isfield(options, 'HeaderRow')
        headerRow = options.HeaderRow;
        validateattributes(headerRow, {'numeric'}, ...
            {'scalar','integer','nonnegative','<',startRow});
    else
        % Metadata may contain delimiters: use the closest matching text row.
        for r = startRow-1:-1:1
            fields = splitFields(lines(r), delimiter);
            if numel(fields) == width && any(strlength(fields) > 0) && ...
                    all(isnan(str2double(fields))) && ~any(contains(fields, '='))
                headerRow = r;
                break
            end
        end
    end
    if headerRow > 0
        originalHeaders = splitFields(lines(headerRow), delimiter);
        if numel(originalHeaders) ~= width
            error('ME395:LabHeaderWidth', 'Header line %d does not match the %d data columns.', headerRow, width);
        end
    else
        originalHeaders = strings(width, 1);
    end
    if headerRow > 0 && ~(isfield(options, 'HeaderRow') && isfield(options, 'DataStartRow'))
        for r = headerRow+1:startRow-1
            if strlength(strtrim(lines(r))) > 0
                error('ME395:AmbiguousLabPreamble', ...
                    'Unexpected content at line %d between header and data. Set HeaderRow/DataStartRow explicitly after checking the file.', r);
            end
        end
    end
    headers = originalHeaders;
    for c = 1:width
        if strlength(headers(c)) == 0, headers(c) = "Column" + c; end
    end
    headers = string(matlab.lang.makeUniqueStrings(cellstr(headers), {}, namelengthmax));
    headers = headers(:);
    data = nan(numel(lines)-startRow+1, width);
    count = 0;
    repeatedHeaders = 0;
    for r = startRow:numel(lines)
        if strlength(strtrim(lines(r))) == 0, continue; end
        fields = splitFields(lines(r), delimiter);
        if headerRow > 0 && isequal(fields, originalHeaders)
            repeatedHeaders = repeatedHeaders + 1;
            continue
        end
        if numel(fields) ~= width
            error('ME395:MalformedLabData', ...
                'Line %d has %d fields; expected %d. A changed schema or another table needs separate import.', r, numel(fields), width);
        end
        if ~numericFields(fields)
            error('ME395:InvalidLabData', ...
                'Line %d contains missing, nonfinite, or nonnumeric values. No readings were discarded.', r);
        end
        count = count + 1;
        data(count,:) = str2double(fields)';
    end
    data = data(1:count,:);
    importInfo = struct('Delimiter', string(delimiter), 'DataStartRow', startRow, ...
        'OriginalHeaders', originalHeaders, 'RepeatedHeadersSkipped', repeatedHeaders);
end

function fields = splitFields(line, delimiter)
    if strcmp(delimiter, 'whitespace')
        fields = string(regexp(char(strtrim(line)), '\s+', 'split'))';
    else
        % Split only outside quotes; preserve empty fields and escaped quotes.
        pattern = [regexptranslate('escape', delimiter) '(?=(?:[^"]*"[^"]*")*[^"]*$)'];
        fields = string(regexp(char(line), pattern, 'split'))';
    end
    fields = strtrim(fields);
    quoted = startsWith(fields, '"') & endsWith(fields, '"') & strlength(fields) >= 2;
    fields(quoted) = extractBetween(fields(quoted), 2, strlength(fields(quoted))-1);
    fields = strtrim(replace(fields, '""', '"'));
end

function yes = numericFields(fields)
    tokens = regexp(cellstr(fields), '^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$', 'once');
    yes = all(~cellfun('isempty', tokens)) && all(isfinite(str2double(fields)));
end

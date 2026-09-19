function test_ME395_import(sampleFolder)
% Run with test_ME395_import or provide the folder containing the five exports.
    folder = tempname;
    mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
    tab = char(9);
    check("Title\nPeak =\t26.2\tResolution =\t0.2\nTime (s)\tStrain\n\n0\t1e-6\n1\t2e-6", ...
        [0 1e-6;1 2e-6], ["Time (s)";"Strain"]);
    check('"Clock","Signal, A","Signal, A",""\n0,2,3,4\n1,5,6,7', ...
        [0 2 3 4;1 5 6 7], ["Clock";"Signal, A";"Signal, A_1";"Column4"]);
    check("t;A;B\n0;1;2\n1;3;4", [0 1 2;1 3 4], ["t";"A";"B"]);
    check("x y\n1 2\n3 4", [1 2;3 4], ["x";"y"]);
    check("1\t2\n3\t4", [1 2;3 4], ["Column1";"Column2"]);
    check("Signal\n1\n2\nSignal\n3", [1;2;3], "Signal");
    reject("Time\tSignal\n0\t1\n1\t2\n2\t", 'ME395:InvalidLabData');
    reject("Time\tSignal\n0\t1\n1\t2\n2\t3\t4", 'ME395:MalformedLabData');
    reject("Time\tSignal\n0\t1\n1\t2\n2\tNaN", 'ME395:InvalidLabData');
    reject("Time\tSignal\n0\tBAD\n1\t2\n2\t3", 'ME395:AmbiguousLabPreamble');
    reject("Time\tSignal\n0\t1\n1\t2\nfooter", 'ME395:MalformedLabData');
    path = fixture("Clock\tA\nseconds\tvolts\n0\t1\n1\t2");
    options = struct('HeaderRow',1,'DataStartRow',3,'Delimiter',tab);
    [data, headers] = ME395_read_lab_export(path, options);
    assert(isequal(data,[0 1;1 2]) && isequal(headers,["Clock";"A"]));
    options.TimeColumn = "Clock";
    options.TimeRange = [0 1];
    options.ChannelSettings = table("A", "Test", "V", 0.1, 0.01, ...
        'VariableNames', {'Channel','Quantity','Unit','AccuracyError','Resolution'});
    result = ME395_uncertainty_analysis(path, fullfile(folder,'override.xlsx'),1,options);
    assert(result.N == 2 && result.Average == 1.5);
    assert(width(result) == 18 && contains(result.ErrorSummary, 'Dominant:'));
    assert(~ismember('DominantErrorSource',result.Properties.VariableNames));
    % Original structured workbook path still uses the same calculations.
    source = table(["Test";"Test"], ["V";"V"], [1;2], [.1;.1], [.01;.01], ...
        'VariableNames', {'Quantity','Unit','Measurement','AccuracyError','Resolution'});
    excel = fullfile(folder,'source.xlsx'); writetable(source,excel);
    other = ME395_uncertainty_analysis(excel,fullfile(folder,'excel.xlsx'));
    assert(other.FinalUncertaintyMean == result.FinalUncertaintyMean);
    assert(other.ErrorSummary == result.ErrorSummary);
    % Scaled report must survive export without changing numeric-column units.
    source.Unit(:) = "m";
    source.Measurement(:) = 12.34e-6;
    source.AccuracyError(:) = .56e-6;
    source.Resolution(:) = 0;
    writetable(source,excel);
    scaledOutput = fullfile(folder,'scaled.xlsx');
    scaled = ME395_uncertainty_analysis(excel,scaledOutput);
    assert(scaled.FinalReport == "12.3 ± 0.6 µm" && scaled.Unit == "m");
    assert(abs(scaled.RoundedAverage-12.3e-6) < 1e-18);
    savedScaled = readtable(scaledOutput,'Sheet','Summary','TextType','string');
    assert(savedScaled.FinalReport == scaled.FinalReport && savedScaled.Unit == "m");
    if nargin > 0
        names = ["6inch_5kHz", "6inch_5kHz_1Mass", "6inch_5kHz_2Mass", ...
            "6inch_5kHz_3Mass", "6inch_5kHz_4Mass"];
        for name = names
            path = fullfile(sampleFolder,name);
            [data,headers,~,headerRow] = ME395_read_lab_export(path);
            assert(headerRow == 5 && isequal(headers,["Time (s)";"Strain"]));
            options = struct('TimeRange',[min(data(:,1)) max(data(:,1))]);
            % Test values only; not instrument specifications.
            options.ChannelSettings = table("Strain","Strain","strain",1e-6,1e-7, ...
                'VariableNames', {'Channel','Quantity','Unit','AccuracyError','Resolution'});
            output = fullfile(folder,name + ".xlsx");
            result = ME395_uncertainty_analysis(path,output,1,options);
            assert(result.N == size(data,1));
            assert(abs(result.Average-mean(data(:,2))) < 1e-14);
            expected = sqrt(1e-12 + (2*std(data(:,2))/sqrt(size(data,1)))^2 + (5e-8)^2);
            assert(abs(result.FinalUncertaintyMean-expected) < 1e-14);
            saved = readtable(output,'Sheet','Summary');
            assert(width(saved) == 18 && ismember('ErrorSummary',saved.Properties.VariableNames));
            fprintf('PASS %s (%d readings)\n',name,result.N);
        end
    end
    fprintf('All importer and analysis regression checks passed.\n');

    function path = fixture(content)
        path = fullfile(folder,'fixture.txt');
        content = replace(string(content), '\n', newline);
        content = replace(content, '\t', tab);
        fid = fopen(path,'w');
        closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid,'%s',content);
    end
    function check(content,expected,expectedHeaders)
        [actual,headers] = ME395_read_lab_export(fixture(content));
        assert(isequal(actual,expected));
        assert(isequal(headers,expectedHeaders));
    end
    function reject(content,expectedId)
        try
            ME395_read_lab_export(fixture(content));
        catch exception
            assert(strcmp(exception.identifier,expectedId),exception.message);
            return
        end
        error('Expected rejection: %s',expectedId);
    end
end

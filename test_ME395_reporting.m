function test_ME395_reporting
% Physical equivalence and rounding checks across display units.
    check(12.34e-6, 0.56e-6, "m", 1, "12.3 ± 0.6 µm", 12.3e-6, .6e-6);
    check(.01234, .00056, "m", 1, "12.3 ± 0.6 mm", .0123, .0006);
    check(.01234, .00056, "mm", 1, "12.3 ± 0.6 µm", .0123, .0006);
    check(12.34e-6, .56e-6, "strain", 2, "12.34 ± 0.56 µstrain", 12.34e-6, .56e-6);
    check(-12.34e-6, .56e-6, "V", 1, "-12.3 ± 0.6 µV", -12.3e-6, .6e-6);
    check(23.456, .12, "degC", 1, "23.5 ± 0.1 degC", 23.5, .1);
    check(12.34e-6, .56e-6, "degC", 1, "(12.3 ± 0.6) × 10^-6 degC", 12.3e-6, .6e-6);
    check(12.34e-6, .56e-6, "degF", 1, "(12.3 ± 0.6) × 10^-6 degF", 12.3e-6, .6e-6);
    check(12.34e-6, .56e-6, "custom", 1, "(12.3 ± 0.6) × 10^-6 custom", 12.3e-6, .6e-6);
    check(0, 0, "m", 1, "0 ± 0 m", 0, 0);
    check(0, .56e-6, "m", 1, "0 ± 600 nm", 0, .6e-6);
    check(12e-6, 0, "m", 1, "12 ± 0 µm", 12e-6, 0);
    check(12340, 560, "m", 1, "12.3 ± 0.6 km", 12300, 600);
    [report,v,u] = ME395_format_report(10e-6,.5,"m",1);
    assert(v == 0 && u == .5);
    assert(contains(report,"unrounded mean: 1e-05 m"));
    % Verify SI prefixes are case-sensitive, and pre-scaled units are converted.
    check(12.34, .56, "µm", 1, "12.3 ± 0.6 µm", 12.3, .6);
    check(.01234, .00056, "MV", 1, "12.3 ± 0.6 kV", .0123, .0006);
    fprintf('All automatic unit reporting checks passed.\n');
end

function check(value, errorValue, unit, digits, expected, expectedValue, expectedError)
    [actual,v,u] = ME395_format_report(value,errorValue,unit,digits);
    assert(actual == expected, 'Expected "%s", got "%s"', expected, actual);
    assert(abs(v-expectedValue) <= 1e-12*max(abs(expectedValue),realmin));
    assert(abs(u-expectedError) <= 1e-12*max(abs(expectedError),realmin));
end

# ME 395 MATLAB uncertainty analyzer

This MATLAB workflow accepts the native tab-delimited files produced by common ME 395 lab acquisition programs. It also retains support for the earlier structured `.xls` and `.xlsx` input format.

## Quick start with a native lab file

1. Open this folder in MATLAB.
2. Run `ME395_uncertainty_live.m`.
3. Select the lab export. Files without an extension are supported.
4. Choose the measurement channel or channels to analyze.
5. Choose a nominally steady time interval.
6. Enter the unit, absolute accuracy error, and instrument resolution for each selected channel.
7. MATLAB displays the results and creates `<input-name>_uncertainty_results.xlsx` beside the source file.

The source file is not changed.

## Native lab export format

The attached thermocouple example has this structure:

```text
Thermocouple Voltage Experiment
9/10/2026 3:14:08 PM
Sample Rate (Hz) = 1.00
Time (s)    Voltage (V)    Thermocouple    CJC Thermistor Voltage (V)    CJC Temp    TC Voltage Std. Dev. (V)    TC Voltage Variance (V)

0.00        5.9811E-4      14.99           9.9223E-4                      24.80       2.8987E-6                  8.4022E-12
1.00        5.9818E-4      14.99           9.9225E-4                      24.80       3.0257E-6                  9.1547E-12
```

The visible gaps between fields are tab characters. The importer automatically detects:

- Experiment title
- Recording date and time
- Sample rate
- Channel header row
- Time column
- Numeric data rows

Time is used to select an interval and is not analyzed as a measurement channel.

## Why the time interval matters

The supplied thermocouple file changes from about 15 degC to about 65 degC. Those values are not nominally identical repeated measurements. Calculating one standard deviation across the full heating run would combine actual temperature change with measurement noise.

Choose a time interval where the measured quantity is reasonably steady when the goal is to estimate precision uncertainty. The selected start and end times are stored in the output workbook's `SourceMetadata` sheet.

## Instrument information requested by the dialogs

The raw lab export contains measurements but normally does not contain the instrument accuracy and resolution needed for the final uncertainty calculation. For each selected channel, the program asks for:

- `Quantity`: the name that should appear in the output.
- `Unit`: the unit shared by the measurements and errors.
- `AccuracyError`: absolute accuracy error from calibration, a datasheet, or course instructions.
- `Resolution`: the smallest recorded increment, not half of it.

For example, if a temperature channel has accuracy +/-0.5 degC and records to the nearest 0.01 degC, enter:

```text
Unit:          degC
AccuracyError: 0.5
Resolution:    0.01
```

The program calculates the resolution error as `Resolution/2`.

## Repeatable noninteractive analysis

For repeated analysis of the same export layout, specify the time range and channel settings in `ME395_uncertainty_live.m`:

The numerical accuracy and resolution values below are illustrative. Replace them with verified values for the instrument and channel being analyzed.

```matlab
labOptions.TimeRange = [0 10]; % Example only; choose a steady interval.
labOptions.ChannelSettings = table( ...
    "Thermocouple", "Thermocouple temperature", "degC", 0.5, 0.01, ...
    'VariableNames', {'Channel','Quantity','Unit', ...
    'AccuracyError','Resolution'});
```

Multiple channels can be listed as additional table rows:

```matlab
labOptions.ChannelSettings = table( ...
    ["Thermocouple"; "CJC Temp"], ...
    ["Thermocouple temperature"; "CJC temperature"], ...
    ["degC"; "degC"], ...
    [0.5; 0.2], ...
    [0.01; 0.01], ...
    'VariableNames', {'Channel','Quantity','Unit', ...
    'AccuracyError','Resolution'});
```

`Channel` must match a header in the source file. `Quantity` is the label used in the results.

## Calculations

For each selected channel with `N` readings in the selected interval, the program calculates:

```text
average                      = mean(readings)
standard deviation           = sample std. dev. using N - 1
standard deviation of mean   = standard deviation / sqrt(N)
precision error, one reading = 2 * standard deviation
precision error, mean        = 2 * standard deviation / sqrt(N)
resolution error             = resolution / 2
final uncertainty, mean      = sqrt(accuracy^2 + precision_mean^2 + resolution_error^2)
```

The final report uses the average and its uncertainty. Accuracy and resolution errors are not divided by `sqrt(N)`. No outliers are removed automatically.

## Output workbook

The output workbook contains:

- `Summary`: complete numerical results, error-source contributions, dominant error source, and the formatted final report.
- `Method`: formulas and reporting conventions.
- `SourceMetadata`: experiment title, source path, sample rate, selected channels, selected time interval, and row counts.

The default final report rounds uncertainty to one significant digit and rounds the average to the same decimal place. Use `2` as the third function argument when two significant digits are appropriate.

## Structured Excel input remains supported

The original long-form workbook format can still be used. The first worksheet must contain:

| Quantity | Unit | Measurement | AccuracyError | Resolution |
|---|---|---:|---:|---:|
| Temperature | degC | 31.6 | 0.5 | 0.1 |
| Temperature | degC | 32.1 | 0.5 | 0.1 |
| Temperature | degC | 31.8 | 0.5 | 0.1 |

Call the analyzer directly if desired:

```matlab
[results, info] = ME395_uncertainty_analysis('my_data.xls');
```

## Scope

The program handles directly measured quantities with uncorrelated accuracy, precision, and resolution contributions. It does not propagate uncertainty through a derived formula, determine slope uncertainty, calculate covariance, or decide whether a measurement is an outlier.

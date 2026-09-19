# ME 395 MATLAB uncertainty analyzer

This MATLAB workflow calculates measurement uncertainty from numeric LabVIEW text exports, including extensionless files. It supports tab, comma, semicolon, and whitespace delimiters, as well as the earlier structured `.xls` and `.xlsx` input format. Final reports automatically scale supported units for readable values.

IMPORTANT NOTICE: This tool is completely developed and implemented using Codex. Versions are to be updated at varying frequency. Make sure you always check the code and understand the commands before using the output for actual usage.!

## Files and workflow

Keep these MATLAB files together in the current folder or on the MATLAB path:

| File | Responsibility |
|---|---|
| `ME395_uncertainty_live.m` | Entry script: sets options, calls the analysis function, and displays results and the output path. |
| `ME395_uncertainty_analysis.m` | Collects settings, calculates uncertainty, builds the results table, and writes the Excel workbook. |
| `ME395_read_lab_export.m` | Detects and validates the numeric text table and processes its column captions. |
| `ME395_format_report.m` | Scales display units and rounds the final report while returning rounded numeric values in the input unit. |
| `test_ME395_import.m` | Import, calculation, and workbook regression checks. |
| `test_ME395_reporting.m` | Unit scaling and reporting regression checks. |

The live script processes one selected file per run; it does not continuously acquire data from LabVIEW. It calls the analysis function, which uses the importer for text files and the formatter for final reports.

## Quick start with a native lab file

1. Open this folder in MATLAB.
2. Run `ME395_uncertainty_live.m`.
3. Select the lab export. Files without an extension are supported.
4. Choose a nominally steady time interval.
5. Choose the measurement channel or channels to analyze.
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

The visible gaps between fields are tab characters. The importer detects the numeric table, a matching caption row, and a time column when its normalized caption starts with `time`. The first two nonblank preamble lines are stored as the experiment title and recording time; these are positional labels, not semantic recognition of arbitrary metadata. A `Sample Rate ... = ...` entry is extracted when present, and the full preamble is retained.

Time is used to select an interval and is not analyzed as a measurement channel.

`ME395_read_lab_export.m` locates consecutive numeric rows first, then finds the nearest matching caption row. Tab-separated metadata such as `Peak frequency ... Resolution ...` is therefore not mistaken for the header. Captions and column counts are not hardcoded. Supported delimiters are tab, comma, semicolon, and whitespace; quoted delimited fields and scientific notation are supported. Empty captions become `Column1`, etc.; duplicate captions receive unique suffixes. Exact repeated header rows and blank lines are skipped. Original and processed captions, preamble, detected line numbers, and skipped-header count are recorded in `SourceMetadata`.

The five supplied `6inch_5kHz*` vibration exports contain this preamble pattern:

```text
Vibration Test
9/17/2026 3:10:38 PM
Sample Rate (Hz) = 5000.00
Peak frequency (Hz) =    26.2    Resolution (Hz) =    0.2
Time (s)    Strain

0.0000    -2.6725E-6
0.0002    -1.9927E-6
```

The old importer assumed that the first tab-separated line was the header, causing `textscan` to attempt to parse `Time (s)` as a number. The numeric-table detection fixes this layout. The frequency resolution in the preamble is metadata; it is not automatically used as the instrument resolution for the strain channel.

Unfamiliar text layouts can be configured explicitly (line numbers are one-based):

```matlab
labOptions.Delimiter = char(9); % Or ',', ';', 'whitespace', or another delimiter
labOptions.HeaderRow = 5;      % 0 for a table without captions
labOptions.DataStartRow = 7;   % First measurement row
labOptions.TimeColumn = 1;     % Column number, processed caption, or 0 for row index
```

Use both `HeaderRow` and `DataStartRow` to intentionally skip separate unit rows or other text between captions and measurements. Without a recognized time caption, interval selection uses a zero-based row index; use `TimeColumn` to identify a differently named time axis. `ChannelSettings.Channel` matches the processed caption shown in the selection dialog.

Automatic detection expects one rectangular numeric table, with at least two consecutive numeric rows. A missing/nonfinite/nonnumeric value, unexpected footer, or changed column count within the data raises an error with the source line number; readings are not silently dropped. Ambiguous metadata, multiple tables, units rows, or unusual captions may require explicit overrides. Decimal-comma numbers, multiline quoted fields, mixed text/numeric measurement tables, binary TDMS files, and arbitrary LabVIEW formats require a dedicated importer or export to supported numeric text. No automatic parser can infer every possible LabVIEW output format.

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

`Channel` must uniquely match a processed caption, including any generated suffix for duplicate captions. `Quantity` is the label used in the results.

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

## Displayed results and output workbook

The live script first displays four columns: `Quantity`, `SourceColumn`, `FinalReport`, and `ErrorSummary`. It then displays the complete results table and the workbook path.

The complete table contains these 18 columns, in order:

```text
Quantity
SourceColumn
Unit
N
Average
StandardDeviation
StandardDeviationOfMean
AccuracyError
PrecisionErrorSingle
PrecisionErrorMean
Resolution
ResolutionError
FinalUncertaintySingle
FinalUncertaintyMean
ErrorSummary
RoundedAverage
RoundedFinalUncertainty
FinalReport
```

The output workbook contains:

- `Summary`: 18 columns containing the numerical results and formatted final report. One `ErrorSummary` column replaces the three contribution-percentage columns and `DominantErrorSource`, for example `Accuracy: 60%; Precision: 30%; Resolution: 10%; Dominant: Accuracy`. Percentages use squared contributions to the uncertainty of the mean and display up to six significant digits; dominant-source ties are retained. When all errors are zero, all percentages are zero; with fewer than two readings they are unavailable.
- `Method`: formulas and reporting conventions.
- `SourceMetadata`: experiment title, source path, sample rate, selected channels, selected time interval, and row counts.

The default final report rounds uncertainty to one significant digit and rounds the average to the same decimal place. Use `2` as the third function argument when two significant digits are appropriate.

### Automatic reporting units

`FinalReport` scales the mean and uncertainty together using the larger magnitude. For example, `0.00001234 ± 0.00000056 m` becomes `12.3 ± 0.6 µm` with one uncertainty significant digit. Length can switch between nm, µm, mm, m, km, etc.; prefixed input units such as mm are recognized. Common SI symbols (including V, A, K, Pa, N, Hz, s) and strain/microstrain are supported. SI symbols are case-sensitive.

Celsius and Fahrenheit retain their original temperature scale: ordinary temperatures stay in degC/degF, and very small values use a shared scientific multiplier, such as `(12.3 ± 0.6) × 10^-6 degC`. Unknown or compound units likewise use scientific notation for very small or large values instead of guessing a conversion. The program does not infer whether a temperature is absolute or a temperature difference.

All numeric columns, including `RoundedAverage` and `RoundedFinalUncertainty`, remain in the original `Unit`; only the self-contained `FinalReport` changes display units. Continue entering accuracy and resolution in the same original unit as the measurements. Scaling does not change relative uncertainty. If an uncertainty is so large that a nonzero mean rounds to zero, the report also includes the unrounded mean and identifies that the uncertainty exceeds its magnitude. For example, an uncertainty of `0.5 m` does not become `0.5 µm` merely because the readings are small.

Run `test_ME395_reporting` to verify unit switching, temperature handling, rounding, zero values, and preservation of the original numerical units.

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

## Regression checks

Run both test suites in MATLAB:

```matlab
test_ME395_reporting
test_ME395_import
```

The reporting suite checks small and large values, negative and zero means, prefixed input units, case-sensitive SI symbols, temperature formatting, and a mean lost to rounding. The import suite checks delimiter/header/error handling, structured workbook input, and preservation of scaled report strings and original numeric units in Excel.

To also validate the five vibration exports, pass the folder containing them (adjust the path for your computer):

```matlab
test_ME395_import('C:\Users\Kawa11_Admin\Downloads')
```

Tests use illustrative instrument errors, verify calculations and the exported summary, and remove their temporary workbooks. These error values are not instrument specifications.

## Changes on 2026-09-19

- Replaced the first-tab-line header assumption with numeric-table detection, caption processing, explicit layout overrides, and source-line diagnostics.
- Verified import and analysis of all five supplied vibration files, each containing 25,001 readings.
- Combined three contribution-percentage columns and the dominant-source column into `ErrorSummary`, reducing the result table from 21 to 18 columns.
- Added automatic final-report unit scaling, scientific notation for temperature and unknown units, and an unrounded-mean note when uncertainty rounds a nonzero mean to zero.
- Verified reporting and import regressions in MATLAB, including saved Excel output with converted report units and unchanged numerical-column units.

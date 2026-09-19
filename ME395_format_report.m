function [report, roundedValue, roundedError] = ME395_format_report(value, uncertainty, unit, significantDigits)
% Automatically scale display only; returned numeric values retain input units.
    validateattributes(value, {'numeric'}, {'scalar','real','finite'});
    validateattributes(uncertainty, {'numeric'}, {'scalar','real','finite','nonnegative'});
    validateattributes(significantDigits, {'numeric'}, {'scalar','integer','>=',1,'<=',2});
    unit = strtrim(string(unit));
    [baseUnit, inputFactor, scalable] = unitDefinition(unit);
    magnitude = max(abs(value), uncertainty);
    factor = 1;
    displayUnit = unit;
    exponent = 0;
    if scalable && magnitude > 0
        baseMagnitude = magnitude * inputFactor;
        targetExponent = 3 * floor(log10(baseMagnitude)/3);
        if targetExponent >= -24 && targetExponent <= 24
            exponents = -24:3:24;
            prefixes = ["y","z","a","f","p","n","µ","m","","k","M","G","T","P","E","Z","Y"];
            factor = inputFactor / 10^targetExponent;
            displayUnit = prefixes(exponents == targetExponent) + baseUnit;
        else
            scalable = false;
        end
    end
    if ~scalable && magnitude > 0 && (magnitude < 0.01 || magnitude >= 1e4)
        exponent = 3 * floor(log10(magnitude)/3);
        factor = 10^(-exponent);
    end
    [scaledValue, scaledError, valueText, errorText] = ...
        roundForReport(value*factor, uncertainty*factor, significantDigits);
    roundedValue = scaledValue / factor;
    roundedError = scaledError / factor;
    if exponent ~= 0
        report = string(sprintf('(%s %c %s) × 10^%d %s', ...
            valueText, char(177), errorText, exponent, char(displayUnit)));
    else
        report = string(sprintf('%s %c %s %s',valueText,char(177),errorText,char(displayUnit)));
    end
    report = strtrim(report);
    if value ~= 0 && scaledValue == 0
        report = report + string(sprintf(' [unrounded mean: %.6g %s; uncertainty exceeds mean magnitude]', ...
            value, char(unit)));
    end
end

function [base, factor, scalable] = unitDefinition(unit)
    % Case-sensitive SI symbols: m (milli) and M (mega) are different.
    % Affine temperature scales (degC/degF) and unknown units use scientific
    % notation, never a guessed physical conversion or a prefix on Celsius.
    unit = replace(unit, "μ", "µ");
    aliases = ["meter","meters","metre","metres","micron","microns", ...
        "microstrain","µstrain","ustrain","ε","µε","uε"];
    canonical = ["m","m","m","m","µm","µm", ...
        "µstrain","µstrain","µstrain","strain","µstrain","µstrain"];
    match = find(unit == aliases,1);
    if ~isempty(match), unit = canonical(match); end
    bases = ["m","s","V","A","K","Pa","N","Hz","W","J","Ohm","ohm","Ω","F","H","strain"];
    prefixes = ["","y","z","a","f","p","n","u","µ","m","c","d","da","h","k","M","G","T","P","E","Z","Y"];
    powers = [0,-24,-21,-18,-15,-12,-9,-6,-6,-3,-2,-1,1,2,3,6,9,12,15,18,21,24];
    base = unit; factor = 1; scalable = false;
    for b = bases
        for k = 1:numel(prefixes)
            if unit == prefixes(k) + b
                base = b; factor = 10^powers(k); scalable = true;
                return
            end
        end
    end
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



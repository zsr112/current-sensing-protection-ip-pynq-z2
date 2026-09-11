Set-StrictMode -Version Latest

$script:Stage1ECanonicalJsonInterface = 'stage1e-runtime-canonical-json-interface-v1'
$script:Stage1ESha256ProviderInterface =
    'stage1e-runtime-sha256-provider-interface-v1'
$script:Stage1EMaxJsonDepth = 64
$script:Stage1EStrictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:Stage1EUtf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Stage1ECanonicalJsonInterfaceVersion {
    return $script:Stage1ECanonicalJsonInterface
}

function Get-Stage1ESha256ProviderInterfaceVersion {
    return $script:Stage1ESha256ProviderInterface
}

function Throw-Stage1EJsonError {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context
    )

    throw [System.IO.InvalidDataException]::new(
        "$Message (character offset $($Context.Index)).")
}

function Skip-Stage1EJsonWhitespace {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)

    while ($Context.Index -lt $Context.Length) {
        $code = [int][char]$Context.Text[$Context.Index]
        if ($code -ne 0x20 -and $code -ne 0x09 -and
            $code -ne 0x0a -and $code -ne 0x0d) {
            break
        }
        $Context.Index++
    }
}

function Test-Stage1EHexCharacter {
    param([Parameter(Mandatory = $true)][char]$Character)

    $code = [int]$Character
    return (($code -ge 0x30 -and $code -le 0x39) -or
        ($code -ge 0x41 -and $code -le 0x46) -or
        ($code -ge 0x61 -and $code -le 0x66))
}

function Read-Stage1EJsonUnicodeEscape {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)

    if (($Context.Index + 4) -gt $Context.Length) {
        Throw-Stage1EJsonError 'Truncated Unicode escape' $Context
    }
    $value = 0
    for ($index = 0; $index -lt 4; $index++) {
        $character = [char]$Context.Text[$Context.Index]
        if (-not (Test-Stage1EHexCharacter $character)) {
            Throw-Stage1EJsonError 'Invalid Unicode escape' $Context
        }
        $code = [int]$character
        if ($code -ge 0x30 -and $code -le 0x39) {
            $digit = $code - 0x30
        }
        elseif ($code -ge 0x41 -and $code -le 0x46) {
            $digit = $code - 0x41 + 10
        }
        else {
            $digit = $code - 0x61 + 10
        }
        $value = ($value * 16) + $digit
        $Context.Index++
    }
    return $value
}

function Read-Stage1EJsonString {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)

    if ($Context.Text[$Context.Index] -ne '"') {
        Throw-Stage1EJsonError 'Expected JSON string' $Context
    }
    $Context.Index++
    $builder = [System.Text.StringBuilder]::new()

    while ($Context.Index -lt $Context.Length) {
        $character = [char]$Context.Text[$Context.Index]
        $Context.Index++
        if ($character -eq '"') {
            return $builder.ToString()
        }
        if ($character -eq '\') {
            if ($Context.Index -ge $Context.Length) {
                Throw-Stage1EJsonError 'Truncated JSON escape' $Context
            }
            $escape = [char]$Context.Text[$Context.Index]
            $Context.Index++
            $escapeCode = [int]$escape
            if ($escapeCode -eq 0x22) {
                $null = $builder.Append('"')
            }
            elseif ($escapeCode -eq 0x5c) {
                $null = $builder.Append('\')
            }
            elseif ($escapeCode -eq 0x2f) {
                $null = $builder.Append('/')
            }
            elseif ($escapeCode -eq 0x62) {
                $null = $builder.Append([char]0x08)
            }
            elseif ($escapeCode -eq 0x66) {
                $null = $builder.Append([char]0x0c)
            }
            elseif ($escapeCode -eq 0x6e) {
                $null = $builder.Append([char]0x0a)
            }
            elseif ($escapeCode -eq 0x72) {
                $null = $builder.Append([char]0x0d)
            }
            elseif ($escapeCode -eq 0x74) {
                $null = $builder.Append([char]0x09)
            }
            elseif ($escapeCode -eq 0x75) {
                $unit = Read-Stage1EJsonUnicodeEscape $Context
                if ($unit -ge 0xd800 -and $unit -le 0xdbff) {
                    if (($Context.Index + 2) -gt $Context.Length -or
                        $Context.Text[$Context.Index] -ne '\' -or
                        $Context.Text[$Context.Index + 1] -ne 'u') {
                        Throw-Stage1EJsonError 'High surrogate lacks a low surrogate' $Context
                    }
                    $Context.Index += 2
                    $low = Read-Stage1EJsonUnicodeEscape $Context
                    if ($low -lt 0xdc00 -or $low -gt 0xdfff) {
                        Throw-Stage1EJsonError 'Invalid low surrogate' $Context
                    }
                    $null = $builder.Append([char]$unit)
                    $null = $builder.Append([char]$low)
                }
                elseif ($unit -ge 0xdc00 -and $unit -le 0xdfff) {
                    Throw-Stage1EJsonError 'Unpaired low surrogate' $Context
                }
                else {
                    $null = $builder.Append([char]$unit)
                }
            }
            else {
                Throw-Stage1EJsonError 'Unknown JSON escape' $Context
            }
            continue
        }

        $code = [int]$character
        if ($code -lt 0x20) {
            Throw-Stage1EJsonError 'Unescaped JSON control character' $Context
        }
        if ($code -ge 0xd800 -and $code -le 0xdbff) {
            if ($Context.Index -ge $Context.Length) {
                Throw-Stage1EJsonError 'Unpaired high surrogate' $Context
            }
            $lowCharacter = [char]$Context.Text[$Context.Index]
            $lowCode = [int]$lowCharacter
            if ($lowCode -lt 0xdc00 -or $lowCode -gt 0xdfff) {
                Throw-Stage1EJsonError 'Unpaired high surrogate' $Context
            }
            $null = $builder.Append($character)
            $null = $builder.Append($lowCharacter)
            $Context.Index++
            continue
        }
        if ($code -ge 0xdc00 -and $code -le 0xdfff) {
            Throw-Stage1EJsonError 'Unpaired low surrogate' $Context
        }
        $null = $builder.Append($character)
    }
    Throw-Stage1EJsonError 'Unterminated JSON string' $Context
}

function Read-Stage1EJsonInteger {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)

    $start = $Context.Index
    $negative = $false
    if ($Context.Text[$Context.Index] -eq '-') {
        $negative = $true
        $Context.Index++
        if ($Context.Index -ge $Context.Length) {
            Throw-Stage1EJsonError 'Truncated JSON number' $Context
        }
    }

    $first = [char]$Context.Text[$Context.Index]
    if ($first -eq '0') {
        $Context.Index++
        if ($negative) {
            Throw-Stage1EJsonError 'Negative zero is not supported' $Context
        }
        if ($Context.Index -lt $Context.Length) {
            $next = [int][char]$Context.Text[$Context.Index]
            if ($next -ge 0x30 -and $next -le 0x39) {
                Throw-Stage1EJsonError 'Leading zero in JSON number' $Context
            }
        }
    }
    else {
        $firstCode = [int]$first
        if ($firstCode -lt 0x31 -or $firstCode -gt 0x39) {
            Throw-Stage1EJsonError 'Invalid JSON number' $Context
        }
        while ($Context.Index -lt $Context.Length) {
            $code = [int][char]$Context.Text[$Context.Index]
            if ($code -lt 0x30 -or $code -gt 0x39) {
                break
            }
            $Context.Index++
        }
    }

    if ($Context.Index -lt $Context.Length) {
        $suffix = [char]$Context.Text[$Context.Index]
        if ($suffix -eq '.' -or $suffix -eq 'e' -or $suffix -eq 'E') {
            Throw-Stage1EJsonError 'Only canonical integers are supported' $Context
        }
    }
    $lexeme = $Context.Text.Substring($start, $Context.Index - $start)
    $number = 0L
    if (-not [long]::TryParse(
            $lexeme,
            [System.Globalization.NumberStyles]::AllowLeadingSign,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$number)) {
        Throw-Stage1EJsonError 'JSON integer is outside the Int64 range' $Context
    }
    return $number
}

function Read-Stage1EJsonLiteral {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][string]$Literal,
        [Parameter(Mandatory = $true)][bool]$Value
    )

    if (($Context.Index + $Literal.Length) -gt $Context.Length -or
        $Context.Text.Substring($Context.Index, $Literal.Length) -cne $Literal) {
        Throw-Stage1EJsonError "Invalid JSON literal; expected $Literal" $Context
    }
    $Context.Index += $Literal.Length
    return $Value
}

function Read-Stage1EJsonArray {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][int]$Depth
    )

    $Context.Index++
    $items = [System.Collections.Generic.List[object]]::new()
    Skip-Stage1EJsonWhitespace $Context
    if ($Context.Index -lt $Context.Length -and
        $Context.Text[$Context.Index] -eq ']') {
        $Context.Index++
        Write-Output -NoEnumerate ([object[]]$items.ToArray())
        return
    }

    while ($true) {
        $items.Add((Read-Stage1EJsonValue $Context $Depth))
        Skip-Stage1EJsonWhitespace $Context
        if ($Context.Index -ge $Context.Length) {
            Throw-Stage1EJsonError 'Unterminated JSON array' $Context
        }
        $separator = [char]$Context.Text[$Context.Index]
        $Context.Index++
        if ($separator -eq ']') {
            Write-Output -NoEnumerate ([object[]]$items.ToArray())
            return
        }
        if ($separator -ne ',') {
            Throw-Stage1EJsonError 'Expected comma or closing bracket' $Context
        }
        Skip-Stage1EJsonWhitespace $Context
    }
}

function Read-Stage1EJsonObject {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][int]$Depth
    )

    $Context.Index++
    $record = [ordered]@{}
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    Skip-Stage1EJsonWhitespace $Context
    if ($Context.Index -lt $Context.Length -and
        $Context.Text[$Context.Index] -eq '}') {
        $Context.Index++
        return $record
    }

    while ($true) {
        if ($Context.Index -ge $Context.Length -or
            $Context.Text[$Context.Index] -ne '"') {
            Throw-Stage1EJsonError 'Expected JSON object property' $Context
        }
        $name = Read-Stage1EJsonString $Context
        if (-not $names.Add($name)) {
            Throw-Stage1EJsonError "Duplicate JSON property '$name'" $Context
        }
        Skip-Stage1EJsonWhitespace $Context
        if ($Context.Index -ge $Context.Length -or
            $Context.Text[$Context.Index] -ne ':') {
            Throw-Stage1EJsonError 'Expected colon after JSON property' $Context
        }
        $Context.Index++
        Skip-Stage1EJsonWhitespace $Context
        $record.Add($name, (Read-Stage1EJsonValue $Context $Depth))
        Skip-Stage1EJsonWhitespace $Context
        if ($Context.Index -ge $Context.Length) {
            Throw-Stage1EJsonError 'Unterminated JSON object' $Context
        }
        $separator = [char]$Context.Text[$Context.Index]
        $Context.Index++
        if ($separator -eq '}') {
            return $record
        }
        if ($separator -ne ',') {
            Throw-Stage1EJsonError 'Expected comma or closing brace' $Context
        }
        Skip-Stage1EJsonWhitespace $Context
    }
}

function Read-Stage1EJsonValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][int]$Depth
    )

    if ($Depth -gt $script:Stage1EMaxJsonDepth) {
        Throw-Stage1EJsonError 'JSON nesting exceeds the supported limit' $Context
    }
    Skip-Stage1EJsonWhitespace $Context
    if ($Context.Index -ge $Context.Length) {
        Throw-Stage1EJsonError 'Unexpected end of JSON input' $Context
    }
    $character = [char]$Context.Text[$Context.Index]
    switch ([int]$character) {
        0x7b { return Read-Stage1EJsonObject $Context ($Depth + 1) }
        0x5b { return Read-Stage1EJsonArray $Context ($Depth + 1) }
        0x22 { return Read-Stage1EJsonString $Context }
        0x74 { return Read-Stage1EJsonLiteral $Context 'true' $true }
        0x66 { return Read-Stage1EJsonLiteral $Context 'false' $false }
        0x6e { Throw-Stage1EJsonError 'JSON null is not supported' $Context }
        default {
            $code = [int]$character
            if ($character -eq '-' -or ($code -ge 0x30 -and $code -le 0x39)) {
                return Read-Stage1EJsonInteger $Context
            }
            Throw-Stage1EJsonError 'Unexpected JSON token' $Context
        }
    }
}

function ConvertFrom-Stage1ECanonicalJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xef -and
        $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
        throw [System.IO.InvalidDataException]::new('UTF-8 BOM is prohibited.')
    }
    try {
        $text = $script:Stage1EStrictUtf8.GetString($Bytes)
    }
    catch {
        throw [System.IO.InvalidDataException]::new(
            'Input is not valid UTF-8.', $_.Exception)
    }
    $context = [ordered]@{ Text = $text; Index = 0; Length = $text.Length }
    $value = Read-Stage1EJsonValue $context 0
    Skip-Stage1EJsonWhitespace $context
    if ($context.Index -ne $context.Length) {
        Throw-Stage1EJsonError 'Trailing data after JSON value' $context
    }
    if ($value -isnot [System.Collections.IDictionary]) {
        throw [System.IO.InvalidDataException]::new(
            'The Stage 1E JSON document root must be an object.')
    }
    return $value
}

function Read-Stage1EJsonFileBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    return [System.IO.File]::ReadAllBytes($LiteralPath)
}

function Get-Stage1EDictionaryValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Dictionary,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not $Dictionary.Contains($Key)) {
        throw [System.IO.InvalidDataException]::new("Missing object property '$Key'.")
    }
    return $Dictionary[$Key]
}

function Resolve-Stage1EJsonSchema {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$RootSchema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry
    )

    if (-not $Schema.Contains('$ref')) {
        return [pscustomobject]@{ Schema = $Schema; Root = $RootSchema }
    }
    $reference = [string]$Schema['$ref']
    $hashIndex = $reference.IndexOf('#')
    if ($hashIndex -lt 0) {
        $documentId = $reference
        $fragment = ''
    }
    else {
        $documentId = $reference.Substring(0, $hashIndex)
        $fragment = $reference.Substring($hashIndex + 1)
    }
    if ([string]::IsNullOrEmpty($documentId)) {
        $targetRoot = $RootSchema
    }
    else {
        if (-not $SchemaRegistry.Contains($documentId)) {
            throw [System.IO.InvalidDataException]::new(
                "Schema reference document is not loaded: $documentId")
        }
        $targetRoot = $SchemaRegistry[$documentId]
    }
    $target = $targetRoot
    if (-not [string]::IsNullOrEmpty($fragment)) {
        if (-not $fragment.StartsWith('/')) {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported schema reference fragment: $reference")
        }
        foreach ($rawPart in $fragment.Substring(1).Split('/')) {
            $part = $rawPart.Replace('~1', '/').Replace('~0', '~')
            if ($target -isnot [System.Collections.IDictionary] -or
                -not $target.Contains($part)) {
                throw [System.IO.InvalidDataException]::new(
                    "Unresolved schema reference: $reference")
            }
            $target = $target[$part]
        }
    }
    if ($target -isnot [System.Collections.IDictionary]) {
        throw [System.IO.InvalidDataException]::new(
            "Schema reference does not select an object: $reference")
    }
    return [pscustomobject]@{ Schema = $target; Root = $targetRoot }
}

function Test-Stage1EIntegralValue {
    param([Parameter(Mandatory = $true)]$Value)

    return ($Value -is [sbyte] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64])
}

function Test-Stage1EJsonValueEqual {
    param($Left, $Right)

    if ($null -eq $Left -or $null -eq $Right) {
        return ($null -eq $Left -and $null -eq $Right)
    }
    if ($Left -is [System.Collections.IDictionary] -and
        $Right -is [System.Collections.IDictionary]) {
        if ($Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) {
            if (-not $Right.Contains([string]$key) -or
                -not (Test-Stage1EJsonValueEqual $Left[$key] $Right[$key])) {
                return $false
            }
        }
        return $true
    }
    $leftArray = ($Left -is [System.Collections.IList] -and
        $Left -isnot [string])
    $rightArray = ($Right -is [System.Collections.IList] -and
        $Right -isnot [string])
    if ($leftArray -or $rightArray) {
        if (-not $leftArray -or -not $rightArray -or
            $Left.Count -ne $Right.Count) { return $false }
        for ($index = 0; $index -lt $Left.Count; $index++) {
            if (-not (Test-Stage1EJsonValueEqual $Left[$index] $Right[$index])) {
                return $false
            }
        }
        return $true
    }
    if ((Test-Stage1EIntegralValue $Left) -and
        (Test-Stage1EIntegralValue $Right)) {
        return ([int64]$Left -eq [int64]$Right)
    }
    if ($Left.GetType() -ne $Right.GetType()) { return $false }
    return ($Left -ceq $Right)
}

function Test-Stage1ECanonicalSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Length -ne 64 -or $Value -ceq ('0' * 64)) { return $false }
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if (-not (($code -ge 0x30 -and $code -le 0x39) -or
                ($code -ge 0x61 -and $code -le 0x66))) {
            return $false
        }
    }
    return $true
}

function Test-Stage1ECanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.IndexOf('\') -ge 0) { return $false }
    foreach ($forbidden in @('*', '?', '[', ']')) {
        if ($Value.IndexOf($forbidden) -ge 0) { return $false }
    }
    foreach ($character in $Value.ToCharArray()) {
        if ([int]$character -lt 0x20) { return $false }
    }

    if ($Value.StartsWith('//')) {
        $segments = @($Value.Substring(2).Split('/'))
        if ($segments.Count -lt 2) { return $false }
    }
    elseif ($Value.StartsWith('/')) {
        $segments = @($Value.Substring(1).Split('/'))
    }
    else {
        if ($Value.Length -lt 3 -or $Value[1] -ne ':' -or
            $Value[2] -ne '/') {
            return $false
        }
        $drive = [int][char]$Value[0]
        if ($drive -lt 0x41 -or $drive -gt 0x5a) { return $false }
        $segments = @($Value.Substring(3).Split('/'))
    }
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or
            $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.IndexOf(':') -ge 0) {
            return $false
        }
    }
    return $true
}

function Assert-Stage1EStringFormat {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Format,
        [Parameter(Mandatory = $true)][string]$Path
    )

    switch ($Format) {
        'sha256' {
            if (-not (Test-Stage1ECanonicalSha256 $Value)) {
                throw [System.IO.InvalidDataException]::new(
                    "$Path is not a lowercase non-placeholder SHA-256 value.")
            }
        }
        'canonical-absolute-path' {
            if (-not (Test-Stage1ECanonicalPath $Value)) {
                throw [System.IO.InvalidDataException]::new(
                    "$Path is not a canonical absolute path.")
            }
        }
        { $_ -in @('token', 'message', 'canonical-reference') } {
            foreach ($character in $Value.ToCharArray()) {
                if ([int]$character -eq 0) {
                    throw [System.IO.InvalidDataException]::new(
                        "$Path contains a prohibited NUL character.")
                }
            }
            if ($Format -eq 'canonical-reference' -and
                $Value.IndexOf('\') -ge 0) {
                throw [System.IO.InvalidDataException]::new(
                    "$Path contains a non-canonical backslash.")
            }
        }
        default {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported Stage 1E string format '$Format' at $Path.")
        }
    }
}

function Select-Stage1EOneOfSchema {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$RootSchema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @($Schema.oneOf)) {
        try {
            $null = Assert-Stage1EJsonSchemaValue -Value $Value -Schema $candidate `
                -RootSchema $RootSchema -SchemaRegistry $SchemaRegistry `
                -Path $Path -OmitProperty ''
            $matches.Add($candidate)
        }
        catch {
            continue
        }
    }
    if ($matches.Count -ne 1) {
        throw [System.IO.InvalidDataException]::new(
            "$Path matches $($matches.Count) oneOf branches; exactly one is required.")
    }
    return $matches[0]
}

function Assert-Stage1EJsonSchemaValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$RootSchema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry,
        [string]$Path = '$',
        [string]$OmitProperty = ''
    )

    if ($null -eq $Value) {
        throw [System.IO.InvalidDataException]::new("$Path must not be null.")
    }
    $resolved = Resolve-Stage1EJsonSchema $Schema $RootSchema $SchemaRegistry
    $Schema = $resolved.Schema
    $RootSchema = $resolved.Root

    if ($Schema.Contains('oneOf')) {
        $selected = Select-Stage1EOneOfSchema $Value $Schema $RootSchema `
            $SchemaRegistry $Path
        Assert-Stage1EJsonSchemaValue -Value $Value -Schema $selected `
            -RootSchema $RootSchema -SchemaRegistry $SchemaRegistry `
            -Path $Path -OmitProperty $OmitProperty
        return $true
    }

    if ($Schema.Contains('type')) {
        $type = [string]$Schema.type
        switch ($type) {
            'object' {
                if ($Value -isnot [System.Collections.IDictionary]) {
                    throw [System.IO.InvalidDataException]::new("$Path must be an object.")
                }
                if (-not $Schema.Contains('properties') -or
                    -not $Schema.Contains('required') -or
                    -not $Schema.Contains('x-stage1e-canonical-order') -or
                    -not $Schema.Contains('additionalProperties') -or
                    [bool]$Schema.additionalProperties) {
                    throw [System.IO.InvalidDataException]::new(
                        "$Path uses an incomplete exact-object schema.")
                }
                $order = @($Schema['x-stage1e-canonical-order'])
                $required = @($Schema.required)
                $expected = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal)
                foreach ($nameValue in $order) {
                    $name = [string]$nameValue
                    if (-not $expected.Add($name) -or
                        -not $Schema.properties.Contains($name)) {
                        throw [System.IO.InvalidDataException]::new(
                            "$Path has invalid canonical-order metadata.")
                    }
                }
                if ($expected.Count -ne $Schema.properties.Count) {
                    throw [System.IO.InvalidDataException]::new(
                        "$Path canonical order is incomplete.")
                }
                foreach ($nameValue in $required) {
                    $name = [string]$nameValue
                    $isOmitted = ($Path -eq '$' -and
                        -not [string]::IsNullOrEmpty($OmitProperty) -and
                        $name -ceq $OmitProperty)
                    if (-not $isOmitted -and -not $Value.Contains($name)) {
                        throw [System.IO.InvalidDataException]::new(
                            "$Path is missing required property '$name'.")
                    }
                }
                foreach ($keyValue in $Value.Keys) {
                    $key = [string]$keyValue
                    if (-not $expected.Contains($key)) {
                        throw [System.IO.InvalidDataException]::new(
                            "$Path contains unknown property '$key'.")
                    }
                    if ($Path -eq '$' -and $key -ceq $OmitProperty) {
                        throw [System.IO.InvalidDataException]::new(
                            "$Path identity payload must omit '$key'.")
                    }
                }
                foreach ($nameValue in $order) {
                    $name = [string]$nameValue
                    if ($Value.Contains($name)) {
                        Assert-Stage1EJsonSchemaValue -Value $Value[$name] `
                            -Schema $Schema.properties[$name] `
                            -RootSchema $RootSchema -SchemaRegistry $SchemaRegistry `
                            -Path "$Path.$name" -OmitProperty ''
                    }
                }
            }
            'array' {
                if ($Value -isnot [System.Collections.IList] -or
                    $Value -is [string] -or
                    $Value -is [System.Collections.IDictionary]) {
                    throw [System.IO.InvalidDataException]::new("$Path must be an array.")
                }
                if ($Schema.Contains('minItems') -and
                    $Value.Count -lt [int64]$Schema.minItems) {
                    throw [System.IO.InvalidDataException]::new("$Path has too few items.")
                }
                if ($Schema.Contains('maxItems') -and
                    $Value.Count -gt [int64]$Schema.maxItems) {
                    throw [System.IO.InvalidDataException]::new("$Path has too many items.")
                }
                if ($Schema.Contains('items')) {
                    for ($index = 0; $index -lt $Value.Count; $index++) {
                        Assert-Stage1EJsonSchemaValue -Value $Value[$index] `
                            -Schema $Schema.items -RootSchema $RootSchema `
                            -SchemaRegistry $SchemaRegistry -Path "$Path[$index]" `
                            -OmitProperty ''
                    }
                }
                if ($Schema.Contains('uniqueItems') -and
                    [bool]$Schema.uniqueItems) {
                    for ($left = 0; $left -lt $Value.Count; $left++) {
                        for ($right = $left + 1; $right -lt $Value.Count; $right++) {
                            if (Test-Stage1EJsonValueEqual $Value[$left] $Value[$right]) {
                                throw [System.IO.InvalidDataException]::new(
                                    "$Path contains duplicate array items.")
                            }
                        }
                    }
                }
            }
            'string' {
                if ($Value -isnot [string]) {
                    throw [System.IO.InvalidDataException]::new("$Path must be a string.")
                }
                if ($Schema.Contains('minLength') -and
                    $Value.Length -lt [int64]$Schema.minLength) {
                    throw [System.IO.InvalidDataException]::new("$Path is too short.")
                }
                if ($Schema.Contains('maxLength') -and
                    $Value.Length -gt [int64]$Schema.maxLength) {
                    throw [System.IO.InvalidDataException]::new("$Path is too long.")
                }
                if ($Schema.Contains('x-stage1e-format')) {
                    Assert-Stage1EStringFormat $Value `
                        ([string]$Schema['x-stage1e-format']) $Path
                }
            }
            'integer' {
                if (-not (Test-Stage1EIntegralValue $Value)) {
                    throw [System.IO.InvalidDataException]::new("$Path must be an integer.")
                }
                $integer = [int64]$Value
                if ($Schema.Contains('minimum') -and
                    $integer -lt [int64]$Schema.minimum) {
                    throw [System.IO.InvalidDataException]::new("$Path is below its minimum.")
                }
                if ($Schema.Contains('maximum') -and
                    $integer -gt [int64]$Schema.maximum) {
                    throw [System.IO.InvalidDataException]::new("$Path exceeds its maximum.")
                }
            }
            'boolean' {
                if ($Value -isnot [bool]) {
                    throw [System.IO.InvalidDataException]::new("$Path must be a boolean.")
                }
            }
            default {
                throw [System.IO.InvalidDataException]::new(
                    "Unsupported schema type '$type' at $Path.")
            }
        }
    }

    if ($Schema.Contains('const') -and
        -not (Test-Stage1EJsonValueEqual $Value $Schema.const)) {
        throw [System.IO.InvalidDataException]::new("$Path does not match its constant.")
    }
    if ($Schema.Contains('enum')) {
        $found = $false
        foreach ($candidate in @($Schema.enum)) {
            if (Test-Stage1EJsonValueEqual $Value $candidate) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            throw [System.IO.InvalidDataException]::new("$Path is not an allowed enum value.")
        }
    }
    return $true
}

function Add-Stage1ECanonicalString {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $null = $Builder.Append('"')
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = [char]$Value[$index]
        $code = [int]$character
        $escaped = $true
        switch ($code) {
            0x22 { $null = $Builder.Append('\"') }
            0x5c { $null = $Builder.Append('\\') }
            0x08 { $null = $Builder.Append('\b') }
            0x0c { $null = $Builder.Append('\f') }
            0x0a { $null = $Builder.Append('\n') }
            0x0d { $null = $Builder.Append('\r') }
            0x09 { $null = $Builder.Append('\t') }
            default { $escaped = $false }
        }
        if ($escaped) { continue }
        if ($code -lt 0x20 -or $code -eq 0x7f -or
            $code -eq 0x2028 -or $code -eq 0x2029) {
            $null = $Builder.Append(('\u{0:x4}' -f $code))
            continue
        }
        if ($code -ge 0xd800 -and $code -le 0xdbff) {
            if (($index + 1) -ge $Value.Length) {
                throw [System.IO.InvalidDataException]::new(
                    'Cannot encode an unpaired high surrogate.')
            }
            $low = [int][char]$Value[$index + 1]
            if ($low -lt 0xdc00 -or $low -gt 0xdfff) {
                throw [System.IO.InvalidDataException]::new(
                    'Cannot encode an unpaired high surrogate.')
            }
            $null = $Builder.Append($character)
            $null = $Builder.Append([char]$low)
            $index++
            continue
        }
        if ($code -ge 0xdc00 -and $code -le 0xdfff) {
            throw [System.IO.InvalidDataException]::new(
                'Cannot encode an unpaired low surrogate.')
        }
        $null = $Builder.Append($character)
    }
    $null = $Builder.Append('"')
}

function Add-Stage1ECanonicalValue {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$RootSchema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$OmitProperty
    )

    $resolved = Resolve-Stage1EJsonSchema $Schema $RootSchema $SchemaRegistry
    $Schema = $resolved.Schema
    $RootSchema = $resolved.Root
    if ($Schema.Contains('oneOf')) {
        $Schema = Select-Stage1EOneOfSchema $Value $Schema $RootSchema `
            $SchemaRegistry $Path
        $resolved = Resolve-Stage1EJsonSchema $Schema $RootSchema $SchemaRegistry
        $Schema = $resolved.Schema
        $RootSchema = $resolved.Root
    }
    $type = [string]$Schema.type
    switch ($type) {
        'object' {
            $null = $Builder.Append('{')
            $first = $true
            foreach ($nameValue in @($Schema['x-stage1e-canonical-order'])) {
                $name = [string]$nameValue
                if ($Path -eq '$' -and $name -ceq $OmitProperty) { continue }
                if (-not $first) { $null = $Builder.Append(',') }
                $first = $false
                Add-Stage1ECanonicalString $Builder $name
                $null = $Builder.Append(':')
                Add-Stage1ECanonicalValue $Builder $Value[$name] `
                    $Schema.properties[$name] $RootSchema $SchemaRegistry `
                    "$Path.$name" ''
            }
            $null = $Builder.Append('}')
        }
        'array' {
            $null = $Builder.Append('[')
            for ($index = 0; $index -lt $Value.Count; $index++) {
                if ($index -ne 0) { $null = $Builder.Append(',') }
                if ($Schema.Contains('items')) {
                    $itemSchema = $Schema.items
                }
                elseif ($Schema.Contains('const')) {
                    $itemSchema = [ordered]@{ type = 'string' }
                }
                else {
                    throw [System.IO.InvalidDataException]::new(
                        "Array schema at $Path has no item contract.")
                }
                Add-Stage1ECanonicalValue $Builder $Value[$index] $itemSchema `
                    $RootSchema $SchemaRegistry "$Path[$index]" ''
            }
            $null = $Builder.Append(']')
        }
        'string' { Add-Stage1ECanonicalString $Builder ([string]$Value) }
        'integer' {
            $null = $Builder.Append(([int64]$Value).ToString(
                    [System.Globalization.CultureInfo]::InvariantCulture))
        }
        'boolean' {
            if ([bool]$Value) { $null = $Builder.Append('true') }
            else { $null = $Builder.Append('false') }
        }
        default {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported canonical type '$type' at $Path.")
        }
    }
}

function ConvertTo-Stage1ECanonicalJsonBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry,
        [string]$OmitProperty = ''
    )

    $null = Assert-Stage1EJsonSchemaValue -Value $Value -Schema $Schema `
        -RootSchema $Schema -SchemaRegistry $SchemaRegistry -Path '$' `
        -OmitProperty $OmitProperty
    $builder = [System.Text.StringBuilder]::new()
    Add-Stage1ECanonicalValue $builder $Value $Schema $Schema `
        $SchemaRegistry '$' $OmitProperty
    $null = $builder.Append("`n")
    return $script:Stage1EUtf8NoBom.GetBytes($builder.ToString())
}

function Compare-Stage1EBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function ConvertFrom-Stage1ECanonicalJsonEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SchemaRegistry
    )

    $value = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $Bytes
    $canonical = ConvertTo-Stage1ECanonicalJsonBytes -Value $value `
        -Schema $Schema -SchemaRegistry $SchemaRegistry
    if (-not (Compare-Stage1EBytes $Bytes $canonical)) {
        throw [System.IO.InvalidDataException]::new(
            'JSON bytes are valid but are not the Stage 1E canonical representation.')
    }
    return $value
}

function Get-Stage1ESha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $provider = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $provider.ComputeHash($Bytes)
    }
    finally {
        $provider.Dispose()
    }
    $builder = [System.Text.StringBuilder]::new(64)
    foreach ($octet in $digest) {
        $null = $builder.Append($octet.ToString('x2',
                [System.Globalization.CultureInfo]::InvariantCulture))
    }
    return $builder.ToString()
}

function Get-Stage1ECanonicalDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [scriptblock]$DigestProvider
    )

    if ($null -eq $DigestProvider) {
        $value = Get-Stage1ESha256Hex -Bytes $Bytes
    }
    else {
        $value = [string](& $DigestProvider $Bytes)
    }
    if (-not (Test-Stage1ECanonicalSha256 $value)) {
        throw [System.IO.InvalidDataException]::new(
            'Digest provider did not return a canonical SHA-256 value.')
    }
    return $value
}

Export-ModuleMember -Function @(
    'Get-Stage1ECanonicalJsonInterfaceVersion'
    'Get-Stage1ESha256ProviderInterfaceVersion'
    'ConvertFrom-Stage1ECanonicalJsonBytes'
    'ConvertFrom-Stage1ECanonicalJsonEnvelope'
    'ConvertTo-Stage1ECanonicalJsonBytes'
    'Read-Stage1EJsonFileBytes'
    'Assert-Stage1EJsonSchemaValue'
    'Compare-Stage1EBytes'
    'Get-Stage1ESha256Hex'
    'Get-Stage1ECanonicalDigest'
)

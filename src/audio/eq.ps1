#Requires -Version 5.1
<#
    Hardline - cálculo y generación de presets de Equalizer APO.

    Equalizer APO implementa sus filtros como biquads de Robert Bristow-Johnson
    ("Audio EQ Cookbook"). Aquí se reproduce la misma matemática para calcular
    la respuesta combinada de la cadena y fijar el preamp justo para que el
    pico máximo quede por debajo de 0 dBFS.

    Por qué importa: tres peaks de +8/+9/+7 dB solapados en 2-4 kHz no suman
    +9 dB, suman ~+15 dB en el centro. Con un preamp de -4 dB eso clipea en
    cualquier explosión cercana, justo cuando necesitas oír pasos.

    https://www.w3.org/TR/audio-eq-cookbook/
    https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/
#>

function Get-HLBiquad {
    param([Parameter(Mandatory)] $Filter, [double]$SampleRate = 48000)

    $A = [math]::Pow(10, [double]$Filter.gain / 40)
    $w0 = 2 * [math]::PI * [double]$Filter.fc / $SampleRate
    $cs = [math]::Cos($w0)
    $alpha = [math]::Sin($w0) / (2 * [double]$Filter.q)
    $sqA2a = 2 * [math]::Sqrt($A) * $alpha

    switch ($Filter.type) {
        'PK' {
            $b0 = 1 + $alpha * $A; $b1 = -2 * $cs; $b2 = 1 - $alpha * $A
            $a0 = 1 + $alpha / $A; $a1 = -2 * $cs; $a2 = 1 - $alpha / $A
        }
        'LSC' {
            $b0 = $A * (($A + 1) - ($A - 1) * $cs + $sqA2a)
            $b1 = 2 * $A * (($A - 1) - ($A + 1) * $cs)
            $b2 = $A * (($A + 1) - ($A - 1) * $cs - $sqA2a)
            $a0 = ($A + 1) + ($A - 1) * $cs + $sqA2a
            $a1 = -2 * (($A - 1) + ($A + 1) * $cs)
            $a2 = ($A + 1) + ($A - 1) * $cs - $sqA2a
        }
        'HSC' {
            $b0 = $A * (($A + 1) + ($A - 1) * $cs + $sqA2a)
            $b1 = -2 * $A * (($A - 1) + ($A + 1) * $cs)
            $b2 = $A * (($A + 1) + ($A - 1) * $cs - $sqA2a)
            $a0 = ($A + 1) - ($A - 1) * $cs + $sqA2a
            $a1 = 2 * (($A - 1) - ($A + 1) * $cs)
            $a2 = ($A + 1) - ($A - 1) * $cs - $sqA2a
        }
        default { throw "Tipo de filtro no soportado: $($Filter.type)" }
    }
    # Paréntesis obligatorios: en PowerShell la coma tiene más precedencia que "/".
    return @(($b0 / $a0), ($b1 / $a0), ($b2 / $a0), ($a1 / $a0), ($a2 / $a0))
}

# Magnitud en dB de un biquad normalizado a la frecuencia f.
function Get-HLBiquadGainDb {
    param([double[]]$C, [double]$Freq, [double]$SampleRate = 48000)
    $w = 2 * [math]::PI * $Freq / $SampleRate
    $c1 = [math]::Cos($w); $s1 = [math]::Sin($w)
    $c2 = [math]::Cos(2 * $w); $s2 = [math]::Sin(2 * $w)
    # H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
    $nr = $C[0] + $C[1] * $c1 + $C[2] * $c2; $ni = - $C[1] * $s1 - $C[2] * $s2
    $dr = 1 + $C[3] * $c1 + $C[4] * $c2;     $di = - $C[3] * $s1 - $C[4] * $s2
    $mag2 = ($nr * $nr + $ni * $ni) / ($dr * $dr + $di * $di)
    return 10 * [math]::Log10($mag2)
}

<#
    Respuesta combinada en una rejilla logarítmica de 20 Hz a 20 kHz.
    Devuelve el pico, dónde está, y la respuesta en frecuencias de interés.
#>
function Measure-HLFilterChain {
    param([Parameter(Mandatory)] $Filters, [int]$Points = 480, [double]$SampleRate = 48000)

    $coefs = @($Filters | ForEach-Object { , (Get-HLBiquad -Filter $_ -SampleRate $SampleRate) })
    $peak = -999.0; $peakF = 0.0
    $lo = [math]::Log10(20); $hi = [math]::Log10(20000)
    for ($i = 0; $i -lt $Points; $i++) {
        $f = [math]::Pow(10, $lo + ($hi - $lo) * $i / ($Points - 1))
        $g = 0.0
        foreach ($c in $coefs) { $g += Get-HLBiquadGainDb -C $c -Freq $f -SampleRate $SampleRate }
        if ($g -gt $peak) { $peak = $g; $peakF = $f }
    }
    $probe = [ordered]@{}
    foreach ($f in @(60, 100, 180, 320, 1000, 2200, 2800, 3600, 5000, 10000)) {
        $g = 0.0
        foreach ($c in $coefs) { $g += Get-HLBiquadGainDb -C $c -Freq $f -SampleRate $SampleRate }
        $probe["$f"] = [math]::Round($g, 1)
    }
    [pscustomobject]@{ PeakDb = [math]::Round($peak, 2); PeakHz = [int]$peakF; Probe = $probe }
}

# Preamp = -(pico) - margen, redondeado hacia abajo a 0.5 dB.
function Get-HLAutoPreamp {
    param([Parameter(Mandatory)] $Filters, [double]$HeadroomDb = 1.0)
    $m = Measure-HLFilterChain -Filters $Filters
    $pre = - ($m.PeakDb + $HeadroomDb)
    return [math]::Floor($pre * 2) / 2
}

# Equalizer APO lee los .txt como ANSI o UTF-8 según versión: se genera ASCII puro.
function ConvertTo-HLAscii {
    param([string]$Text)
    $norm = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ([int]$ch -lt 128) { [void]$sb.Append($ch) } else { [void]$sb.Append('?') }
    }
    return $sb.ToString()
}

<#
    Escala las ganancias de todos los filtros. 1.0 = preset tal cual.
    0.7 = "moderado": mismas frecuencias y Q, 30% menos de corrección.
#>
function Get-HLScaledFilters {
    param([Parameter(Mandatory)] $Filters, [double]$Intensity = 1.0)
    foreach ($f in $Filters) {
        $o = [ordered]@{ type = $f.type; fc = $f.fc; gain = [math]::Round([double]$f.gain * $Intensity, 1); q = $f.q }
        $why = $f.PSObject.Properties['why']
        if ($why) { $o['why'] = $why.Value }
        [pscustomobject]$o
    }
}

# Cadena completa: corrección del headset (sin escalar) + preset de pasos (escalado).
function Get-HLChainFilters {
    param([Parameter(Mandatory)] $HeadsetProfile, [double]$Intensity = 1.0)
    $corr = @()
    $p = $HeadsetProfile.PSObject.Properties['correction']
    if ($p -and $p.Value) { $corr = @($p.Value) }
    return @($corr + @(Get-HLScaledFilters -Filters $HeadsetProfile.filters -Intensity $Intensity))
}

function ConvertTo-HLEqApoText {
    param([Parameter(Mandatory)] $HeadsetProfile, [string]$Title, [double]$Intensity = 1.0)

    $hp = $HeadsetProfile
    $corr = @()
    $cp = $hp.PSObject.Properties['correction']
    if ($cp -and $cp.Value) { $corr = @($cp.Value) }
    $steps = @(Get-HLScaledFilters -Filters $hp.filters -Intensity $Intensity)
    $all = @($corr + $steps)
    $pre = Get-HLAutoPreamp -Filters $all
    $m = Measure-HLFilterChain -Filters $all
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $line = { param($f) 'Filter: ON {0} Fc {1} Hz Gain {2} dB Q {3}' -f $f.type,
        ([double]$f.fc).ToString('0', $inv), ([double]$f.gain).ToString('0.0', $inv), ([double]$f.q).ToString('0.00', $inv) }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Hardline - $Title")
    [void]$sb.AppendLine(("# Perfil: {0} | intensidad {1}%" -f $hp.name, [int]($Intensity * 100)))
    [void]$sb.AppendLine(("# Pico de la cadena: +{0} dB @ {1} Hz -> preamp automático {2} dB (1 dB de margen)" -f $m.PeakDb.ToString('0.0', $inv), $m.PeakHz, $pre.ToString('0.0', $inv)))
    [void]$sb.AppendLine('# Generado por src/audio/eq.ps1. Edita headsets.json, no este archivo.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Preamp: {0} dB' -f $pre.ToString('0.0', $inv)))
    if ($corr.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("# --- Corrección del headset: $($hp.correctionSource) ---")
        [void]$sb.AppendLine('# Lleva el headset a respuesta neutra antes del preset de pasos.')
        foreach ($f in $corr) { [void]$sb.AppendLine((& $line $f)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('# --- Preset de pasos de Hardline ---')
    }
    foreach ($f in $steps) {
        $why = $f.PSObject.Properties['why']
        if ($why) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("# $($why.Value)") }
        [void]$sb.AppendLine((& $line $f))
    }
    return (ConvertTo-HLAscii $sb.ToString())
}

<#
    Lee un preset generado por ConvertTo-HLEqApoText. Devuelve Name,
    Intensity (0-1.5), Correction (filtros de corrección, sin escalar),
    CorrectionSource y Steps (filtros del preset de pasos, con su comentario
    en "why"). Sin sección de corrección, todos los filtros son del preset.
#>
function ConvertFrom-HLEqPresetText {
    param([Parameter(Mandatory)] [string] $Text)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $lines = @($Text -split '\r?\n')
    $hasCorr = [bool]($lines | Where-Object { $_ -match '^# --- Preset de pasos' })
    $corr = New-Object System.Collections.Generic.List[object]
    $steps = New-Object System.Collections.Generic.List[object]
    $name = ''; $int = 1.0; $src = ''; $why = $null
    $inSteps = -not $hasCorr
    foreach ($l in $lines) {
        if ($l -match '^# Perfil: (.+?) \| intensidad (\d+)%') { $name = $Matches[1]; $int = [int]$Matches[2] / 100.0; continue }
        if ($l -match '^# --- Correcci.n del headset: (.+?) ---') { $src = $Matches[1]; continue }
        if ($l -match '^# --- Preset de pasos') { $inSteps = $true; $why = $null; continue }
        if ($l -match '^\s*Filter:\s*ON\s+(\w+)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB\s+Q\s+([\d.]+)') {
            $f = [ordered]@{ type = $Matches[1]; fc = [double]::Parse($Matches[2], $inv); gain = [double]::Parse($Matches[3], $inv); q = [double]::Parse($Matches[4], $inv) }
            if ($inSteps) { if ($why) { $f['why'] = $why }; $steps.Add([pscustomobject]$f) } else { $corr.Add([pscustomobject]$f) }
            $why = $null
            continue
        }
        if ($inSteps -and $l -match '^#\s+(.+)$' -and $l -notmatch '^# (Hardline|Perfil|Pico|Generado|Lleva)') { $why = $Matches[1] }
    }
    return [pscustomobject]@{ Name = $name; Intensity = $int; Correction = $corr.ToArray(); CorrectionSource = $src; Steps = $steps.ToArray() }
}

<#
    Preset con otra intensidad a partir del preset completo (100%): mismas
    frecuencias y Q, ganancias del preset de pasos escaladas, corrección del
    headset intacta y preamp recalculado para no saturar. Devuelve Text y PreampDb.
#>
function New-HLEqIntensityPreset {
    param([Parameter(Mandatory)] [string] $BaseText, [Parameter(Mandatory)] [double] $Intensity)
    $p = ConvertFrom-HLEqPresetText -Text $BaseText
    if ($p.Steps.Count -eq 0) { throw 'El preset base no tiene filtros de pasos.' }
    # El base debería estar al 100%; si no, se lleva primero a 100%.
    $k = $Intensity / [Math]::Max(0.01, $p.Intensity)
    $text = ConvertTo-HLEqApoText -HeadsetProfile ([pscustomobject]@{ name = $p.Name; filters = $p.Steps; correction = $p.Correction; correctionSource = $p.CorrectionSource }) -Title 'Warzone footsteps' -Intensity $k
    # La cabecera dice la intensidad del escalado ($k); se reescribe con la real.
    $text = $text -replace '\| intensidad \d+%', ('| intensidad {0}%' -f [int][Math]::Round($Intensity * 100))
    $pre = Get-HLAutoPreamp -Filters @(@($p.Correction) + @(Get-HLScaledFilters -Filters $p.Steps -Intensity $k))
    return [pscustomobject]@{ Text = $text; PreampDb = $pre }
}

function Get-HLHeadsetProfiles {
    param([Parameter(Mandatory)] [string] $Root)
    $path = Join-Path $Root 'src\audio\profiles\headsets.json'
    $json = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    return $json
}

# Devuelve el perfil completo (filtros + parámetros de Voicemeeter ya fusionados).
# Con -Correction (AutoEq o archivo propio) el headset queda neutro, así que el
# preset de pasos es el base; del perfil empaquetado solo se hereda Voicemeeter.
function Resolve-HLHeadsetProfile {
    param([Parameter(Mandatory)] $Database, [string]$Id, $Correction)
    $p = $Database.base
    if ($Id -and $Id -ne 'generic') {
        $hit = @($Database.headsets | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
        if ($hit) { $p = $hit }
    }
    $vm = [ordered]@{}
    foreach ($prop in $Database.voicemeeter_defaults.PSObject.Properties) { $vm[$prop.Name] = $prop.Value }
    $over = $p.PSObject.Properties['voicemeeter']
    if ($over) { foreach ($prop in $over.Value.PSObject.Properties) { $vm[$prop.Name] = $prop.Value } }

    if ($Correction) {
        $safeId = ($Correction.Name -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
        return [pscustomobject]@{
            id               = $safeId
            name             = "$($Correction.Name) (corrección $($Correction.Source))"
            filters          = @($Database.base.filters)
            correction       = @($Correction.Filters)
            correctionSource = $Correction.Source
            voicemeeter      = [pscustomobject]$vm
            vmProfileId      = $p.id
            rationale        = "Corrección medida ($($Correction.Source)) + preset de pasos base."
        }
    }
    [pscustomobject]@{
        id               = $p.id
        name             = $p.name
        filters          = @($p.filters)
        correction       = @()
        correctionSource = ''
        voicemeeter      = [pscustomobject]$vm
        vmProfileId      = $p.id
        rationale        = $p.rationale
    }
}

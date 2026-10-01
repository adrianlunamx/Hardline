#Requires -Version 5.1
<#
    Hardline - interruptor del EQ.

    config.txt de Equalizer APO incluye hardline\switch.txt, y switch.txt
    incluye el preset. Activar/desactivar = comentar o descomentar esa única
    línea de switch.txt. Equalizer APO detecta el cambio y recarga al momento,
    sin reiniciar el audio.

    La carpeta config\hardline recibe permiso de escritura para el usuario
    durante la instalación, así que el atajo funciona sin pedir admin.
#>

function Get-HLEqApoConfigRoot {
    $p = (Get-ItemProperty 'HKLM:\SOFTWARE\EqualizerAPO' -ErrorAction SilentlyContinue).ConfigPath
    if ($p -and (Test-Path $p)) { return $p }
    $d = Join-Path $env:ProgramFiles 'EqualizerAPO\config'
    if (Test-Path $d) { return $d }
    return $null
}

function Get-HLEqSwitchPath {
    param([string]$ConfigRoot = (Get-HLEqApoConfigRoot))
    if (-not $ConfigRoot) { return $null }
    return (Join-Path $ConfigRoot 'hardline\switch.txt')
}

# Contenido de switch.txt para un preset dado y un estado.
function New-HLEqSwitchText {
    param([Parameter(Mandatory)] [string] $PresetName, [bool]$On = $true)
    $inc = "Include: $PresetName"
    $line = if ($On) { $inc } else { "# OFF $inc" }
    return (@(
            '# Hardline - interruptor del EQ (atajo Ctrl+Alt+F10 o eq_toggle.ps1).'
            '# Línea activa = EQ encendido. "# OFF" delante = EQ apagado.'
            $line
        ) -join "`r`n")
}

# Devuelve $true (encendido), $false (apagado) o $null (no hay interruptor).
function Get-HLEqState {
    param([string]$SwitchPath = (Get-HLEqSwitchPath))
    if (-not $SwitchPath -or -not (Test-Path $SwitchPath)) { return $null }
    foreach ($l in (Get-Content $SwitchPath)) {
        if ($l -match '^\s*Include:') { return $true }
        if ($l -match '^\s*#\s*OFF\s+Include:') { return $false }
    }
    return $null
}

# Preset al que apunta el interruptor (encendido o apagado), o $null.
function Get-HLEqPreset {
    param([string]$SwitchPath = (Get-HLEqSwitchPath))
    if (-not $SwitchPath -or -not (Test-Path $SwitchPath)) { return $null }
    foreach ($l in (Get-Content $SwitchPath)) {
        if ($l -match '^\s*(#\s*OFF\s+)?Include:\s*(.+?)\s*$') { return $Matches[2] }
    }
    return $null
}

<#
    Variantes de intensidad junto al preset activo: warzone_footsteps_<id>.txt
    (completa) y warzone_footsteps_<id>_70.txt (moderada). Devuelve Name,
    Label e Intensity, la completa primero.
#>
function Get-HLEqPresetVariants {
    param([Parameter(Mandatory)] [string[]] $Names, [string] $Current = '')
    $base = if ($Current -match '^(warzone_footsteps_.+?)(_70)?\.txt$') { $Matches[1] } else { '' }
    $out = foreach ($n in $Names) {
        if ($n -notmatch '^(warzone_footsteps_.+?)(_70)?\.txt$') { continue }
        if ($base -and $Matches[1] -ne $base) { continue }
        $mod = [bool]$Matches[2]
        [pscustomobject]@{ Name = $n; Label = $(if ($mod) { 'Moderada (70%)' } else { 'Completa' }); Intensity = $(if ($mod) { 0.7 } else { 1.0 }) }
    }
    return @($out | Sort-Object { -$_.Intensity })
}

# Cambia el preset sin tocar el estado encendido/apagado. Equalizer APO recarga al momento.
function Set-HLEqPreset {
    param([Parameter(Mandatory)] [string] $PresetName, [string]$SwitchPath = (Get-HLEqSwitchPath))
    if (-not $SwitchPath -or -not (Test-Path $SwitchPath)) { throw 'No hay interruptor de EQ (ejecuta la configuración de audio de Hardline).' }
    if ($PresetName -notmatch '^warzone_footsteps_[\w.-]+\.txt$') { throw "Nombre de preset no válido: $PresetName" }
    $lines = @(Get-Content $SwitchPath)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*(?:#\s*OFF\s+)?Include:\s*)') { $lines[$i] = $Matches[1] + $PresetName }
    }
    [IO.File]::WriteAllText($SwitchPath, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

function Set-HLEqState {
    param([Parameter(Mandatory)] [bool] $On, [string]$SwitchPath = (Get-HLEqSwitchPath))
    if (-not $SwitchPath -or -not (Test-Path $SwitchPath)) { throw 'No hay interruptor de EQ (ejecuta la configuración de audio de Hardline).' }
    $lines = @(Get-Content $SwitchPath)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($On -and $lines[$i] -match '^\s*#\s*OFF\s+(Include:.*)$') { $lines[$i] = $Matches[1] }
        elseif (-not $On -and $lines[$i] -match '^\s*(Include:.*)$') { $lines[$i] = "# OFF $($Matches[1])" }
    }
    [IO.File]::WriteAllText($SwitchPath, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

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

# Preset completo (100%) del que sale cada variante: quita _70 / _live.
function Get-HLEqBasePreset {
    param([string] $Current)
    if ($Current -match '^(warzone_footsteps_.+?)(_70|_live)?\.txt$') { return "$($Matches[1]).txt" }
    return $null
}

# Intensidad del preset activo (0-1.5) leída de su cabecera, o $null.
function Get-HLEqIntensity {
    param([string]$SwitchPath = (Get-HLEqSwitchPath))
    $cur = Get-HLEqPreset -SwitchPath $SwitchPath
    if (-not $cur) { return $null }
    $f = Join-Path (Split-Path $SwitchPath -Parent) $cur
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    foreach ($l in (Get-Content -LiteralPath $f -TotalCount 5)) { if ($l -match 'intensidad (\d+)%') { return [int]$Matches[1] / 100.0 } }
    return $null
}

<#
    Intensidad libre del EQ de pasos (0 = solo la corrección del headset,
    1 = preset completo, hasta 1.5). Escribe warzone_footsteps_<id>_live.txt
    a partir del preset completo y apunta el interruptor a él, sin tocar el
    estado encendido/apagado. Equalizer APO recarga al momento. Sin
    administrador: la carpeta hardline\ tiene permiso de escritura para el
    usuario. Devuelve el preamp del nuevo preset.
#>
function Set-HLEqIntensity {
    param([Parameter(Mandatory)] [double] $Intensity, [string]$SwitchPath = (Get-HLEqSwitchPath))
    if (-not $SwitchPath -or -not (Test-Path $SwitchPath)) { throw 'No hay interruptor de EQ (ejecuta la configuración de audio de Hardline).' }
    # [double] explícito: con un 0 entero, [Math]::Max elige la versión de enteros y 0.85 pasa a ser 1.
    $Intensity = [Math]::Min([double]1.5, [Math]::Max([double]0, $Intensity))
    $dir = Split-Path $SwitchPath -Parent
    $base = Get-HLEqBasePreset -Current (Get-HLEqPreset -SwitchPath $SwitchPath)
    if (-not $base -or -not (Test-Path -LiteralPath (Join-Path $dir $base))) { throw 'No se encuentra el preset completo: vuelve a aplicar el audio de Hardline.' }
    $r = New-HLEqIntensityPreset -BaseText ([IO.File]::ReadAllText((Join-Path $dir $base))) -Intensity $Intensity
    if ([Math]::Abs($Intensity - 1.0) -lt 0.001) {
        Set-HLEqPreset -PresetName $base -SwitchPath $SwitchPath
    } else {
        $live = $base -replace '\.txt$', '_live.txt'
        [IO.File]::WriteAllText((Join-Path $dir $live), $r.Text, [Text.Encoding]::ASCII)
        Set-HLEqPreset -PresetName $live -SwitchPath $SwitchPath
    }
    return $r.PreampDb
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

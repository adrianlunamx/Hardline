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

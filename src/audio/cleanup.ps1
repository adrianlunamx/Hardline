#Requires -Version 5.1
<#
    Hardline - audio previo: detección y limpieza antes de instalar.

    Si ya tenías un audio personalizado, instalar encima deja dos cadenas
    compitiendo y no sabes qué estás oyendo. Lo que se busca:

      1. Equalizer APO con un config.txt propio (tuyo, de Peace, de AutoEq...).
         Sus archivos se apartan a config\antes_de_hardline\ para que no se
         carguen ni se confundan con los de Hardline. Revertible.
      2. Equalizer APO activo en varios dispositivos. En modo Completo el EQ
         se aplicaría dos veces (CABLE Input y otra vez en el headset). Se
         listan para desmarcarlos en el Configurator.
      3. Presets antiguos de Hardline (otro headset, otra intensidad).
      4. Peace: al guardar reescribe config.txt y pisa el preset. Se quita su
         arranque automático y se ofrece desinstalarlo.
      5. Otros procesadores que se apilan con el EQ: FxSound, Boom 3D,
         ViPER4Windows, Razer Surround, Nahimic, SteelSeries Sonar, Dolby,
         DTS. Los que son programas sueltos se desinstalan con su propio
         desinstalador (pidiendo confirmación); los que van dentro de otra
         suite (Sonar en GG, Dolby, DTS) se explican paso a paso.
      6. Voicemeeter Banana o Standard sin Potato: los parámetros del
         compresor solo existen en Potato. Se instala Potato encima (mismo
         desinstalador, conserva la configuración).

    Lo que se mueve o se cambia en el registro queda en el manifiesto y el
    rollback lo devuelve. Una desinstalación no se puede revertir: por eso se
    pregunta programa a programa (o se pide -CleanAudio en modo desatendido).
#>

# CLSID con el que Equalizer APO se registra en los efectos de cada dispositivo.
$script:HLEqApoClsid = '{EACD2258-FCAC-4FF4-B36D-419E924A6D79}'

# Archivos que trae Equalizer APO en config\: no son configuración tuya.
$script:HLEqApoStockFiles = @('config.txt', 'example.txt', 'demo.txt', 'multichannel.txt', 'iir_lowpass.txt', 'readme.txt')

$script:HLAudioEnhancers = @(
    @{ Name = 'Peace';             Display = '^Peace';                 Process = @('Peace');                 Kind = 'Uninstall'; Why = 'Al guardar en Peace se reescribe config.txt y se pierde el preset de Hardline.' }
    @{ Name = 'FxSound';           Display = '^FxSound';               Process = @('FxSound');               Kind = 'Uninstall'; Why = 'Su propio EQ y "realce" se suman al de Hardline.' }
    @{ Name = 'Boom 3D';           Display = '^Boom 3D';               Process = @('Boom3D');                Kind = 'Uninstall'; Why = 'Virtualizador y EQ propios encima del de Hardline.' }
    @{ Name = 'ViPER4Windows';     Display = 'ViPER4Windows';          Process = @('ViPER4Windows');         Kind = 'Uninstall'; Why = 'Es otro APO: compite con Equalizer APO en el mismo dispositivo.' }
    @{ Name = 'Razer Surround';    Display = '^Razer Surround|THX Spatial Audio'; Process = @('RzSurround', 'THXAudioSvc'); Kind = 'Uninstall'; Why = 'Virtualizador 7.1: Warzone ya aplica su HRTF; apilarlos destruye la localización.' }
    @{ Name = 'Nahimic';           Display = '^Nahimic';               Process = @('Nahimic3', 'NahimicSvc64'); Service = 'NahimicService'; Kind = 'Service'; Why = 'Procesa el audio de todos los juegos; se desactiva su servicio (revertible).' }
    @{ Name = 'SteelSeries Sonar'; Endpoint = 'SteelSeries Sonar';    Kind = 'Manual'; Why = 'Sonar crea sus propios dispositivos con EQ.'; Advice = 'SteelSeries GG > Sonar: desactívalo (o desinstala GG si no lo usas). Si lo dejas, que el juego no salga por "SteelSeries Sonar - Gaming".' }
    @{ Name = 'Dolby Atmos';       Appx = 'DolbyLaboratories.Dolby'; Kind = 'Manual'; Why = 'Audio espacial encima del HRTF del juego.'; Advice = 'Propiedades del headset > Audio espacial: Desactivado (Dolby Atmos for Headphones fuera).' }
    @{ Name = 'DTS';               Appx = 'DTSInc.';                  Kind = 'Manual'; Why = 'Audio espacial encima del HRTF del juego.'; Advice = 'DTS Sound Unbound / DTS:X: desactívalo para el headset y deja Audio espacial en Desactivado.' }
)

# --------------------------------------------------------------------------
# Cálculo (sin hardware: se prueba en tests\validate.ps1)
# --------------------------------------------------------------------------

function Test-HLHardlineEqConfig {
    param([string]$Text)
    return ("$Text".TrimStart([char]0xFEFF) -match '^\s*# Hardline')
}

# Archivos que un config.txt incluye (Include: a.txt; Include: b.txt).
function Get-HLEqApoIncludes {
    param([string]$Text)
    $out = foreach ($l in ("$Text" -split '\r?\n')) {
        if ($l -match '^\s*Include\s*:\s*(.+?)\s*$') { foreach ($p in ($Matches[1] -split ';')) { $p.Trim() } }
    }
    return @($out | Where-Object { $_ })
}

# ¿Algún valor de FxProperties apunta a Equalizer APO?
function Test-HLEqApoFx {
    param([string[]]$Values)
    foreach ($v in $Values) { if ("$v".ToUpperInvariant().Contains($script:HLEqApoClsid)) { return $true } }
    return $false
}

<#
    Archivos de config\ que hay que apartar: lo que no es de Hardline ni de
    la instalación de Equalizer APO. $Files: nombres relativos a config\.
#>
function Select-HLEqApoForeignFiles {
    param([string[]]$Files, [string[]]$Includes = @())
    $stock = $script:HLEqApoStockFiles
    $out = foreach ($f in $Files) {
        $n = $f -replace '/', '\'
        if ($n -match '^(hardline|antes_de_hardline)\\') { continue }
        if ((Split-Path $n -Leaf).ToLowerInvariant() -in $stock -and $n -notmatch '\\') { continue }
        $n
    }
    # Lo incluido por el config.txt anterior, aunque esté en una subcarpeta.
    foreach ($i in $Includes) { $j = $i -replace '/', '\'; if ($j -notmatch '^(hardline|antes_de_hardline)\\' -and $j -notin $out -and $j -notmatch '^[A-Za-z]:') { $out += $j } }
    return @($out | Select-Object -Unique)
}

# Presets de Hardline que ya no se usan (otro headset u otra versión).
function Select-HLStalePresets {
    param([string[]]$Names, [string[]]$Keep)
    return @($Names | Where-Object { $_ -like 'warzone_footsteps_*.txt' -and $_ -notin $Keep })
}

<#
    Separa ejecutable y argumentos de una UninstallString y la convierte en
    silenciosa cuando se sabe hacerlo (MSI). Devuelve FilePath, Arguments y
    Silent.
#>
function ConvertTo-HLUninstallCommand {
    param([Parameter(Mandatory)] [string] $UninstallString, [string] $QuietUninstallString = '')
    $cmd = if ($QuietUninstallString) { $QuietUninstallString } else { $UninstallString }
    $silent = [bool]$QuietUninstallString
    if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $args_ = $Matches[2] }
    elseif ($cmd -match '^\s*(.+?\.exe)\s*(.*)$') { $exe = $Matches[1]; $args_ = $Matches[2] }
    else { $exe = $cmd.Trim(); $args_ = '' }
    if ((Split-Path $exe -Leaf) -match '^msiexec(\.exe)?$' -and $args_ -match '(\{[0-9A-Fa-f-]{36}\})') {
        $args_ = "/X$($Matches[1]) /qn /norestart"
        $silent = $true
    }
    return [pscustomobject]@{ FilePath = $exe; Arguments = $args_.Trim(); Silent = $silent }
}

# --------------------------------------------------------------------------
# Sistema
# --------------------------------------------------------------------------

function Get-HLUninstallEntries {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($r in $roots) {
        Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -and $_.UninstallString } |
            ForEach-Object { [pscustomobject]@{ DisplayName = $_.DisplayName; UninstallString = $_.UninstallString; QuietUninstallString = "$($_.QuietUninstallString)" } }
    }
}

# Dispositivos de reproducción activos con Equalizer APO instalado.
function Get-HLEqApoDevices {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    foreach ($k in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
        $state = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($state -ne 1) { continue }
        $fx = Get-ItemProperty (Join-Path $k.PSPath 'FxProperties') -ErrorAction SilentlyContinue
        if (-not $fx) { continue }
        $vals = @($fx.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Value)" })
        if (-not (Test-HLEqApoFx -Values $vals)) { continue }
        $p = Get-ItemProperty (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
        $desc = "$($p.'{a45c254e-df1c-4efd-8020-67d146a850e0},2')"; $iface = "$($p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6')"
        [pscustomobject]@{ Id = $k.PSChildName; Name = $(if ($iface) { "$desc ($iface)" } else { $desc }) }
    }
}

function Get-HLAudioInventory {
    param([string]$ConfigDir)
    $inv = [ordered]@{ ConfigDir = $ConfigDir; ForeignConfig = $false; ForeignFiles = @(); StalePresets = @(); ApoDevices = @(); Enhancers = @(); VoicemeeterNoPotato = $false }

    if ($ConfigDir -and (Test-Path $ConfigDir)) {
        $cfg = Join-Path $ConfigDir 'config.txt'
        $text = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
        if ($text.Trim() -and -not (Test-HLHardlineEqConfig $text)) {
            $inv.ForeignConfig = $true
            $files = @(Get-ChildItem $ConfigDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($ConfigDir.TrimEnd('\').Length + 1) })
            $inv.ForeignFiles = @(Select-HLEqApoForeignFiles -Files $files -Includes (Get-HLEqApoIncludes $text) | Where-Object { Test-Path (Join-Path $ConfigDir $_) })
        }
        $hlDir = Join-Path $ConfigDir 'hardline'
        if (Test-Path $hlDir) { $inv.StalePresets = @(Get-ChildItem $hlDir -Filter 'warzone_footsteps_*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
    }
    $inv.ApoDevices = @(Get-HLEqApoDevices)

    $entries = @(Get-HLUninstallEntries)
    $procs = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    $endpoints = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $_.FriendlyName })
    $appx = @()
    if (@($script:HLAudioEnhancers | Where-Object { $_.Appx }).Count) { $appx = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
    $inv.Enhancers = @(foreach ($e in $script:HLAudioEnhancers) {
            $entry = if ($e.Display) { $entries | Where-Object { $_.DisplayName -match $e.Display } | Select-Object -First 1 } else { $null }
            $running = @($e.Process | Where-Object { $_ -and $_ -in $procs }).Count -gt 0
            $svc = if ($e.Service) { Get-Service -Name $e.Service -ErrorAction SilentlyContinue } else { $null }
            $ep = if ($e.Endpoint) { @($endpoints | Where-Object { $_ -match [regex]::Escape($e.Endpoint) }).Count -gt 0 } else { $false }
            $ax = if ($e.Appx) { @($appx | Where-Object { $_ -like "$($e.Appx)*" }).Count -gt 0 } else { $false }
            if ($entry -or $running -or $svc -or $ep -or $ax) {
                [pscustomobject]@{ Name = $e.Name; Kind = $e.Kind; Why = $e.Why; Advice = "$($e.Advice)"; Entry = $entry; Service = $e.Service; Process = @($e.Process) }
            }
        })

    $inv.VoicemeeterNoPotato = [bool](Get-HLVoicemeeterDir) -and -not (Test-HLVoicemeeterPotato)
    return [pscustomobject]$inv
}

function Test-HLVoicemeeterPotato {
    $d = Get-HLVoicemeeterDir
    return [bool]($d -and ((Test-Path (Join-Path $d 'voicemeeter8x64.exe')) -or (Test-Path (Join-Path $d 'voicemeeter8.exe'))))
}

function Test-HLAudioInventoryClean {
    param([Parameter(Mandatory)] $Inventory, [string[]] $KeepPreset = @())
    return (-not $Inventory.ForeignConfig -and @(Select-HLStalePresets -Names $Inventory.StalePresets -Keep $KeepPreset).Count -eq 0 -and
        $Inventory.ApoDevices.Count -le 1 -and $Inventory.Enhancers.Count -eq 0 -and -not $Inventory.VoicemeeterNoPotato)
}

function Show-HLAudioInventory {
    param([Parameter(Mandatory)] $Inventory, [string[]] $KeepPreset = @())
    Write-HLWarn 'Hay un audio personalizado anterior. Se limpia antes de instalar para que no haya dos cadenas compitiendo:'
    if ($Inventory.ForeignConfig) { Write-HLSub ("Equalizer APO con configuración propia ({0} archivos): se apartan a config\antes_de_hardline\" -f $Inventory.ForeignFiles.Count) }
    $stale = @(Select-HLStalePresets -Names $Inventory.StalePresets -Keep $KeepPreset)
    if ($stale.Count) { Write-HLSub ("Presets antiguos de Hardline: {0}" -f ($stale -join ', ')) }
    if ($Inventory.ApoDevices.Count -gt 1) { Write-HLSub ("Equalizer APO activo en {0} dispositivos: {1}" -f $Inventory.ApoDevices.Count, (($Inventory.ApoDevices | ForEach-Object { $_.Name }) -join '; ')) }
    foreach ($e in $Inventory.Enhancers) { Write-HLSub ("{0}: {1}" -f $e.Name, $e.Why) }
    if ($Inventory.VoicemeeterNoPotato) { Write-HLSub 'Voicemeeter sin la edición Potato: se instala Potato encima (conserva tu configuración).' }
}

<#
    Aparta un archivo: copia en el backup de la sesión (manifiesto, el
    rollback lo devuelve), copia visible en antes_de_hardline\ y lo quita de
    su sitio para que Equalizer APO no lo cargue.
#>
function Move-HLAudioFile {
    param([Parameter(Mandatory)] [string] $ConfigDir, [Parameter(Mandatory)] [string] $Relative, [string] $Reason)
    $src = Join-Path $ConfigDir $Relative
    if (-not (Test-Path -LiteralPath $src)) { return $false }
    if ($HL.DryRun) { return $true }
    $dst = Join-Path (Join-Path $ConfigDir 'antes_de_hardline') $Relative
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Backup-HLFile -Path $src -Reason $Reason | Out-Null
    Remove-Item -LiteralPath $src -Force
    return $true
}

function Invoke-HLUninstallProgram {
    param([Parameter(Mandatory)] $Enhancer)
    $c = ConvertTo-HLUninstallCommand -UninstallString $Enhancer.Entry.UninstallString -QuietUninstallString $Enhancer.Entry.QuietUninstallString
    foreach ($p in $Enhancer.Process) { if ($p) { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } }
    if ($HL.DryRun) { return $true }
    if (-not $c.Silent) { Write-HLInfo "Se abre el desinstalador de $($Enhancer.Name): sigue sus pasos y ciérralo al terminar." }
    $proc = if ($c.Arguments) { Start-Process -FilePath $c.FilePath -ArgumentList $c.Arguments -Wait -PassThru } else { Start-Process -FilePath $c.FilePath -Wait -PassThru }
    Add-HLManifestEntry -Type 'Info' -Data @{ Note = "Hardline desinstaló $($Enhancer.Name) a petición tuya. El rollback no lo reinstala." }
    $still = @(Get-HLUninstallEntries | Where-Object { $_.DisplayName -eq $Enhancer.Entry.DisplayName }).Count -gt 0
    return (-not $still -or $proc.ExitCode -eq 0)
}

<#
    Limpieza. $AllowUninstall: en modo desatendido solo con -CleanAudio;
    con preguntas, se confirma programa a programa.
#>
function Invoke-HLAudioCleanup {
    param([Parameter(Mandatory)] $Inventory, [string[]] $KeepPreset = @(), [bool] $AllowUninstall = $false)
    $cfgDir = $Inventory.ConfigDir
    $moved = 0

    # El config.txt anterior también queda a la vista (Hardline lo reemplaza; copia en backups\).
    if ($Inventory.ForeignConfig -and -not $HL.DryRun) {
        $old = Join-Path $cfgDir 'config.txt'
        $keepDir = Join-Path $cfgDir 'antes_de_hardline'
        if (-not (Test-Path $keepDir)) { New-Item -ItemType Directory -Path $keepDir -Force | Out-Null }
        if (Test-Path $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $keepDir 'config.txt') -Force }
    }
    foreach ($f in $Inventory.ForeignFiles) {
        if (Move-HLAudioFile -ConfigDir $cfgDir -Relative $f -Reason 'Configuración anterior de Equalizer APO') { $moved++ }
    }
    if ($moved) {
        Write-HLSub "Configuración anterior de Equalizer APO apartada ($moved archivos en config\antes_de_hardline\)" 'OK'
        Add-HLResult -Module 'Audio' -Item 'Audio anterior: Equalizer APO' -Status Applied -Detail "$moved archivos apartados a $(Join-Path $cfgDir 'antes_de_hardline'). El rollback los devuelve."
    }
    $stale = @(Select-HLStalePresets -Names $Inventory.StalePresets -Keep $KeepPreset)
    foreach ($s in $stale) { Move-HLAudioFile -ConfigDir $cfgDir -Relative "hardline\$s" -Reason 'Preset antiguo de Hardline' | Out-Null }
    if ($stale.Count) { Add-HLResult -Module 'Audio' -Item 'Audio anterior: presets antiguos' -Status Applied -Detail ($stale -join ', ') }

    foreach ($e in $Inventory.Enhancers) {
        switch ($e.Kind) {
            'Service' {
                if ($e.Service -and (Get-Service -Name $e.Service -ErrorAction SilentlyContinue)) {
                    Get-Service -Name $e.Service -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
                    Set-HLServiceStart -Name $e.Service -StartType Disabled -Reason "$($e.Name): procesa el audio encima del EQ" | Out-Null
                    Add-HLResult -Module 'Audio' -Item "Audio anterior: $($e.Name)" -Status Applied -Detail 'Servicio desactivado (revertible)'
                } else {
                    Add-HLManualStep 'Audio' "$($e.Name): desactiva sus efectos para el headset. $($e.Why)"
                }
            }
            'Uninstall' {
                # Sin arranque automático aunque no se desinstale: deja de reescribir la config.
                foreach ($run in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
                    $props = Get-ItemProperty $run -ErrorAction SilentlyContinue
                    if (-not $props) { continue }
                    foreach ($pp in $props.PSObject.Properties) {
                        if ($pp.Name -notmatch '^PS' -and ($pp.Name -match [regex]::Escape($e.Name) -or "$($pp.Value)" -match [regex]::Escape($e.Name))) {
                            Remove-HLRegistryValue -Path $run -Name $pp.Name -Reason "Arranque automático de $($e.Name)" | Out-Null
                        }
                    }
                }
                if (-not $e.Entry) { Add-HLManualStep 'Audio' "$($e.Name) está en ejecución: ciérralo. $($e.Why)"; continue }
                $go = if ($HL.Unattended) { $AllowUninstall } else { Read-HLYesNo "¿Desinstalar $($e.Name)? $($e.Why)" $true }
                if ($go) {
                    Invoke-HLSafely 'Audio' "Desinstalar $($e.Name)" {
                        if (Invoke-HLUninstallProgram -Enhancer $e) {
                            Write-HLSub "$($e.Name) desinstalado" 'OK'
                            Add-HLResult -Module 'Audio' -Item "Audio anterior: $($e.Name)" -Status Applied -Detail 'Desinstalado (no se reinstala al revertir)'
                        } else {
                            Add-HLResult -Module 'Audio' -Item "Audio anterior: $($e.Name)" -Status Manual -Detail 'El desinstalador no terminó'
                            Add-HLManualStep 'Audio' "Desinstala $($e.Name) desde Configuración > Aplicaciones. $($e.Why)"
                        }
                    }
                } else {
                    Add-HLResult -Module 'Audio' -Item "Audio anterior: $($e.Name)" -Status Manual -Detail 'Se mantiene (sin arranque automático)'
                    Add-HLManualStep 'Audio' "$($e.Name) sigue instalado. $($e.Why) Desinstálalo desde Configuración > Aplicaciones o no lo abras mientras juegas."
                }
            }
            default {
                Add-HLResult -Module 'Audio' -Item "Audio anterior: $($e.Name)" -Status Manual -Detail $e.Why
                Add-HLManualStep 'Audio' $e.Advice
            }
        }
    }
}

# Aviso previo al Configurator: en qué dispositivos está ahora y cuál debe quedar.
function Get-HLEqApoDeviceAdvice {
    param($Devices, [ValidateSet('Full', 'EqOnly')] [string] $Mode)
    $list = @($Devices | ForEach-Object { $_.Name } | Where-Object { $_ })
    if ($list.Count -eq 0) { return '' }
    $target = if ($Mode -eq 'Full') { 'CABLE Input' } else { 'tu headset' }
    # El nombre visible se puede cambiar en Windows ("Art Tune +"): el del driver no.
    $cable = 'CABLE Input|VB-Audio Virtual Cable'
    $extra = if ($Mode -eq 'Full') { @($list | Where-Object { $_ -notmatch $cable }) } else { @($list | Select-Object -Skip 1) }
    if ($extra.Count -eq 0 -and $list.Count -le 1) { return '' }
    return ("Equalizer APO está activo ahora en: {0}. Deja marcado SOLO {1} y desmarca el resto, o el EQ se aplicará dos veces." -f ($list -join '; '), $target)
}

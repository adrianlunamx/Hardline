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
$script:HLEqApoStockFiles = @('config.txt', 'example.txt', 'demo.txt', 'multichannel.txt', 'iir_lowpass.txt', 'selective_delay.txt', 'readme.txt')

$script:HLAudioEnhancers = @(
    # Art Tune normalmente no se registra en Aplicaciones: su rastro (ArtTuneDB, HeSuVi, VST, iconos) lo busca Get-HLArtTuneFootprint.
    @{ Name = 'Art Tune';          Display = '^Art ?Tune';             Process = @('ArtTune*');              Kind = 'Uninstall'; Why = 'Procesa el audio con sus propios efectos y renombra los dispositivos de VB-CABLE ("Art Tune +"), así que las instrucciones ya no coinciden.' }
    @{ Name = 'Peace';             Display = '^Peace';                 Process = @('Peace');                 Kind = 'Uninstall'; Why = 'Al guardar en Peace se reescribe config.txt y se pierde el preset de Hardline.' }
    @{ Name = 'FxSound';           Display = '^FxSound';               Process = @('FxSound');               Kind = 'Uninstall'; Why = 'Su propio EQ y "realce" se suman al de Hardline.' }
    @{ Name = 'Boom 3D';           Display = '^Boom 3D';               Process = @('Boom3D');                Kind = 'Uninstall'; Why = 'Virtualizador y EQ propios encima del de Hardline.' }
    @{ Name = 'ViPER4Windows';     Display = 'ViPER4Windows';          Process = @('ViPER4Windows');         Kind = 'Uninstall'; Why = 'Es otro APO: compite con Equalizer APO en el mismo dispositivo.' }
    @{ Name = 'Razer Surround';    Display = '^Razer Surround|THX Spatial Audio'; Process = @('RzSurround', 'THXAudioSvc'); Kind = 'Uninstall'; Why = 'Virtualizador 7.1: Warzone ya aplica su HRTF; apilarlos destruye la localización.' }
    @{ Name = 'Nahimic';           Display = '^Nahimic';               Process = @('Nahimic3', 'NahimicSvc64'); Service = 'NahimicService'; Kind = 'Service'; Why = 'Procesa el audio de todos los juegos; se desactiva su servicio (revertible).' }
    @{ Name = 'Sound Blaster (Acoustic Engine / Command)'; Display = '^BlasterX Acoustic Engine|^Sound Blaster Command|^Sound Blaster Connect'; Process = @('BlasterX*', 'SBCommand*', 'SBConnect*'); Kind = 'Manual'; Why = 'Efectos de la tarjeta (SBX, Crystalizer, Smart Volume, EQ) encima del EQ de Hardline.'; Advice = 'Software de Sound Blaster (Acoustic Engine / Command): desactiva SBX Surround, Crystalizer, Smart Volume, Dialog Plus y su EQ para la salida del headset. Es el software de tu tarjeta: no se desinstala, solo se apagan sus efectos.' }
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

<#
    ¿Existe el desinstalador al que apunta la entrada? Si se borró la carpeta
    del programa a mano, la entrada queda huérfana en Aplicaciones: el programa
    ya no está y lanzar el desinstalador falla siempre. Solo se da por
    huérfana con una ruta absoluta y limpia a un .exe que no existe: msiexec,
    RunDll32 (InstallShield) y cualquier cosa que no se entienda bien cuentan
    como presentes, porque quitar la entrada de un programa instalado sería peor.
#>
function Test-HLUninstallerPresent {
    param([Parameter(Mandatory)] $Entry)
    $c = ConvertTo-HLUninstallCommand -UninstallString $Entry.UninstallString -QuietUninstallString $Entry.QuietUninstallString
    $path = [Environment]::ExpandEnvironmentVariables("$($c.FilePath)").Trim()
    if ($path -notmatch '^[A-Za-z]:\\[^"<>|?*]+\.exe$') { return $true }
    if ((Split-Path $path -Leaf) -match '^(msiexec|rundll32)\.exe$') { return $true }
    return (Test-Path -LiteralPath $path)
}

# --------------------------------------------------------------------------
# Sistema
# --------------------------------------------------------------------------

function Get-HLUninstallEntries {
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($r in $roots) {
        foreach ($k in (Get-ChildItem $r -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if (-not ($p -and $p.DisplayName -and $p.UninstallString)) { continue }
            # Key: ruta de la clave en formato de reg.exe, para poder quitar una entrada huérfana.
            [pscustomobject]@{ DisplayName = $p.DisplayName; UninstallString = $p.UninstallString; QuietUninstallString = "$($p.QuietUninstallString)"; Key = $k.Name }
        }
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

<#
    Rastro de Art Tune (un paquete de configuración para Equalizer APO, sin
    desinstalador en Aplicaciones) y de HeSuVi (virtualizador surround que
    se apila con el HRTF de Warzone). Devuelve:
      Items       lo que se aparta entero (reversible): carpetas de config\,
                  VST, iconos, LEQ Control Panel y accesos directos a ello.
      UserCopies  copias que Art Tune guardó en Documentos / Descargas. Son
                  tuyas y no afectan al audio: solo se listan.
      ArtTune     $true si hay rastro de Art Tune (no solo de HeSuVi).
    Las rutas base son parámetros para probarlo sin tocar el sistema.
#>
function Get-HLArtTuneFootprint {
    param(
        [string] $ConfigDir,
        [string] $ProgramData = $env:ProgramData,
        [string[]] $ProgramFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}),
        [string] $LocalAppData = $env:LOCALAPPDATA,
        [string[]] $LinkDirs = @(),
        [string[]] $UserDirs = @()
    )
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($p, $what) if ($p -and (Test-Path -LiteralPath $p) -and -not ($items | Where-Object { $_.Path -eq $p })) { $items.Add([pscustomobject]@{ Path = $p; What = $what }) } }

    $artTune = $false
    if ($ConfigDir -and (Test-Path -LiteralPath $ConfigDir)) {
        $db = Join-Path $ConfigDir 'ArtTuneDB'
        if (Test-Path -LiteralPath $db) { $artTune = $true; & $add $db 'Biblioteca de Art Tune en Equalizer APO' }
        & $add (Join-Path $ConfigDir 'HeSuVi') 'HeSuVi: virtualizador surround encima del HRTF de Warzone'
        # Copias que Art Tune deja junto a config.txt (_backup_AAAAMMDD).
        if ($artTune) { foreach ($b in @(Get-ChildItem -LiteralPath $ConfigDir -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue)) { & $add $b.FullName 'Copia de configuración de Art Tune' } }
    }
    if ($ProgramData) {
        $pd = Join-Path $ProgramData 'ArtTune'
        if (Test-Path -LiteralPath $pd) { $artTune = $true; & $add $pd 'Iconos de Art Tune para los dispositivos de VB-CABLE' }
    }
    foreach ($pf in @($ProgramFiles | Where-Object { $_ })) {
        $vst = Join-Path $pf 'VSTPlugins\ArtTuneKit'
        if (Test-Path -LiteralPath $vst) { $artTune = $true; & $add $vst 'Plugin VST de Art Tune (cadena "Art Tune +")' }
    }
    if ($artTune -and $LocalAppData) {
        & $add (Join-Path $LocalAppData 'Programs\LEQControlPanel') 'LEQ Control Panel (ecualización de sonoridad que trae Art Tune)'
    }

    # Accesos directos que apuntan a lo anterior (ArtTuneDB.lnk en el escritorio, HeSuVi...).
    if ($items.Count -gt 0) {
        $sh = $null
        try { $sh = New-Object -ComObject WScript.Shell } catch { $sh = $null }
        foreach ($ld in @($LinkDirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
            foreach ($lnk in @(Get-ChildItem -LiteralPath $ld -Filter '*.lnk' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue)) {
                $target = ''
                if ($sh) { try { $target = "$($sh.CreateShortcut($lnk.FullName).TargetPath)" } catch { $target = '' } }
                $hit = @($items | Where-Object { $target -and $target.StartsWith($_.Path, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
                if ($hit -or $lnk.BaseName -match '^(Art ?Tune|ArtTuneDB|HeSuVi|LEQ Control Panel)') { & $add $lnk.FullName 'Acceso directo' }
            }
        }
    }

    $copies = @(foreach ($ud in @($UserDirs | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
            Get-ChildItem -LiteralPath $ud -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Art ?Tune|ArtTuneDB)' } | ForEach-Object { $_.FullName }
        })
    return [pscustomobject]@{ Items = @($items.ToArray()); UserCopies = $copies; ArtTune = $artTune }
}

function Get-HLAudioInventory {
    param([string]$ConfigDir)
    $inv = [ordered]@{ ConfigDir = $ConfigDir; ForeignConfig = $false; ForeignFiles = @(); StalePresets = @(); ApoDevices = @(); Enhancers = @(); VoicemeeterNoPotato = $false
        Footprint = @(); UserCopies = @(); Orphans = @() }

    $userDirs = @([Environment]::GetFolderPath('MyDocuments'), (Join-Path $env:USERPROFILE 'Downloads'))
    $linkDirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))
    $fp = Get-HLArtTuneFootprint -ConfigDir $ConfigDir -LinkDirs $linkDirs -UserDirs $userDirs
    $inv.Footprint = @($fp.Items)
    $inv.UserCopies = @($fp.UserCopies)

    if ($ConfigDir -and (Test-Path $ConfigDir)) {
        $cfg = Join-Path $ConfigDir 'config.txt'
        $text = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
        if ($text.Trim() -and -not (Test-HLHardlineEqConfig $text)) {
            $inv.ForeignConfig = $true
            $files = @(Get-ChildItem $ConfigDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($ConfigDir.TrimEnd('\').Length + 1) })
            # Lo que se aparta como carpeta entera (ArtTuneDB, HeSuVi) no se mueve archivo a archivo.
            $whole = @($inv.Footprint | ForEach-Object { $_.Path } | Where-Object { $_.StartsWith($ConfigDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object { $_.Substring($ConfigDir.TrimEnd('\').Length + 1) + '\' })
            $files = @($files | Where-Object { $f = $_; -not ($whole | Where-Object { $f.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) })
            $inv.ForeignFiles = @(Select-HLEqApoForeignFiles -Files $files -Includes (Get-HLEqApoIncludes $text) | Where-Object { $f = $_; (Test-Path (Join-Path $ConfigDir $f)) -and -not ($whole | Where-Object { $f.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) })
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
            # Solo en lo que Hardline desinstala: el software de tarjetas (Kind Manual) no se toca.
            if ($entry -and $e.Kind -eq 'Uninstall' -and -not (Test-HLUninstallerPresent -Entry $entry)) {
                # Huérfana: el programa ya no está, pero sigue en Aplicaciones. Se quita la entrada (revertible).
                Write-HLLog INFO "$($e.Name): entrada de desinstalación huérfana ($($entry.UninstallString) no existe)."
                $inv.Orphans += [pscustomobject]@{ Name = $e.Name; DisplayName = $entry.DisplayName; Key = $entry.Key }
                $entry = $null
            }
            $running = @(foreach ($pat in @($e.Process)) { if ($pat) { $procs | Where-Object { $_ -like $pat } } }).Count -gt 0
            $svc = if ($e.Service) { Get-Service -Name $e.Service -ErrorAction SilentlyContinue } else { $null }
            $ep = if ($e.Endpoint) { @($endpoints | Where-Object { $_ -match [regex]::Escape($e.Endpoint) }).Count -gt 0 } else { $false }
            $ax = if ($e.Appx) { @($appx | Where-Object { $_ -like "$($e.Appx)*" }).Count -gt 0 } else { $false }
            if ($entry -or $running -or $svc -or $ep -or $ax) {
                [pscustomobject]@{ Name = $e.Name; Kind = $e.Kind; Why = $e.Why; Advice = "$($e.Advice)"; Entry = $entry; Service = $e.Service; Process = @($e.Process) }
            }
        })

    # ReaPlugs: plugins VST que carga la cadena "Art Tune +". Sin Art Tune puede ser
    # tuyo (para un DAW), así que solo se ofrece quitarlo si hay rastro de Art Tune.
    $artTuneSeen = $fp.ArtTune -or @($endpoints | Where-Object { $_ -match 'Art Tune' }).Count -gt 0
    if ($artTuneSeen) {
        $rp = $entries | Where-Object { $_.DisplayName -match '^ReaPlugs' } | Select-Object -First 1
        if ($rp -and (Test-HLUninstallerPresent -Entry $rp)) {
            $inv.Enhancers += [pscustomobject]@{ Name = 'ReaPlugs'; Kind = 'Uninstall'; Why = 'Plugins VST que carga la cadena "Art Tune +" dentro de Equalizer APO.'; Advice = ''; Entry = $rp; Service = $null; Process = @() }
        }
    }

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
        $Inventory.ApoDevices.Count -le 1 -and $Inventory.Enhancers.Count -eq 0 -and -not $Inventory.VoicemeeterNoPotato -and
        (Get-HLCount $Inventory 'Footprint') -eq 0 -and (Get-HLCount $Inventory 'Orphans') -eq 0)
}

# Elementos de una lista del inventario (0 si no existe la propiedad).
function Get-HLCount {
    param($Object, [string] $Name)
    $p = $Object.PSObject.Properties[$Name]
    if (-not $p -or $null -eq $p.Value) { return 0 }
    return @($p.Value | Where-Object { $null -ne $_ }).Count
}

function Show-HLAudioInventory {
    param([Parameter(Mandatory)] $Inventory, [string[]] $KeepPreset = @())
    Write-HLWarn 'Hay un audio personalizado anterior. Se limpia antes de instalar para que no haya dos cadenas compitiendo:'
    if ($Inventory.ForeignConfig) { Write-HLSub ("Equalizer APO con configuración propia ({0} archivos): se apartan a config\antes_de_hardline\" -f $Inventory.ForeignFiles.Count) }
    $stale = @(Select-HLStalePresets -Names $Inventory.StalePresets -Keep $KeepPreset)
    if ($stale.Count) { Write-HLSub ("Presets antiguos de Hardline: {0}" -f ($stale -join ', ')) }
    if ((Get-HLCount $Inventory 'Footprint') -gt 0) {
        Write-HLSub 'Art Tune / HeSuVi: se aparta todo (vuelve con el rollback):'
        foreach ($f in $Inventory.Footprint) { Write-HLInfo ("  {0}: {1}" -f $f.What, $f.Path) }
    }
    if ((Get-HLCount $Inventory 'Orphans') -gt 0) { Write-HLSub ("Entradas de Aplicaciones de programas que ya no están: {0}. Se quitan de la lista." -f (($Inventory.Orphans | ForEach-Object { $_.DisplayName }) -join ', ')) }
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

<#
    Deja config.txt sin filtros (copia en el manifiesto) y reinicia el audio
    de Windows: Equalizer APO suelta los VST y archivos de la configuración
    anterior. Hardline escribe su config.txt justo después.
#>
function Clear-HLEqApoConfig {
    param([Parameter(Mandatory)] [string] $ConfigDir)
    if ($HL.DryRun) { return }
    $cfg = Join-Path $ConfigDir 'config.txt'
    if (Test-Path -LiteralPath $cfg) {
        Backup-HLFile -Path $cfg -Reason 'config.txt neutro para soltar la configuración anterior' | Out-Null
        Set-Content -LiteralPath $cfg -Value '# Hardline: configuración anterior apartada. Hardline escribe la suya a continuación.' -Encoding UTF8
    }
    Write-HLInfo 'Reiniciando el audio de Windows para soltar la configuración anterior...'
    try { Restart-Service -Name 'Audiosrv' -Force -ErrorAction Stop; Start-Sleep -Seconds 2 } catch { Write-HLLog WARN "No se pudo reiniciar Audiosrv: $($_.Exception.Message)" }
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

    # Art Tune / HeSuVi: carpetas enteras a backups\<sesión>\apartado\.
    $footprint = @($Inventory.Footprint | Where-Object { $_ })
    if ($footprint.Count -gt 0) {
        if (-not $HL.DryRun) { Get-Process -Name 'HeSuVi', 'LEQControlPanel' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
        $audioRestarted = $false
        $aside = 0
        foreach ($f in $footprint) {
            $done = $false
            try { [void](Move-HLPathAside -Path $f.Path -Reason $f.What); $done = $true }
            catch {
                # Archivo en uso: Equalizer APO tiene cargado un VST o un filtro de la configuración
                # anterior. Se deja config.txt neutro, se reinicia el audio y se vuelve a intentar.
                if (-not $audioRestarted -and -not $HL.DryRun) {
                    $audioRestarted = $true
                    Clear-HLEqApoConfig -ConfigDir $cfgDir
                    try { [void](Move-HLPathAside -Path $f.Path -Reason $f.What); $done = $true } catch { Write-HLLog WARN "No se pudo apartar $($f.Path): $($_.Exception.Message)" }
                } else { Write-HLLog WARN "No se pudo apartar $($f.Path): $($_.Exception.Message)" }
            }
            if ($done) { $aside++ } else {
                Add-HLResult -Module 'Audio' -Item "Audio anterior: $($f.What)" -Status Manual -Detail "En uso: $($f.Path)"
                Add-HLManualStep 'Audio' "Reinicia y vuelve a aplicar el audio: no se pudo apartar $($f.Path) ($($f.What)) porque estaba en uso."
            }
        }
        if ($aside) {
            Write-HLSub "Art Tune / HeSuVi apartados ($aside elementos)" 'OK'
            Add-HLResult -Module 'Audio' -Item 'Audio anterior: Art Tune / HeSuVi' -Status Applied -Detail "$aside carpetas y accesos apartados a backups\$($HL.Stamp)\apartado. El rollback los devuelve."
        }
        Add-HLManualStep 'Audio' 'Si activaste "Ecualización de sonoridad" (Loudness Equalization) con LEQ Control Panel: Configuración > Sonido > tu headset > Mejoras de audio: desactivadas. Comprime el audio por su cuenta, encima del compresor de Hardline.'
    }
    $copies = @($Inventory.UserCopies | Where-Object { $_ })
    if ($copies.Count -gt 0) {
        Add-HLManualStep 'Audio' ("Copias de Art Tune en tus carpetas (no afectan al audio, Hardline no las toca): {0}. Bórralas si ya no las quieres." -f ($copies -join '; '))
    }
    foreach ($o in @($Inventory.Orphans | Where-Object { $_ -and $_.Key })) {
        try {
            if (Remove-HLRegistryKey -Key $o.Key -Reason "Entrada huérfana de $($o.Name)") {
                Write-HLSub "$($o.DisplayName): entrada sin programa quitada de Aplicaciones" 'OK'
                Add-HLResult -Module 'Audio' -Item "Audio anterior: $($o.Name)" -Status Applied -Detail 'Ya no estaba instalado; se quitó su entrada de Aplicaciones (revertible).'
            }
        } catch {
            Add-HLResult -Module 'Audio' -Item "Audio anterior: $($o.Name)" -Status Failed -Detail $_.Exception.Message
        }
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

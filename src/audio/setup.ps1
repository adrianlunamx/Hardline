#Requires -Version 5.1
<#
    Hardline - audio competitivo.

    Dos modos:
      Completo   cod.exe -> CABLE Input [EQ APO] -> Voicemeeter Strip 1 [Gate+Comp] -> headset
                 Resto del sistema -> Voicemeeter Input -> headset (sin procesar)
                 Coste: Voicemeeter añade ~10-20 ms de latencia de audio.
      Solo EQ    Todo -> headset [EQ APO]. Sin latencia añadida, sin compresión.

    Se puede ejecutar suelto:
      .\src\audio\setup.ps1                     (interactivo, requiere admin)
      .\src\audio\setup.ps1 -HeadsetId "Kraken V3" (busca la medición en AutoEq)
      .\src\audio\setup.ps1 -ConfigureVoicemeeter -HeadsetId corsair-hs80 -HeadsetDevice "Headphones (CORSAIR HS80)"
        (segunda fase tras reiniciar; la registra el propio script en RunOnce)
#>
[CmdletBinding()]
param(
    [switch] $ConfigureVoicemeeter,
    [string] $HeadsetId,
    [string] $HeadsetDevice
)

$script:AudioRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'eq.ps1')
. (Join-Path $PSScriptRoot 'voicemeeter.ps1')
. (Join-Path $PSScriptRoot 'autoeq.ps1')
. (Join-Path $PSScriptRoot 'eqswitch.ps1')
. (Join-Path $PSScriptRoot 'hesuvi.ps1')
. (Join-Path $PSScriptRoot 'cleanup.ps1')
. (Join-Path $PSScriptRoot 'endpoints.ps1')

# Fuentes de descarga. Voicemeeter con hash fijado (mismo que el manifiesto de
# winget VB-Audio.Voicemeeter.Potato 3.1.2.2). EQ APO viene de SourceForge
# (proyecto oficial); VB-Cable de vb-audio.com. Peace ya no se instala: al
# guardar reescribe config.txt y pisa el preset (ver cleanup.ps1).
$script:HLAudioSources = @{
    Voicemeeter = @{
        Urls   = @('https://download.vb-audio.com/Download_CABLE/Voicemeeter8Setup_v3122.zip')
        Sha256 = '4061AE4CE1AB8009E39819DD3DACAB9316E5F04B307014DDA6D2B338AA2E0DDC'
        Page   = 'https://vb-audio.com/Voicemeeter/potato.htm'
    }
    VBCable = @{
        Urls   = @('https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip',
                   'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip')
        Page   = 'https://vb-audio.com/Cable/'
    }
    EqualizerAPO = @{
        Urls   = @('https://sourceforge.net/projects/equalizerapo/files/latest/download',
                   'https://sourceforge.net/projects/equalizerapo/files/1.3/EqualizerAPO64-1.3.exe/download')
        Page   = 'https://sourceforge.net/projects/equalizerapo/'
    }
}

# --------------------------------------------------------------------------
# Detección de componentes
# --------------------------------------------------------------------------

function Get-HLEqApoDir {
    $p = (Get-ItemProperty 'HKLM:\SOFTWARE\EqualizerAPO' -ErrorAction SilentlyContinue).InstallPath
    if ($p -and (Test-Path $p)) { return $p }
    $d = Join-Path $env:ProgramFiles 'EqualizerAPO'
    if (Test-Path (Join-Path $d 'Configurator.exe')) { return $d }
    return $null
}

function Get-HLEqApoConfigDir {
    param([string]$InstallDir)
    $p = (Get-ItemProperty 'HKLM:\SOFTWARE\EqualizerAPO' -ErrorAction SilentlyContinue).ConfigPath
    if ($p -and (Test-Path $p)) { return $p }
    return (Join-Path $InstallDir 'config')
}

function Test-HLVBCable {
    return [bool](Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like 'CABLE Input*' })
}

# --------------------------------------------------------------------------
# Instalación
# --------------------------------------------------------------------------

function Get-HLTempDir {
    $d = Join-Path $env:TEMP 'Hardline'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

<#
    Intento fallido de instalar Potato encima de otra edición. Se guarda el
    SHA256 del instalador: con el mismo instalador no se reintenta en cada
    aplicación (cada intento cierra Voicemeeter y corta el audio). Si
    Hardline trae otro instalador, se vuelve a probar.
#>
function Get-HLPotatoFailMarker { return (Join-Path (Join-Path $HL.Root 'config') 'voicemeeter_potato_failed.txt') }

function Test-HLPotatoInstallFailed {
    $f = Get-HLPotatoFailMarker
    if (-not (Test-Path $f)) { return $false }
    return ((Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim() -eq $script:HLAudioSources.Voicemeeter.Sha256)
}

function Set-HLPotatoInstallFailed {
    param([bool] $Failed)
    if ($HL.DryRun) { return }
    $f = Get-HLPotatoFailMarker
    if ($Failed) {
        $dir = Split-Path $f -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $f -Value $script:HLAudioSources.Voicemeeter.Sha256 -Encoding ASCII
    } else {
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }
}

<#
    Verifica la firma Authenticode de un instalador descargado ANTES de
    ejecutarlo con privilegios de administrador. Fail-closed: sin firma
    válida no se ejecuta nada. El firmante queda en el log para auditoría.
    (El chequeo de magic bytes de Invoke-HLDownload se mantiene.)
#>
function Test-HLInstallerSignature {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Name)
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    } catch {
        Write-HLErr "No se pudo leer la firma del instalador de $Name : $($_.Exception.Message)"
        return $false
    }
    if ($sig.Status -ne 'Valid') {
        Write-HLErr "El instalador de $Name no trae firma Authenticode válida (estado: $($sig.Status)). No se ejecuta."
        return $false
    }
    $signer = "$($sig.SignerCertificate.Subject)"
    Write-HLLog INFO "Firma válida de $Name : $signer"
    return $true
}

function Install-HLComponent {
    param([Parameter(Mandatory)] [ValidateSet('Voicemeeter', 'VBCable', 'EqualizerAPO')] [string] $Name)

    $src = $script:HLAudioSources[$Name]
    $tmp = Get-HLTempDir
    if ($HL.DryRun) { Write-HLSub "Instalar $Name" 'SKIP (DryRun)'; return $true }

    switch ($Name) {
        'Voicemeeter' {
            # Con Voicemeeter abierto el instalador no puede reemplazar sus archivos.
            Get-Process -Name 'voicemeeter*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            $zip = Join-Path $tmp 'voicemeeter.zip'
            if (Invoke-HLDownload -Urls $src.Urls -OutFile $zip -Sha256 $src.Sha256 -ExpectZip) {
                $x = Join-Path $tmp 'voicemeeter'
                Expand-Archive -Path $zip -DestinationPath $x -Force
                $exe = Get-ChildItem $x -Recurse -Filter 'Voicemeeter8Setup.exe' | Select-Object -First 1
                if (-not $exe) { $exe = Get-ChildItem $x -Recurse -Filter '*Setup*.exe' | Select-Object -First 1 }
                if ($exe) {
                    # -install = instalación silenciosa (código de salida 1 = OK, según el manifiesto de winget).
                    $p = Start-Process -FilePath $exe.FullName -ArgumentList '-install' -Wait -PassThru
                    Write-HLLog INFO "Instalador de Voicemeeter: código $($p.ExitCode)"
                    $HL.NeedsReboot = $true
                    if (Test-HLVoicemeeterPotato) { return $true }
                } else { Write-HLLog WARN 'El ZIP de Voicemeeter no trae el instalador esperado' }
            } else { Write-HLLog WARN 'Descarga de Voicemeeter fallida o SHA256 distinto (VB-Audio pudo publicar otra versión)' }
            # Alternativa: winget (repositorio oficial de Microsoft, mismo paquete de VB-Audio).
            if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
                Write-HLInfo 'Probando con winget...'
                $p = Start-Process -FilePath 'winget.exe' -ArgumentList @('install', '--id', 'VB-Audio.Voicemeeter.Potato', '-e', '--silent', '--accept-package-agreements', '--accept-source-agreements') -Wait -PassThru -WindowStyle Hidden
                Write-HLLog INFO "winget Voicemeeter: código $($p.ExitCode)"
                $HL.NeedsReboot = $true
            }
            return (Test-HLVoicemeeterPotato)
        }
        'VBCable' {
            $zip = Join-Path $tmp 'vbcable.zip'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $zip -ExpectZip)) { return $false }
            $x = Join-Path $tmp 'vbcable'
            Expand-Archive -Path $zip -DestinationPath $x -Force
            $exe = Get-ChildItem $x -Recurse -Filter 'VBCABLE_Setup_x64.exe' | Select-Object -First 1
            if (-not $exe) { return $false }
            # La firma se verifica ANTES de ejecutar el instalador elevado.
            if (-not (Test-HLInstallerSignature -Path $exe.FullName -Name 'VB-CABLE')) { return $false }
            Write-HLInfo 'Se abre el instalador de VB-CABLE: pulsa "Install Driver" y acepta el aviso de Windows.'
            $p = Start-Process -FilePath $exe.FullName -Wait -PassThru -Verb RunAs
            $HL.NeedsReboot = $true
            return $true
        }
        'EqualizerAPO' {
            $exe = Join-Path $tmp 'EqualizerAPO-setup.exe'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $exe -ExpectPE)) { return $false }
            # La firma se verifica ANTES de ejecutar el instalador.
            if (-not (Test-HLInstallerSignature -Path $exe -Name 'Equalizer APO')) { return $false }
            Write-HLInfo 'Se abre el instalador de Equalizer APO. Al final aparece el Configurator: NO marques nada todavía, Hardline te dirá qué dispositivo.'
            $p = Start-Process -FilePath $exe -Wait -PassThru
            $HL.NeedsReboot = $true
            return [bool](Get-HLEqApoDir)
        }
    }
}

# --------------------------------------------------------------------------
# Selección de headset y modo
# --------------------------------------------------------------------------

<#
    Devuelve @{ Id = <perfil empaquetado o 'generic'>; Correction = <corrección medida o $null> }.

    Orden de preferencia para la corrección del headset:
      archivo en headsets\ que coincida > descarga de AutoEq > perfil aproximado de headsets.json
#>
function Select-HLHeadset {
    param([Parameter(Mandatory)] $Database, $Hardware, [string]$Preset)

    $root = $HL.Root
    $bundled = @($Database.headsets)
    $local = @(Get-HLLocalCorrections -Root $root)

    # Busca corrección para un modelo empaquetado: primero en local, luego AutoEq.
    $getCorrection = {
        param($h, [bool]$ask)
        $hitLocal = $local | Where-Object { $_.Name -like "*$($h.name)*" } | Select-Object -First 1
        if ($hitLocal) { Write-HLSub "Corrección local: headsets\$(Split-Path $hitLocal.Path -Leaf)" 'OK'; return $hitLocal }
        if ($ask -and -not (Read-HLYesNo "¿Descargar la corrección medida de AutoEq para $($h.name)? (más precisa que el perfil aproximado)" $true)) { return $null }
        return (Find-HLAutoEqInteractive -Root $root -Query $h.name -PickBest)
    }

    # --- Parámetro -Headset: id empaquetado, nombre de archivo en headsets\ o modelo para AutoEq
    if ($Preset) {
        $h = $bundled | Where-Object { $_.id -eq $Preset } | Select-Object -First 1
        if ($h) { return [pscustomobject]@{ Id = $h.id; Correction = (& $getCorrection $h $false) } }
        if ($Preset -eq 'generic') { return [pscustomobject]@{ Id = 'generic'; Correction = $null } }
        $f = $local | Where-Object { $_.Name -like "*$Preset*" } | Select-Object -First 1
        if ($f) { return [pscustomobject]@{ Id = 'generic'; Correction = $f } }
        $c = Find-HLAutoEqInteractive -Root $root -Query $Preset -PickBest
        if ($c) { return [pscustomobject]@{ Id = 'generic'; Correction = $c } }
        Write-HLWarn "No se encontró '$Preset' (ni en headsets.json, ni en headsets\, ni en AutoEq); se pregunta."
    }

    # --- Detección
    $eps = if ($Hardware) { $Hardware.Audio } else { @(Get-HLAudioEndpoints) }
    $det = Find-HLHeadset -Profiles $bundled -Endpoints $eps
    # Nombre del modelo tal y como lo expone Windows: "Auriculares (Razer Kraken V3)" -> "Razer Kraken V3"
    $suggest = $null
    if (-not $det) {
        $ep = @($eps | Where-Object { $_.Render -and $_.Name -notmatch 'CABLE|Voicemeeter|VB-Audio|Realtek|High Definition|NVIDIA|AMD|Intel|Digital|HDMI|DisplayPort' }) | Select-Object -First 1
        if ($ep -and $ep.Name -match '\((?:\d+-\s*)?(?<m>[^)]+)\)') { $suggest = $Matches['m'].Trim() }
    }

    $options = New-Object System.Collections.Generic.List[string]
    foreach ($h in $bundled) { $options.Add(('{0} ({1} mm, {2} ohm, {3})' -f $h.name, $h.driver_mm, $h.impedance_ohm, $h.design)) }
    $iAutoEq = $options.Count; $options.Add('Otro modelo: buscar su medición en AutoEq (~8800 auriculares)')
    $iLocal = -1
    if ($local.Count -gt 0) { $iLocal = $options.Count; $options.Add("Archivo en la carpeta headsets\ ($($local.Count))") }
    $iGeneric = $options.Count; $options.Add('Genérico (preset base, sin corrección)')

    $default = $iGeneric
    if ($det) {
        $idx = [array]::IndexOf(@($bundled | ForEach-Object { $_.id }), $det.Id)
        if ($idx -ge 0) { $default = $idx }
        Write-HLOk "Headset detectado: $($det.DeviceName)"
    } elseif ($suggest) {
        $default = $iAutoEq
        Write-HLOk "Salida de audio detectada: $suggest (no está en los perfiles incluidos)"
    }
    if ($HL.Unattended -and -not $det) { return [pscustomobject]@{ Id = 'generic'; Correction = $null } }

    while ($true) {
        $i = Read-HLChoice -Prompt '¿Qué headset tienes?' -Options $options.ToArray() -Default $default
        if ($i -lt $bundled.Count) {
            $h = $bundled[$i]
            $c = & $getCorrection $h (-not $HL.Unattended)
            if (-not $c) { Write-HLInfo "Se usa el perfil aproximado de $($h.name)." }
            return [pscustomobject]@{ Id = $h.id; Correction = $c }
        }
        if ($i -eq $iAutoEq) {
            $c = Find-HLAutoEqInteractive -Root $root -Query $suggest
            if ($c) { return [pscustomobject]@{ Id = 'generic'; Correction = $c } }
            Write-HLInfo "Sin perfil. Puedes descargarlo a mano de https://autoeq.app (formato Equalizer APO) y dejarlo en $(Get-HLHeadsetDir -Root $root)"
            $suggest = $null
            continue
        }
        if ($i -eq $iLocal) {
            $j = Read-HLChoice -Prompt 'Archivo' -Options @($local | ForEach-Object { "$($_.Name) ($(@($_.Filters).Count) filtros)" }) -Default 0
            return [pscustomobject]@{ Id = 'generic'; Correction = $local[$j] }
        }
        return [pscustomobject]@{ Id = 'generic'; Correction = $null }
    }
}

function Select-HLRenderDevice {
    param([Parameter(Mandatory)] [string] $HeadsetId, $Database, [string] $Preferred = '')

    $render = @(Get-HLAudioEndpoints | Where-Object { $_.Render -and $_.Name -notmatch 'CABLE|Voicemeeter|VB-Audio' })
    if ($render.Count -eq 0) { return $null }

    # Elegida en la interfaz o con -AudioDevice.
    if ($Preferred) {
        $hit = @($render | Where-Object { $_.Name -eq $Preferred }) + @($render | Where-Object { $_.Name -like "*$Preferred*" }) | Select-Object -First 1
        if ($hit) { return $hit.Name }
        Write-HLWarn "La salida elegida ""$Preferred"" no está conectada; se elige automáticamente."
    }

    $h = @($Database.headsets | Where-Object { $_.id -eq $HeadsetId }) | Select-Object -First 1
    $patterns = if ($h) { @($h.match) } else { @() }
    $winDefault = Get-HLDefaultRenderName
    $best = 0; $bestScore = [int]::MinValue
    for ($i = 0; $i -lt $render.Count; $i++) {
        $sc = Get-HLRenderDeviceScore -Name $render[$i].Name -HeadsetPatterns $patterns -WindowsDefault $winDefault
        if ($sc -gt $bestScore) { $best = $i; $bestScore = $sc }
    }
    if ($render.Count -eq 1) { return $render[0].Name }
    if ($HL.Unattended) {
        Write-HLSub "Salida del headset (A1): $($render[$best].Name) (automática; se cambia en la interfaz, ""Salida del headset"")"
        return $render[$best].Name
    }
    $i = Read-HLChoice -Prompt 'Dispositivo de salida del headset (A1 de Voicemeeter)' -Options @($render | ForEach-Object { $_.Name }) -Default $best
    return $render[$i].Name
}

# --------------------------------------------------------------------------
# Equalizer APO
# --------------------------------------------------------------------------

function Write-HLEqConfig {
    param([Parameter(Mandatory)] $HeadsetProfile, [double]$Intensity = 1.0, [switch]$WithHeSuVi)

    $apo = Get-HLEqApoDir
    if (-not $apo) { throw 'Equalizer APO no está instalado.' }
    $cfgDir = Get-HLEqApoConfigDir -InstallDir $apo
    $hlDir = Join-Path $cfgDir 'hardline'
    if (-not (Test-Path $hlDir) -and -not $HL.DryRun) { New-Item -ItemType Directory -Path $hlDir -Force | Out-Null }

    # Las dos intensidades quedan escritas: el panel del EQ cambia entre ellas al momento.
    $fullName = "warzone_footsteps_$($HeadsetProfile.id).txt"
    $modName = "warzone_footsteps_$($HeadsetProfile.id)_70.txt"
    $presetName = if ($Intensity -lt 1.0) { $modName } else { $fullName }
    $presetPath = Join-Path $hlDir $presetName
    $variants = @{
        $fullName = ConvertTo-HLEqApoText -HeadsetProfile $HeadsetProfile -Title 'Warzone footsteps' -Intensity 1.0
        $modName  = ConvertTo-HLEqApoText -HeadsetProfile $HeadsetProfile -Title 'Warzone footsteps (moderada)' -Intensity 0.7
    }
    $configPath = Join-Path $cfgDir 'config.txt'

    # config.txt -> [HeSuVi] -> hardline\switch.txt -> preset. El atajo de
    # teclado solo toca switch.txt (ver eqswitch.ps1); HeSuVi queda aparte
    # y el EQ se puede encender/apagar sin perder la virtualización.
    # Orden: primero la convolución 7.1->estéreo de HeSuVi y después el EQ
    # de pasos de Hardline (convención de la comunidad: pre, HeSuVi, EQ).
    $lines = @(
        '# Hardline - Equalizer APO'
        '# Backup del config.txt anterior en la carpeta backups/ de Hardline.'
        '# Encender/apagar el EQ: atajo Ctrl+Alt+F10 (edita hardline\switch.txt).'
        ''
    )
    if ($WithHeSuVi) {
        if (Test-Path -LiteralPath (Join-Path $cfgDir 'HeSuVi\hesuvi.txt')) {
            $lines += @('# HeSuVi: virtualización 7.1 -> estéreo (HRTF). Va ANTES del EQ.', 'Include: HeSuVi\hesuvi.txt', '')
        } else {
            Write-HLWarn 'HeSuVi pedido pero no se encontró HeSuVi\hesuvi.txt: el EQ se escribe sin virtualización. Abre la interfaz de HeSuVi una vez y vuelve a aplicar el audio.'
        }
    }
    $lines += 'Include: hardline\switch.txt'
    $config = $lines -join "`r`n"
    $switchPath = Join-Path $hlDir 'switch.txt'

    if ($HL.DryRun) { return $presetPath }

    $utf8 = New-Object Text.UTF8Encoding($false)
    foreach ($v in $variants.Keys) {
        $vp = Join-Path $hlDir $v
        Backup-HLFile -Path $vp -Reason 'Preset EQ de Hardline' | Out-Null
        [IO.File]::WriteAllText($vp, $variants[$v].Replace("`r`n", "`n").Replace("`n", "`r`n"), $utf8)
    }
    Backup-HLFile -Path $switchPath -Reason 'Interruptor del EQ' | Out-Null
    [IO.File]::WriteAllText($switchPath, (ConvertTo-HLAscii (New-HLEqSwitchText -PresetName $presetName -On $true)), $utf8)
    Backup-HLFile -Path $configPath -Reason 'config.txt de Equalizer APO' | Out-Null
    [IO.File]::WriteAllText($configPath, (ConvertTo-HLAscii $config), $utf8)
    Grant-HLUserWrite -Path $hlDir
    return $presetPath
}

<#
    Permiso de modificación para el usuario actual en config\hardline (dentro
    de Program Files). Así el atajo de teclado cambia el EQ sin pedir admin.
    Queda en el manifiesto: el rollback lo retira.
#>
function Grant-HLUserWrite {
    param([Parameter(Mandatory)] [string] $Path)
    $who = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = Get-Acl -Path $Path
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($who, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    # Idempotente: AddAccessRule duplicaba la ACE en re-ejecuciones.
    $already = @($acl.Access | Where-Object {
        $_.IdentityReference.Value -eq $who -and $_.FileSystemRights -eq 'Modify' -and
        $_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit') -and
        $_.PropagationFlags -eq 'None' -and $_.AccessControlType -eq 'Allow'
    }).Count -gt 0
    if (-not $already) {
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl
    }
    # Se guarda la regla exacta añadida: el undo la quita con RemoveAccessRule
    # en vez de purgar todas las reglas de la identidad.
    Add-HLManifestEntry -Type 'Acl' -Data @{
        Path = $Path; Identity = $who; Rights = 'Modify'
        Inheritance = 'ContainerInherit,ObjectInherit'; Propagation = 'None'; AccessType = 'Allow'
    }
}

# Acceso directo en Inicio > Hardline. Con -Hotkey funciona como atajo global
# (Windows solo atiende atajos de accesos directos del menú Inicio o el escritorio).
function New-HLShortcut {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Target,
        [string] $Arguments = '',
        [string] $Hotkey = '',
        [string] $Description = ''
    )
    $dir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Hardline'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lnk = Join-Path $dir "$Name.lnk"
    Backup-HLFile -Path $lnk -Reason "Acceso directo $Name" | Out-Null
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $Target
    $s.Arguments = $Arguments
    $s.WorkingDirectory = $HL.Root
    $s.Description = $Description
    if ($Hotkey) { $s.Hotkey = $Hotkey }
    $s.Save()
    return $lnk
}

function Install-HLAudioShortcuts {
    if ($HL.DryRun) { return }
    $audio = Join-Path $HL.Root 'src\audio'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    New-HLShortcut -Name 'Hardline EQ on-off' -Target (Join-Path $env:SystemRoot 'System32\wscript.exe') `
        -Arguments ('"{0}"' -f (Join-Path $audio 'eq_toggle.vbs')) -Hotkey 'CTRL+ALT+F10' `
        -Description 'Enciende/apaga el EQ de pasos. Un pitido agudo = encendido, dos graves = apagado.' | Out-Null
    New-HLShortcut -Name 'Hardline EQ' -Target $ps `
        -Arguments ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $HL.Root 'src\gui\eq_panel.ps1')) `
        -Description 'Panel del EQ de pasos: encender/apagar e intensidad. Sin administrador.' | Out-Null
    New-HLShortcut -Name 'Hardline test de pasos' -Target $ps `
        -Arguments ('-NoProfile -NoExit -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $audio 'footstep_test.ps1')) `
        -Description 'Escena de prueba (pasos + explosión) con el EQ apagado y encendido.' | Out-Null
    Write-HLSub 'Panel del EQ, atajo Ctrl+Alt+F10 y test de pasos en Inicio > Hardline' 'OK'
    Add-HLResult -Module 'Audio' -Item 'Atajos' -Status Applied -Detail 'Inicio > Hardline > "Hardline EQ" (panel: encender/apagar e intensidad). Ctrl+Alt+F10 en partida. "Hardline test de pasos" para comparar.'
}

# --------------------------------------------------------------------------
# Flujo principal
# --------------------------------------------------------------------------

function Invoke-HLAudioSetup {
    param(
        $Hardware,
        [string] $HeadsetId,
        [ValidateSet('', 'Full', 'EqOnly')] [string] $Mode = '',
        [double] $Intensity = 0,
        [switch] $CleanAudio,
        [string] $OutputDevice = '',
        [ValidateSet('', 'normal', 'pasos')] [string] $Dynamics = '',
        [switch] $HeSuVi
    )
    # Sin elección explícita se mantiene la última (config\audio.json) o "normal".
    if (-not $Dynamics) { $Dynamics = (Get-HLAudioSettings -Root $HL.Root).Dynamics }

    $db = Get-HLHeadsetProfiles -Root $HL.Root
    $sel = Select-HLHeadset -Database $db -Hardware $Hardware -Preset $HeadsetId
    $id = $sel.Id
    $hp = Resolve-HLHeadsetProfile -Database $db -Id $id -Correction $sel.Correction
    Write-HLInfo "Perfil: $($hp.name). $($hp.rationale)"

    if (-not $Mode) {
        $m = Read-HLChoice -Prompt 'Modo de audio' -Options @(
            'Completo: EQ de pasos + compresor Voicemeeter (explosiones controladas, +10-20 ms de latencia de audio)',
            'Solo EQ: EQ de pasos directo en el headset (sin latencia añadida)'
        ) -Default 0
        $Mode = if ($m -eq 0) { 'Full' } else { 'EqOnly' }
    }
    if ($Intensity -le 0) {
        $k = Read-HLChoice -Prompt 'Intensidad del EQ' -Options @(
            'Completa (preset tal cual: 2.8 kHz queda ~18 dB por encima de 1 kHz)',
            'Moderada (70%: pasos claros sin sonido tan metálico)'
        ) -Default 0
        $Intensity = if ($k -eq 0) { 1.0 } else { 0.7 }
    }
    Add-HLResult -Module 'Audio' -Item 'Perfil' -Status Info -Detail "$($hp.name), modo $Mode, intensidad $([int]($Intensity*100))%"

    # --- Audio anterior: limpieza antes de instalar -----------------------------
    $keepPreset = @("warzone_footsteps_$($hp.id).txt", "warzone_footsteps_$($hp.id)_70.txt")
    $apo0 = Get-HLEqApoDir
    $inv = Get-HLAudioInventory -ConfigDir $(if ($apo0) { Get-HLEqApoConfigDir -InstallDir $apo0 } else { '' }) -KeepHeSuVi:$HeSuVi
    if (Test-HLAudioInventoryClean -Inventory $inv -KeepPreset $keepPreset) {
        Write-HLSub 'Audio personalizado anterior' 'OK (nada que limpiar)'
    } else {
        Show-HLAudioInventory -Inventory $inv -KeepPreset $keepPreset
        $doClean = if ($HL.Unattended) { $true } else { Read-HLYesNo 'Limpiar el audio anterior antes de instalar (recomendado; lo que se aparta vuelve con el rollback)' $true }
        if ($doClean) {
            Invoke-HLSafely 'Audio' 'Limpieza del audio anterior' { Invoke-HLAudioCleanup -Inventory $inv -KeepPreset $keepPreset -AllowUninstall ([bool]$CleanAudio) -KeepHeSuVi:$HeSuVi }
        } else {
            Add-HLResult -Module 'Audio' -Item 'Audio anterior' -Status Manual -Detail 'Se mantiene: puede haber dos cadenas de EQ a la vez'
            Add-HLManualStep 'Audio' 'Mantuviste tu audio anterior. Si los pasos no suenan como en el test, vuelve a aplicar con la limpieza: puede haber dos EQ actuando a la vez.'
        }
    }

    # --- Instalación ------------------------------------------------------------
    $needed = @('EqualizerAPO')
    if ($Mode -eq 'Full') { $needed = @('VBCable', 'Voicemeeter') + $needed }
    foreach ($c in $needed) {
        $present = switch ($c) {
            'EqualizerAPO' { [bool](Get-HLEqApoDir) }
            'VBCable'      { Test-HLVBCable }
            'Voicemeeter'  { Test-HLVoicemeeterPotato }
        }
        if ($present) {
            # Potato instalado (a mano o por Hardline): el aviso de un intento fallido ya no vale.
            if ($c -eq 'Voicemeeter') { Set-HLPotatoInstallFailed -Failed $false }
            Write-HLSub "$c" 'OK (ya instalado)'; continue
        }
        $potatoPage = $script:HLAudioSources.Voicemeeter.Page
        if ($c -eq 'Voicemeeter' -and (Get-HLVoicemeeterDir) -and (Test-HLPotatoInstallFailed)) {
            $retry = if ($HL.Unattended) { $false } else { Read-HLYesNo 'La instalación de Voicemeeter Potato ya falló antes con este instalador. ¿Reintentarla? (cierra Voicemeeter mientras tanto)' $false }
            if (-not $retry) {
                Write-HLSub 'Voicemeeter Potato' 'MANUAL (falló antes; se usa tu edición actual)'
                Add-HLResult -Module 'Audio' -Item $c -Status Manual -Detail "Se usa la edición instalada. Potato: $potatoPage"
                Add-HLManualStep 'Audio' "Instala Voicemeeter Potato ($potatoPage) con Voicemeeter cerrado y vuelve a aplicar el audio: solo Potato tiene el compresor y el gate completos."
                continue
            }
        }
        Write-HLSub "Instalando $c"
        $ok = Install-HLComponent -Name $c
        if ($c -eq 'Voicemeeter') { Set-HLPotatoInstallFailed -Failed (-not $ok) }
        if ($ok) {
            Write-HLSub "$c" 'OK'
            if (-not $HL.DryRun) { Add-HLManifestEntry -Type 'Info' -Data @{ Note = "Hardline instaló $c. El rollback no desinstala software: quítalo desde Configuración > Aplicaciones si no lo quieres." } }
            Add-HLResult -Module 'Audio' -Item $c -Status Applied -Detail 'Instalado (desinstalar desde Aplicaciones si reviertes)'
        } elseif ($c -eq 'Voicemeeter' -and (Get-HLVoicemeeterDir)) {
            # Hay otra edición instalada: se sigue con ella (sin los parámetros avanzados del compresor).
            Write-HLWarn "No se pudo instalar Voicemeeter Potato; se usa tu Voicemeeter actual. Para el compresor completo instala Potato a mano: $($script:HLAudioSources[$c].Page)"
            Add-HLResult -Module 'Audio' -Item $c -Status Manual -Detail "Se usa la edición instalada. Potato: $($script:HLAudioSources[$c].Page)"
            Add-HLManualStep 'Audio' "Instala Voicemeeter Potato ($($script:HLAudioSources[$c].Page)) con Voicemeeter cerrado y vuelve a aplicar el audio: solo Potato tiene el compresor y el gate completos."
        } else {
            Write-HLErr "$c no se pudo instalar automáticamente. Descárgalo de: $($script:HLAudioSources[$c].Page)"
            Add-HLResult -Module 'Audio' -Item $c -Status Failed -Detail "Instalación manual: $($script:HLAudioSources[$c].Page)"
            if ($c -eq 'EqualizerAPO') { return }
        }
    }

    # --- HeSuVi (opcional): después de los componentes, antes del EQ ---------------
    # El EQ (Write-HLEqConfig) reescribe config.txt; HeSuVi debe estar
    # instalado antes para que su include quede en su sitio.
    $heSuViOk = $false
    if ($HeSuVi) { $heSuViOk = Install-HLHeSuVi }

    # --- Nombres e iconos de VB-CABLE y Voicemeeter --------------------------------
    # Otros programas los renombran ("Art Tune +", "Virtual Mix"): las instrucciones
    # dejan de coincidir y Voicemeeter no encuentra "CABLE Output" por su nombre.
    if (-not $HL.DryRun -and (Restore-HLCableNames) -gt 0) {
        # Voicemeeter lee la lista de dispositivos al arrancar: se reabre con los nombres nuevos.
        Get-Process -Name 'voicemeeter*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Iconos que apuntaban a lo que la limpieza acaba de apartar (ProgramData\ArtTune).
    [void](Restore-HLCableIcons)

    # --- EQ -----------------------------------------------------------------------
    $preset = Write-HLEqConfig -HeadsetProfile $hp -Intensity $Intensity -WithHeSuVi:$heSuViOk
    $pre = Get-HLAutoPreamp -Filters @(Get-HLChainFilters -HeadsetProfile $hp -Intensity $Intensity)
    if (-not $HL.DryRun) { Save-HLAudioSettings -Root $HL.Root -Set @{ HeadsetId = "$($hp.vmProfileId)"; PreampDb = [double]$pre; Dynamics = $Dynamics; Overrides = $hp.voicemeeter } }
    Write-HLSub "Preset EQ ($preset, preamp $pre dB)" 'OK'
    Add-HLResult -Module 'Audio' -Item 'Preset EQ APO' -Status Applied -Detail "$preset (preamp automático $pre dB)"
    Invoke-HLSafely 'Audio' 'Atajos de audio' { Install-HLAudioShortcuts }

    $target = if ($Mode -eq 'Full') { 'CABLE Input (VB-Audio Virtual Cable)' } else { 'tu headset' }
    $devAdvice = Get-HLEqApoDeviceAdvice -Devices @(Get-HLEqApoDevices) -Mode $Mode
    if ($devAdvice) { Write-HLWarn $devAdvice; Add-HLManualStep 'Audio' $devAdvice }
    $apo = Get-HLEqApoDir
    if ($apo -and -not $HL.DryRun -and -not $HL.Unattended) {
        Write-HLWarn "En el Configurator de Equalizer APO marca SOLO: $target. Después pulsa OK y cierra."
        $cfgExe = Join-Path $apo 'Configurator.exe'
        if (Test-Path $cfgExe) { Start-Process -FilePath $cfgExe -Wait }
        $HL.NeedsReboot = $true
    }
    Add-HLManualStep 'Audio' "En el Configurator de Equalizer APO deja marcado solo $target, pulsa OK y reinicia." '' 'eqapo-configurator'

    # --- Voicemeeter ----------------------------------------------------------------
    if ($Mode -eq 'Full') {
        $dev = Select-HLRenderDevice -HeadsetId $id -Database $db -Preferred $OutputDevice
        if (-not $dev) {
            Write-HLWarn 'No se encontró ningún dispositivo de salida para A1.'
            Add-HLResult -Module 'Audio' -Item 'Voicemeeter' -Status Failed -Detail 'Sin dispositivo de salida'
        } else {
            Invoke-HLVoicemeeterPhase -HeadsetProfile $hp -HeadsetDevice $dev -Dynamics $Dynamics -PreampDb ([double]$pre)
        }
        # Banana / Potato: fuera de las listas los dispositivos virtuales que nadie usa (revertible).
        [void](Hide-HLUnusedVaioEndpoints)
        Add-HLManualStep 'Audio' 'En Salida elige "Voicemeeter Input". Así Discord y el resto suenan por Voicemeeter, sin el EQ del juego.' '' 'sound-settings'
        Add-HLManualStep 'Audio' 'Con Warzone abierto, en el Mezclador de volumen busca cod.exe y en Dispositivo de salida elige "CABLE Input". Windows lo recuerda.' '' 'volume-mixer'
    }

    Add-HLManualStep 'Audio' 'Doble clic en tu headset > pestaña Mejoras: desactívalas. Pestaña Audio espacial: Desactivado. Warzone ya hace su propio 3D; dos a la vez estropean la dirección de los pasos.' '' 'sound-playback'
    Add-HLManualStep 'Audio' 'Software del headset (G HUB, iCUE, NGENUITY, SteelSeries GG, Synapse): EQ plano y 7.1 virtual desactivado. El EQ lo hace Hardline.'
    if ($heSuViOk) {
        Add-HLManualStep 'Audio' 'HeSuVi: elige un perfil HRIR (prueba "ooyh_0") y pulsa Actions > Restart Audio Service. No hace falta reiniciar.' '' 'hesuvi'
        Add-HLManualStep 'Audio' 'Pon tu headset en 7.1: selecciónalo > Configurar > "7.1 Surround" > Siguiente hasta Finalizar. Si no aparece 7.1, en HeSuVi > Additional > Matrix Upmix activa Stereo y 5.1.' '' 'sound-playback'
        Add-HLManualStep 'Audio' 'Warzone > Audio: salida 7.1 / Home Theater (no "Auriculares"). HeSuVi necesita los 8 canales para crear el sonido 3D.'
        Add-HLManualStep 'Audio' 'Con HeSuVi, el EQ de pasos de Hardline sigue aplicando encima (va después en config.txt). Ctrl+Alt+F10 apaga solo el EQ, la virtualización queda.'
    } else {
        Add-HLManualStep 'Audio' 'Warzone > Audio: Mezcla "Auriculares", volumen de música y diálogo a 0, efectos al 100%. Si aparece "Reducción del sonido de tinnitus", actívala: quita el pitido tras explosiones cercanas.'
    }
    Add-HLManualStep 'Audio' 'Pasos más altos y disparos más bajos: en Hardline EQ > Compresor elige "Pasos al máximo". Se aplica al momento; compáralo en partida con "Normal".' '' 'eq-panel'
    Add-HLManualStep 'Audio' 'Tras reiniciar, haz el test de pasos: suena la misma escena sin y con EQ; en la segunda, los pasos de la izquierda deben destacar sobre la explosión. En partida, Ctrl+Alt+F10 enciende/apaga el EQ.' '' 'footstep-test'
}

function Invoke-HLVoicemeeterPhase {
    param([Parameter(Mandatory)] $HeadsetProfile, [Parameter(Mandatory)] [string] $HeadsetDevice, [string] $Dynamics = 'normal', [double] $PreampDb = 0)

    $xml = Join-Path $HL.Root 'src\audio\configs\voicemeeter_comp.xml'
    if ($HL.DryRun) { Write-HLSub 'Voicemeeter' 'SKIP (DryRun)'; return }

    $vmDir = Get-HLVoicemeeterDir
    $cableReady = Test-HLVBCable
    $applied = $false
    if ($vmDir -and $cableReady) {
        try {
            $r = Set-HLVoicemeeterConfig -XmlPath $xml -HeadsetDevice $HeadsetDevice -Overrides $HeadsetProfile.voicemeeter -Dynamics $Dynamics -PreampDb $PreampDb
            if ($r.Failed.Count -gt 0) { Write-HLWarn ("Parámetros rechazados por Voicemeeter: " + ($r.Failed -join ', ')) }
            $vm = $HeadsetProfile.voicemeeter
            Write-HLSub ("Voicemeeter: gate {0} dB, comp {1}:1 @ {2} dB, {3}/{4} ms, makeup +{5} dB" -f $vm.gate_threshold_db, $vm.comp_ratio, $vm.comp_threshold_db, $vm.comp_attack_ms, $vm.comp_release_ms, $vm.comp_makeup_db) 'OK'
            Add-HLResult -Module 'Audio' -Item 'Voicemeeter' -Status Applied -Detail "A1 = $HeadsetDevice, $($r.Statements) parámetros"
            $applied = $true
        } catch {
            Write-HLLog WARN "Voicemeeter no configurable ahora: $($_.Exception.Message)"
        }
    }

    if (-not $applied) {
        # Drivers recién instalados: los dispositivos aparecen tras reiniciar.
        $cmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -ConfigureVoicemeeter -HeadsetId {2} -HeadsetDevice "{3}"' -f `
            (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), (Join-Path $HL.Root 'src\audio\setup.ps1'), $HeadsetProfile.vmProfileId, $HeadsetDevice
        Set-HLRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'HardlineVoicemeeter' -Value $cmd -Type String -Reason 'Configura Voicemeeter tras reiniciar' | Out-Null
        Write-HLSub 'Voicemeeter' 'Se configura solo tras reiniciar'
        Add-HLResult -Module 'Audio' -Item 'Voicemeeter' -Status Applied -Detail 'Pendiente de reinicio (RunOnce)'
        $HL.NeedsReboot = $true
    }

    # Voicemeeter debe arrancar con Windows o el juego se queda sin audio.
    # Se apunta a la edición instalada (no siempre Potato).
    $exe = if ($vmDir) { Get-HLVoicemeeterExe -Dir $vmDir } else { $null }
    if ($exe) {
        Set-HLRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'HardlineVoicemeeter' -Value ('"{0}"' -f $exe) -Type String -Reason 'Voicemeeter al iniciar sesión' | Out-Null
    } elseif ($vmDir) {
        Write-HLWarn "No se encontró el ejecutable de Voicemeeter en ${vmDir}: no arrancará con Windows."
        Add-HLManualStep 'Audio' 'Voicemeeter no arranca solo con Windows: en su Menú activa "Run on Windows Startup", o el juego se queda sin audio tras reiniciar.' '' 'voicemeeter'
    }
}

# --------------------------------------------------------------------------
# Ejecución directa del script
# --------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    . (Join-Path $script:AudioRoot 'src\core\common.ps1')
    . (Join-Path $script:AudioRoot 'src\core\detector.ps1')

    if ($ConfigureVoicemeeter) {
        # Fase 2 (tras reinicio, sin admin): solo Voicemeeter. No crea backup nuevo;
        # los cambios del registro ya están en el manifiesto de la sesión original.
        Initialize-HLSession -Root $script:AudioRoot -NoBackup
        $db = Get-HLHeadsetProfiles -Root $script:AudioRoot
        $hp = Resolve-HLHeadsetProfile -Database $db -Id $HeadsetId
        Write-HLStep 'Hardline: configurando Voicemeeter (una sola vez, tras reiniciar)...'
        Write-HLInfo 'Esperando a que Windows cargue VB-CABLE...'
        for ($i = 0; $i -lt 10 -and -not (Test-HLVBCable); $i++) { Start-Sleep -Seconds 3 }
        $vmDir = Get-HLVoicemeeterDir
        if (-not $vmDir) {
            Write-HLErr 'Voicemeeter no está instalado. Abre Hardline y aplica el audio otra vez.'
            Start-Sleep -Seconds 15
            return
        }
        # La configuración va en un proceso aparte con tiempo límite: si Voicemeeter
        # no responde, esta ventana no se queda abierta para siempre.
        Write-HLInfo 'Abriendo Voicemeeter y aplicando el compresor (máximo 90 s)...'
        $job = Start-Job -ArgumentList $script:AudioRoot, $HeadsetDevice, $HeadsetId -ScriptBlock {
            param($root, $device, $id)
            . (Join-Path $root 'src\core\common.ps1')
            . (Join-Path $root 'src\audio\setup.ps1')
            Initialize-HLSession -Root $root -NoBackup -Unattended
            $db = Get-HLHeadsetProfiles -Root $root
            $p = Resolve-HLHeadsetProfile -Database $db -Id $id
            $st = Get-HLAudioSettings -Root $root
            $r = Set-HLVoicemeeterConfig -XmlPath (Join-Path $root 'src\audio\configs\voicemeeter_comp.xml') -HeadsetDevice $device -Overrides $p.voicemeeter -Dynamics $st.Dynamics -PreampDb $st.PreampDb
            [pscustomobject]@{ Type = $r.Type; Statements = $r.Statements; Failed = @($r.Failed) }
        }
        $done = Wait-Job $job -Timeout 90
        if (-not $done) {
            Stop-Job $job -ErrorAction SilentlyContinue
            Write-HLErr 'Voicemeeter no respondió en 90 s.'
            Write-HLInfo 'Abre Voicemeeter a mano y aplica el audio desde Hardline: se configura en ese momento.'
        } else {
            try {
                $r = Receive-Job $job -ErrorAction Stop | Select-Object -Last 1
                if (-not $r) { throw 'sin resultado' }
                $ed = switch ($r.Type) { 1 { 'Voicemeeter' } 2 { 'Banana' } 3 { 'Potato' } default { "tipo $($r.Type)" } }
                Write-HLOk "Voicemeeter $ed configurado: $($r.Statements) parámetros, A1 = $HeadsetDevice."
                if (@($r.Failed).Count) { Write-HLWarn "Parámetros que Voicemeeter no aceptó: $(@($r.Failed).Count) (normal si no es Potato)." }
            } catch {
                Write-HLErr "No se pudo configurar Voicemeeter: $($_.Exception.Message)"
                Write-HLInfo 'Abre Voicemeeter a mano y aplica el audio desde Hardline.'
            }
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-HLInfo 'Esta ventana se cierra sola en 10 s.'
        Start-Sleep -Seconds 10
        return
    }

    if (-not (Test-HLAdmin)) { Write-Host '[x] Ejecuta como administrador.' -ForegroundColor Red; return }
    Initialize-HLSession -Root $script:AudioRoot
    Show-HLBanner
    Write-HLStep 'Audio competitivo'
    Invoke-HLAudioSetup -HeadsetId $HeadsetId
    Write-Host ''
    Write-HLOk "Backup y manifiesto: $($HL.BackupDir)"
    foreach ($m in $HL.Manual) { Write-HLInfo "[$($m.Area)] $($m.Text)" }
    if ($HL.NeedsReboot) { Write-HLWarn 'Reinicia para que Equalizer APO y los drivers de audio se carguen.' }
}

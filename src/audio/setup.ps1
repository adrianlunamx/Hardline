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

# Fuentes de descarga. Voicemeeter con hash fijado (mismo que el manifiesto de
# winget VB-Audio.Voicemeeter.Potato 3.1.2.2). EQ APO y Peace vienen de
# SourceForge (proyectos oficiales); VB-Cable de vb-audio.com.
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
    Peace = @{
        Urls   = @('https://sourceforge.net/projects/peace-equalizer-apo-extension/files/latest/download')
        Page   = 'https://sourceforge.net/projects/peace-equalizer-apo-extension/'
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

function Test-HLPeace {
    foreach ($r in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        $hit = Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -match '^Peace' }
        if ($hit) { return $true }
    }
    return $false
}

# --------------------------------------------------------------------------
# Instalación
# --------------------------------------------------------------------------

function Get-HLTempDir {
    $d = Join-Path $env:TEMP 'Hardline'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Install-HLComponent {
    param([Parameter(Mandatory)] [ValidateSet('Voicemeeter', 'VBCable', 'EqualizerAPO', 'Peace')] [string] $Name)

    $src = $script:HLAudioSources[$Name]
    $tmp = Get-HLTempDir
    if ($HL.DryRun) { Write-HLSub "Instalar $Name" 'SKIP (DryRun)'; return $true }

    switch ($Name) {
        'Voicemeeter' {
            $zip = Join-Path $tmp 'voicemeeter.zip'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $zip -Sha256 $src.Sha256 -ExpectZip)) { return $false }
            $x = Join-Path $tmp 'voicemeeter'
            Expand-Archive -Path $zip -DestinationPath $x -Force
            $exe = Get-ChildItem $x -Recurse -Filter 'Voicemeeter8Setup.exe' | Select-Object -First 1
            if (-not $exe) { $exe = Get-ChildItem $x -Recurse -Filter '*Setup*.exe' | Select-Object -First 1 }
            if (-not $exe) { return $false }
            # -install = instalación silenciosa (código de salida 1 = OK, según el manifiesto de winget).
            $p = Start-Process -FilePath $exe.FullName -ArgumentList '-install' -Wait -PassThru
            $HL.NeedsReboot = $true
            return ($p.ExitCode -in @(0, 1))
        }
        'VBCable' {
            $zip = Join-Path $tmp 'vbcable.zip'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $zip -ExpectZip)) { return $false }
            $x = Join-Path $tmp 'vbcable'
            Expand-Archive -Path $zip -DestinationPath $x -Force
            $exe = Get-ChildItem $x -Recurse -Filter 'VBCABLE_Setup_x64.exe' | Select-Object -First 1
            if (-not $exe) { return $false }
            Write-HLInfo 'Se abre el instalador de VB-CABLE: pulsa "Install Driver" y acepta el aviso de Windows.'
            $p = Start-Process -FilePath $exe.FullName -Wait -PassThru -Verb RunAs
            $HL.NeedsReboot = $true
            return $true
        }
        'EqualizerAPO' {
            $exe = Join-Path $tmp 'EqualizerAPO-setup.exe'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $exe -ExpectPE)) { return $false }
            Write-HLInfo 'Se abre el instalador de Equalizer APO. Al final aparece el Configurator: NO marques nada todavía, Hardline te dirá qué dispositivo.'
            $p = Start-Process -FilePath $exe -Wait -PassThru
            $HL.NeedsReboot = $true
            return [bool](Get-HLEqApoDir)
        }
        'Peace' {
            $exe = Join-Path $tmp 'PeaceSetup.exe'
            if (-not (Invoke-HLDownload -Urls $src.Urls -OutFile $exe -ExpectPE)) { return $false }
            $p = Start-Process -FilePath $exe -Wait -PassThru
            return (Test-HLPeace)
        }
    }
}

# --------------------------------------------------------------------------
# Selección de headset y modo
# --------------------------------------------------------------------------

function Select-HLHeadset {
    param([Parameter(Mandatory)] $Database, $Hardware, [string]$Preset)

    $all = @($Database.headsets) + @($Database.base)
    if ($Preset) {
        $hit = $all | Where-Object { $_.id -eq $Preset } | Select-Object -First 1
        if ($hit) { return $hit.id }
        Write-HLWarn "Headset '$Preset' no existe en headsets.json; se pregunta."
    }

    $eps = if ($Hardware) { $Hardware.Audio } else { @(Get-HLAudioEndpoints) }
    $det = Find-HLHeadset -Profiles $Database.headsets -Endpoints $eps
    $default = $all.Count - 1
    if ($det) {
        $idx = [array]::IndexOf(@($all | ForEach-Object { $_.id }), $det.Id)
        if ($idx -ge 0) { $default = $idx }
        Write-HLOk "Headset detectado: $($det.DeviceName)"
    }
    $labels = $all | ForEach-Object {
        $meta = if ($_.driver_mm) { " ({0} mm, {1} ohm, {2})" -f $_.driver_mm, $_.impedance_ohm, $_.design } else { '' }
        "$($_.name)$meta"
    }
    $i = Read-HLChoice -Prompt '¿Qué headset tienes?' -Options $labels -Default $default
    return $all[$i].id
}

function Select-HLRenderDevice {
    param([Parameter(Mandatory)] [string] $HeadsetId, $Database)

    $render = @(Get-HLAudioEndpoints | Where-Object { $_.Render -and $_.Name -notmatch 'CABLE|Voicemeeter|VB-Audio' })
    if ($render.Count -eq 0) { return $null }
    $h = @($Database.headsets | Where-Object { $_.id -eq $HeadsetId }) | Select-Object -First 1
    $default = 0
    if ($h) {
        for ($i = 0; $i -lt $render.Count; $i++) {
            foreach ($pat in @($h.match)) { if ($render[$i].Name -match $pat) { $default = $i; break } }
        }
    }
    if ($render.Count -eq 1) { return $render[0].Name }
    $i = Read-HLChoice -Prompt 'Dispositivo de salida del headset (A1 de Voicemeeter)' -Options @($render | ForEach-Object { $_.Name }) -Default $default
    return $render[$i].Name
}

# --------------------------------------------------------------------------
# Equalizer APO
# --------------------------------------------------------------------------

function Write-HLEqConfig {
    param([Parameter(Mandatory)] $HeadsetProfile, [double]$Intensity = 1.0)

    $apo = Get-HLEqApoDir
    if (-not $apo) { throw 'Equalizer APO no está instalado.' }
    $cfgDir = Get-HLEqApoConfigDir -InstallDir $apo
    $hlDir = Join-Path $cfgDir 'hardline'
    if (-not (Test-Path $hlDir) -and -not $HL.DryRun) { New-Item -ItemType Directory -Path $hlDir -Force | Out-Null }

    $presetName = "warzone_footsteps_$($HeadsetProfile.id).txt"
    $presetPath = Join-Path $hlDir $presetName
    $text = ConvertTo-HLEqApoText -HeadsetProfile $HeadsetProfile -Title 'Warzone footsteps' -Intensity $Intensity
    $configPath = Join-Path $cfgDir 'config.txt'

    $config = @(
        '# Hardline - Equalizer APO'
        '# Backup del config.txt anterior en la carpeta backups/ de Hardline.'
        '# Desactivar el EQ sin desinstalar: comenta la línea Include con #.'
        ''
        "Include: hardline\$presetName"
    ) -join "`r`n"

    if ($HL.DryRun) { return $presetPath }

    Backup-HLFile -Path $presetPath -Reason 'Preset EQ de Hardline' | Out-Null
    [IO.File]::WriteAllText($presetPath, $text.Replace("`r`n", "`n").Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
    Backup-HLFile -Path $configPath -Reason 'config.txt de Equalizer APO' | Out-Null
    [IO.File]::WriteAllText($configPath, (ConvertTo-HLAscii $config), (New-Object Text.UTF8Encoding($false)))
    return $presetPath
}

# --------------------------------------------------------------------------
# Flujo principal
# --------------------------------------------------------------------------

function Invoke-HLAudioSetup {
    param(
        $Hardware,
        [string] $HeadsetId,
        [ValidateSet('', 'Full', 'EqOnly')] [string] $Mode = '',
        [double] $Intensity = 0
    )

    $db = Get-HLHeadsetProfiles -Root $HL.Root
    $id = Select-HLHeadset -Database $db -Hardware $Hardware -Preset $HeadsetId
    $hp = Resolve-HLHeadsetProfile -Database $db -Id $id
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

    # --- Instalación ------------------------------------------------------------
    $needed = @('EqualizerAPO')
    if ($Mode -eq 'Full') { $needed = @('VBCable', 'Voicemeeter') + $needed }
    foreach ($c in $needed) {
        $present = switch ($c) {
            'EqualizerAPO' { [bool](Get-HLEqApoDir) }
            'VBCable'      { Test-HLVBCable }
            'Voicemeeter'  { [bool](Get-HLVoicemeeterDir) }
        }
        if ($present) { Write-HLSub "$c" 'OK (ya instalado)'; continue }
        Write-HLSub "Instalando $c"
        $ok = Install-HLComponent -Name $c
        if ($ok) {
            Write-HLSub "$c" 'OK'
            if (-not $HL.DryRun) { Add-HLManifestEntry -Type 'Info' -Data @{ Note = "Hardline instaló $c. El rollback no desinstala software: quítalo desde Configuración > Aplicaciones si no lo quieres." } }
            Add-HLResult -Module 'Audio' -Item $c -Status Applied -Detail 'Instalado (desinstalar desde Aplicaciones si reviertes)'
        } else {
            Write-HLErr "$c no se pudo instalar automáticamente. Descárgalo de: $($script:HLAudioSources[$c].Page)"
            Add-HLResult -Module 'Audio' -Item $c -Status Failed -Detail "Instalación manual: $($script:HLAudioSources[$c].Page)"
            if ($c -eq 'EqualizerAPO') { return }
        }
    }
    if (-not (Test-HLPeace)) {
        Write-HLInfo 'Peace es una interfaz gráfica para EQ APO. Útil para ver la curva; si guardas un preset desde Peace, reemplaza el de Hardline.'
        if (Read-HLYesNo '¿Instalar Peace?' $true) {
            if (Install-HLComponent -Name 'Peace') { Add-HLResult -Module 'Audio' -Item 'Peace' -Status Applied -Detail 'Instalado' }
            else { Add-HLResult -Module 'Audio' -Item 'Peace' -Status Failed -Detail $script:HLAudioSources.Peace.Page }
        }
    }

    # --- EQ -----------------------------------------------------------------------
    $preset = Write-HLEqConfig -HeadsetProfile $hp -Intensity $Intensity
    $pre = Get-HLAutoPreamp -Filters @(Get-HLScaledFilters -Filters $hp.filters -Intensity $Intensity)
    Write-HLSub "Preset EQ ($preset, preamp $pre dB)" 'OK'
    Add-HLResult -Module 'Audio' -Item 'Preset EQ APO' -Status Applied -Detail "$preset (preamp automático $pre dB)"

    $target = if ($Mode -eq 'Full') { 'CABLE Input (VB-Audio Virtual Cable)' } else { 'tu headset' }
    $apo = Get-HLEqApoDir
    if ($apo -and -not $HL.DryRun -and -not $HL.Unattended) {
        Write-HLWarn "En el Configurator de Equalizer APO marca SOLO: $target. Después pulsa OK y cierra."
        $cfgExe = Join-Path $apo 'Configurator.exe'
        if (Test-Path $cfgExe) { Start-Process -FilePath $cfgExe -Wait }
        $HL.NeedsReboot = $true
    }
    Add-HLManualStep 'Audio' "Equalizer APO Configurator: el único dispositivo marcado debe ser $target. Reinicia después."

    # --- Voicemeeter ----------------------------------------------------------------
    if ($Mode -eq 'Full') {
        $dev = Select-HLRenderDevice -HeadsetId $id -Database $db
        if (-not $dev) {
            Write-HLWarn 'No se encontró ningún dispositivo de salida para A1.'
            Add-HLResult -Module 'Audio' -Item 'Voicemeeter' -Status Failed -Detail 'Sin dispositivo de salida'
        } else {
            Invoke-HLVoicemeeterPhase -HeadsetProfile $hp -HeadsetDevice $dev
        }
        Add-HLManualStep 'Audio' 'Configuración > Sistema > Sonido > Salida: "Voicemeeter Input". Así Discord y el resto pasan por Voicemeeter sin procesar.'
        Add-HLManualStep 'Audio' 'Con Warzone abierto: Configuración > Sistema > Sonido > Mezclador de volumen > cod.exe > Dispositivo de salida: "CABLE Input". Windows lo recuerda para siguientes sesiones.'
    }

    Add-HLManualStep 'Audio' 'Propiedades del headset en Windows: desactiva "Mejoras de audio" y "Audio espacial" (Windows Sonic/Dolby). Warzone ya aplica su propio HRTF; apilar virtualizadores destruye la localización.'
    Add-HLManualStep 'Audio' 'Software del headset (G HUB, iCUE, NGENUITY, SteelSeries GG, Synapse): EQ plano y 7.1 virtual desactivado. El EQ lo hace Hardline.'
    Add-HLManualStep 'Audio' 'Warzone > Audio: Mezcla "Auriculares", volumen de música y diálogo a 0, efectos al 100%.'
}

function Invoke-HLVoicemeeterPhase {
    param([Parameter(Mandatory)] $HeadsetProfile, [Parameter(Mandatory)] [string] $HeadsetDevice)

    $xml = Join-Path $HL.Root 'src\audio\configs\voicemeeter_comp.xml'
    if ($HL.DryRun) { Write-HLSub 'Voicemeeter' 'SKIP (DryRun)'; return }

    $vmDir = Get-HLVoicemeeterDir
    $cableReady = Test-HLVBCable
    $applied = $false
    if ($vmDir -and $cableReady) {
        try {
            $r = Set-HLVoicemeeterConfig -XmlPath $xml -HeadsetDevice $HeadsetDevice -Overrides $HeadsetProfile.voicemeeter
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
            (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), (Join-Path $HL.Root 'src\audio\setup.ps1'), $HeadsetProfile.id, $HeadsetDevice
        Set-HLRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'HardlineVoicemeeter' -Value $cmd -Type String -Reason 'Configura Voicemeeter tras reiniciar' | Out-Null
        Write-HLSub 'Voicemeeter' 'Se configura solo tras reiniciar'
        Add-HLResult -Module 'Audio' -Item 'Voicemeeter' -Status Applied -Detail 'Pendiente de reinicio (RunOnce)'
        $HL.NeedsReboot = $true
    }

    # Voicemeeter debe arrancar con Windows o el juego se queda sin audio.
    if ($vmDir) {
        $exe = Join-Path $vmDir 'voicemeeter8x64.exe'
        if (-not (Test-Path $exe)) { $exe = Join-Path $vmDir 'voicemeeter8.exe' }
        Set-HLRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'HardlineVoicemeeter' -Value ('"{0}"' -f $exe) -Type String -Reason 'Voicemeeter al iniciar sesión' | Out-Null
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
        Write-HLStep 'Hardline: configurando Voicemeeter...'
        for ($i = 0; $i -lt 10 -and -not (Test-HLVBCable); $i++) { Start-Sleep -Seconds 3 }
        try {
            $r = Set-HLVoicemeeterConfig -XmlPath (Join-Path $script:AudioRoot 'src\audio\configs\voicemeeter_comp.xml') -HeadsetDevice $HeadsetDevice -Overrides $hp.voicemeeter
            Write-HLOk "Voicemeeter configurado ($($r.Statements) parámetros, A1 = $HeadsetDevice)."
        } catch {
            Write-HLErr "No se pudo configurar Voicemeeter: $($_.Exception.Message)"
            Write-HLInfo 'Vuelve a lanzar este mismo comando cuando Voicemeeter esté abierto.'
        }
        Start-Sleep -Seconds 5
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

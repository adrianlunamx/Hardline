#Requires -Version 5.1
<#
    Hardline - tweaks de registro.

    Cada entrada declara qué hace y por qué. Todas pasan por Set-HLRegistryValue,
    que guarda el valor anterior en el manifiesto. No hay tweaks "por si acaso":
    si algo no tiene efecto medible o documentado, no está aquí (ver
    docs/TWEAKS_EXPLAINED.md, sección "Lo que Hardline NO hace").
#>

function Get-HLRegistryPlan {
    param($Hardware)

    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $plan = New-Object System.Collections.Generic.List[object]
    function Add-Tweak($Group, $Path, $Name, $Value, $Type, $Why) {
        $plan.Add([pscustomobject]@{ Group = $Group; Path = $Path; Name = $Name; Value = $Value; Type = $Type; Why = $Why })
    }

    # --- Game Bar / Game DVR -------------------------------------------------
    # La grabación en segundo plano de Game DVR mantiene un encoder activo.
    Add-Tweak 'Game Bar' 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 DWord 'Desactiva la captura en segundo plano de Game DVR.'
    Add-Tweak 'Game Bar' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 DWord 'Desactiva la captura de apps.'
    Add-Tweak 'Game Bar' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 DWord 'Política: Game DVR no disponible para ningún usuario.'
    Add-Tweak 'Game Bar' 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0 DWord 'Win+G / botón Xbox del mando ya no abren el overlay.'
    Add-Tweak 'Game Bar' 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0 DWord 'Sin panel de bienvenida al iniciar un juego.'

    # --- Game Mode ON ----------------------------------------------------------
    # Game Mode en Win10 2004+ / Win11 limita Windows Update y prioriza el
    # proceso en primer plano. El efecto se nota en 1% lows cuando hay actividad
    # de fondo (updates, indexado); con el sistema en reposo es neutro.
    Add-Tweak 'Game Mode' 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 DWord 'Game Mode activo.'
    Add-Tweak 'Game Mode' 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 DWord 'Game Mode activo (clave antigua, Win10).'

    # --- HAGS OFF (solo Radeon) ------------------------------------------------
    # HwSchMode: 1 = off, 2 = on. Con RDNA2 y Warzone, HAGS off da frametimes
    # más estables en la mayoría de drivers Adrenalin. Requiere reinicio.
    # En NVIDIA e Intel no se toca: su Frame Generation lo necesita activado y
    # con sus drivers actuales no hay ventaja medible en apagarlo.
    $vendor = if ($Hardware -and $Hardware.GPU.Primary) { $Hardware.GPU.Primary.Vendor } else { '' }
    if ($vendor -eq 'AMD') {
        Add-Tweak 'HAGS' 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 DWord 'Hardware-accelerated GPU scheduling OFF (reinicio necesario).'
    }

    # --- MMCSS ---------------------------------------------------------------
    # SystemResponsiveness: % de CPU reservado para tareas de baja prioridad
    # cuando hay tareas MMCSS activas. Por defecto 20. 10 es el mínimo efectivo:
    # según la documentación de MMCSS, 0 se trata como 10 y el resto se redondea
    # a múltiplos de 10. Por eso aquí no se pone 0 como en otras guías.
    # https://learn.microsoft.com/windows/win32/procthread/multimedia-class-scheduler-service
    Add-Tweak 'MMCSS' $mm 'SystemResponsiveness' 10 DWord 'Reserva de CPU para procesos de fondo: 20% -> 10%.'
    Add-Tweak 'MMCSS' "$mm\Tasks\Games" 'GPU Priority' 8 DWord 'Prioridad GPU de la clase MMCSS "Games".'
    Add-Tweak 'MMCSS' "$mm\Tasks\Games" 'Priority' 6 DWord 'Prioridad de hilo de la clase "Games".'
    Add-Tweak 'MMCSS' "$mm\Tasks\Games" 'Scheduling Category' 'High' String 'Categoría de planificación alta.'
    Add-Tweak 'MMCSS' "$mm\Tasks\Games" 'SFIO Priority' 'High' String 'Prioridad de I/O alta.'

    # --- Power throttling ------------------------------------------------------
    # EcoQoS / Power Throttling puede aparcar procesos en segundo plano en núcleos
    # lentos. En desktop no aporta y puede afectar a Discord/overlays que se
    # ejecutan junto al juego.
    Add-Tweak 'Energía' 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 DWord 'Desactiva Power Throttling (EcoQoS).'

    # --- Bloat ---------------------------------------------------------------
    Add-Tweak 'Bloat' 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 DWord 'Widgets (Win11) desactivados por política.'
    Add-Tweak 'Bloat' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 DWord 'Noticias e intereses (Win10) desactivados.'
    Add-Tweak 'Bloat' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 DWord 'Cortana desactivada por política.'
    Add-Tweak 'Bloat' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1 DWord 'Búsqueda web en Inicio desactivada.'
    Add-Tweak 'Bloat' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 DWord 'Sin resultados de Bing en Inicio.'

    # --- GPU por ejecutable ----------------------------------------------------
    # Ryzen 7000 trae iGPU. Si está activa, Windows puede decidir mal qué GPU usa
    # un juego con varios monitores. GpuPreference=2 fuerza la de alto rendimiento.
    if ($Hardware -and $Hardware.Game.Primary -and $Hardware.GPU.HasIGPUActive) {
        foreach ($exe in $Hardware.Game.Paths) {
            Add-Tweak 'GPU' 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $exe 'GpuPreference=2;' String 'cod.exe usa siempre la GPU dedicada.'
        }
    }

    return $plan
}

function Invoke-HLRegistry {
    param($Hardware)

    Write-HLSub 'Aplicando tweaks de registro'
    $applied = 0
    foreach ($t in (Get-HLRegistryPlan -Hardware $Hardware)) {
        try {
            $changed = Set-HLRegistryValue -Path $t.Path -Name $t.Name -Value $t.Value -Type $t.Type -Reason $t.Why
            $label = "$($t.Group): $($t.Name)"
            if ($changed) { $applied++; Add-HLResult -Module 'Registro' -Item $label -Status Applied -Detail $t.Why }
            else { Add-HLResult -Module 'Registro' -Item $label -Status Skipped -Detail 'Ya tenía el valor objetivo' }
            if ($t.Name -eq 'HwSchMode' -and $changed) { $HL.NeedsReboot = $true }
        } catch {
            Add-HLResult -Module 'Registro' -Item "$($t.Group): $($t.Name)" -Status Failed -Detail $_.Exception.Message
            Write-HLLog ERROR "Registro $($t.Path)\$($t.Name): $($_.Exception.Message)"
        }
    }
    Write-HLSub "Tweaks de registro aplicados: $applied" 'OK'

    Invoke-HLAppxBloat
}

<#
    Desinstala Xbox Game Bar y Cortana para el usuario actual.
    No es reversible desde el manifiesto (Windows no permite reinstalar AppX
    sin la Store), así que se pregunta y se deja anotado cómo reinstalar.
#>
function Invoke-HLAppxBloat {
    $targets = @(
        [pscustomobject]@{ Package = 'Microsoft.XboxGamingOverlay'; Label = 'Xbox Game Bar'; Store = 'https://apps.microsoft.com/detail/9nzkpstsnw4p' }
        [pscustomobject]@{ Package = 'Microsoft.549981C3F5F10';     Label = 'Cortana';       Store = 'https://apps.microsoft.com/detail/9nffx4szz23l' }
    )
    $present = @($targets | Where-Object { Get-AppxPackage -Name $_.Package -ErrorAction SilentlyContinue })
    if ($present.Count -eq 0) {
        Add-HLResult -Module 'Bloat' -Item 'AppX' -Status Skipped -Detail 'Game Bar y Cortana no están instalados'
        return
    }

    $names = ($present | ForEach-Object { $_.Label }) -join ', '
    Write-HLInfo "Instalado: $names. Las políticas de arriba ya los neutralizan; desinstalar libera además sus procesos."
    if (-not (Read-HLYesNo "¿Desinstalar $names? (se reinstala desde la Store)" $false)) {
        foreach ($p in $present) { Add-HLResult -Module 'Bloat' -Item $p.Label -Status Skipped -Detail 'Usuario eligió conservarlo' }
        return
    }
    foreach ($p in $present) {
        if ($HL.DryRun) { Add-HLResult -Module 'Bloat' -Item $p.Label -Status Skipped -Detail 'DryRun'; continue }
        try {
            Get-AppxPackage -Name $p.Package | Remove-AppxPackage -ErrorAction Stop
            Add-HLManifestEntry -Type 'Info' -Data @{ Note = "AppX $($p.Package) desinstalado. Reinstalar: $($p.Store)" }
            Add-HLResult -Module 'Bloat' -Item $p.Label -Status Applied -Detail "Desinstalado. Reinstalar: $($p.Store)"
        } catch {
            Add-HLResult -Module 'Bloat' -Item $p.Label -Status Failed -Detail $_.Exception.Message
        }
    }
}

#Requires -Version 5.1
<#
    Hardline - GPU AMD Radeon.

    Qué hace automáticamente (solo lectura):
      - Versión y antigüedad del driver.
      - Estado real de SAM / Resizable BAR (tamaño de la apertura de memoria
        PCIe de la GPU, sin depender de Adrenalin).
      - Crashes/TDR del driver en los últimos 14 días (Event ID 4101), para
        validar un undervolt.

    Qué NO hace automáticamente: cambiar ajustes de Adrenalin (Anti-Lag, Chill,
    RIS, undervolt). AMD no publica una API para ello y escribir las claves
    internas del driver es frágil entre versiones y puede dejar el perfil
    corrupto. Se generan instrucciones exactas en el reporte.
#>

# Get-HLRebarState, Get-HLDisplayCrashes y Get-HLRebarBiosPath: src/modules/gpu/shared.ps1

function Invoke-HLAmdGpu {
    param([Parameter(Mandatory)] $Hardware)

    $gpu = $Hardware.GPU.Primary
    if (-not $gpu -or $gpu.Vendor -ne 'AMD' -or $gpu.Integrated) {
        Add-HLResult -Module 'GPU AMD' -Item 'Detección' -Status Skipped -Detail 'No hay Radeon dedicada'
        return
    }

    Write-HLStep "Revisando $($gpu.Name)..."

    # --- Driver ---------------------------------------------------------------
    $adrenalin = $null
    if ($gpu.ClassKey) { $adrenalin = (Get-ItemProperty $gpu.ClassKey -ErrorAction SilentlyContinue).RadeonSoftwareVersion }
    $age = if ($gpu.DriverDate) { [int]((Get-Date) - $gpu.DriverDate).TotalDays } else { $null }
    $drvLabel = if ($adrenalin) { "Adrenalin $adrenalin" } else { "driver $($gpu.DriverVersion)" }
    if ($null -ne $age -and $age -gt 120) {
        Write-HLWarn "Driver: $drvLabel, $age días. Los drivers recientes traen perfiles específicos de COD."
        Add-HLManualStep 'GPU' 'Actualiza Adrenalin (instalación limpia: Factory Reset en el instalador).' 'https://www.amd.com/es/support/download/drivers.html'
        Add-HLResult -Module 'GPU AMD' -Item 'Driver' -Status Manual -Detail "$drvLabel ($age días)"
    } else {
        Write-HLSub "Driver: $drvLabel" 'OK'
        Add-HLResult -Module 'GPU AMD' -Item 'Driver' -Status Info -Detail $drvLabel
    }

    # --- SAM / Resizable BAR ----------------------------------------------------
    $rebar = Get-HLRebarState -Gpu $gpu
    if ($null -eq $rebar) {
        Write-HLSub 'Smart Access Memory' 'MANUAL (no verificable, revisa Adrenalin > Rendimiento > Sintonización)'
        Add-HLResult -Module 'GPU AMD' -Item 'SAM' -Status Manual -Detail 'No se pudo leer la apertura PCIe'
    } elseif ($rebar.Enabled) {
        Write-HLSub "Smart Access Memory (apertura $($rebar.ApertureMB) MB)" 'OK'
        Add-HLResult -Module 'GPU AMD' -Item 'SAM' -Status Info -Detail "Activo, apertura $($rebar.ApertureMB) MB"
    } else {
        Write-HLSub "Smart Access Memory (apertura $($rebar.ApertureMB) MB)" 'MANUAL (desactivado)'
        $biosPath = Get-HLRebarBiosPath -BoardVendor $Hardware.Board.Vendor
        Add-HLManualStep 'BIOS' "Activa SAM/ReBAR: $biosPath. Requiere CSM desactivado (arranque UEFI)." 'https://www.amd.com/es/technologies/smart-access-memory'
        Add-HLResult -Module 'GPU AMD' -Item 'SAM' -Status Manual -Detail 'Desactivado en BIOS'
    }

    # --- Estabilidad (útil tras undervolt) --------------------------------------
    $crashes = Get-HLDisplayCrashes -Days 14
    if ($crashes -gt 0) {
        Write-HLWarn "$crashes reinicios del driver de pantalla (TDR, evento 4101) en 14 días. Si tienes undervolt/OC, súbelo 10-20 mV."
        Add-HLResult -Module 'GPU AMD' -Item 'Estabilidad' -Status Manual -Detail "$crashes TDR en 14 días"
    } else {
        Write-HLSub 'Crashes del driver (14 días)' 'OK (0)'
    }

    # --- Adrenalin: instrucciones exactas ---------------------------------------
    Write-HLSub 'Ajustes de Adrenalin' 'MANUAL (ver reporte)'
    $steps = @(
        'Adrenalin > Juegos > Call of Duty > Perfil: Personalizado.'
        'AMD Anti-Lag: ACTIVADO. Si en el menú gráfico de Warzone aparece "AMD Anti-Lag 2", actívalo allí: tiene prioridad y reduce más latencia que la versión del driver.'
        'Radeon Chill: DESACTIVADO (limita FPS dinámicamente, añade latencia variable).'
        'Radeon Boost: DESACTIVADO (baja resolución en movimiento, justo cuando apuntas).'
        'Radeon Image Sharpening: ACTIVADO al 80%. No combinar con FidelityFX CAS del juego: elige uno.'
        'AMD Fluid Motion Frames: DESACTIVADO (interpola frames = más latencia).'
        'Enhanced Sync: DESACTIVADO. Esperar a actualización vertical: Desactivado, salvo que la aplicación lo especifique.'
        'Radeon Super Resolution: DESACTIVADO.'
    )
    foreach ($s in $steps) { Add-HLManualStep 'Adrenalin' $s }

    # --- Undervolt sugerido (no se aplica) ------------------------------------
    if ($gpu.Name -match '66[05]0 XT|6600') {
        Add-HLManualStep 'Undervolt' ('RX 66x0: Adrenalin > Rendimiento > Sintonización > Manual > Sintonización de GPU: Avanzado. ' +
            'Frecuencia máx.: stock. Voltaje: 1100 mV (stock ~1150-1200 mV). Límite de potencia: máximo permitido. ' +
            'Prueba 30 min de Warzone + 20 min de Time Spy en bucle. Si hay crash o artefactos: +20 mV. Si es estable: baja de 10 en 10 mV. ' +
            'Vuelve a ejecutar Hardline: el apartado "Crashes del driver" cuenta los TDR para validarlo.') 'https://www.amd.com/es/products/software/adrenalin/performance-tuning.html'
    } else {
        Add-HLManualStep 'Undervolt' 'Baja el voltaje máximo en pasos de 25 mV a frecuencia stock y valida 30 min en juego por paso.' ''
    }
    Add-HLResult -Module 'GPU AMD' -Item 'Adrenalin (Anti-Lag, Chill, RIS, undervolt)' -Status Manual -Detail 'Instrucciones en el reporte'
}

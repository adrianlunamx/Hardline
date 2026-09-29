#Requires -Version 5.1
<#
    Hardline - CPU Ryzen y memoria.

    PBO, Curve Optimizer, SMT y EXPO viven en la BIOS (firmware AGESA). Ningún
    script de Windows puede cambiarlos de forma persistente; Ryzen Master lo
    hace con su propio driver y aun así se pierde al reiniciar. Hardline
    detecta el estado, decide qué recomendar para tu CPU concreta y deja la
    ruta exacta de menús según el fabricante de tu placa.
#>

function Get-HLChipsetDriver {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($r in $roots) {
        $hit = Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -match '^AMD Chipset Software' } | Select-Object -First 1
        if ($hit) { return $hit.DisplayVersion }
    }
    return $null
}

function Get-HLBiosPaths {
    param([string]$Vendor)
    switch ($Vendor) {
        'ASUS' {
            @{ PBO = 'Advanced (F7) > AMD Overclocking > Precision Boost Overdrive: Advanced, PBO Limits: Motherboard'
               CO  = 'AMD Overclocking > Precision Boost Overdrive > Curve Optimizer: All Cores, Negative, 20'
               SMT = 'Advanced > CPU Configuration > SMT Mode'
               EXPO = 'Ai Tweaker > Ai Overclock Tuner: EXPO I' }
        }
        'MSI' {
            @{ PBO = 'OC > Advanced CPU Configuration > AMD Overclocking > Precision Boost Overdrive: Advanced'
               CO  = 'AMD Overclocking > Precision Boost Overdrive > Curve Optimizer: All Cores, Negative, 20'
               SMT = 'OC > Advanced CPU Configuration > SMT Mode'
               EXPO = 'OC > Extreme Memory Profile (EXPO): Profile 1' }
        }
        'Gigabyte' {
            @{ PBO = 'Tweaker > Advanced CPU Settings > Precision Boost Overdrive: Advanced'
               CO  = 'Tweaker > Advanced CPU Settings > Curve Optimizer: All Cores, Negative, 20'
               SMT = 'Tweaker > Advanced CPU Settings > SMT Mode'
               EXPO = 'Tweaker > Extreme Memory Profile (X.M.P./EXPO): Profile 1' }
        }
        'ASRock' {
            @{ PBO = 'OC Tweaker > CPU Configuration > Precision Boost Overdrive: Advanced'
               CO  = 'Advanced > AMD Overclocking > Precision Boost Overdrive > Curve Optimizer: All Cores, Negative, 20'
               SMT = 'Advanced > CPU Configuration > SMT Mode'
               EXPO = 'OC Tweaker > DRAM Profile Setting: EXPO Profile 1' }
        }
        default {
            @{ PBO = 'Busca "Precision Boost Overdrive" (suele estar en AMD Overclocking / AMD CBS)'
               CO  = 'Dentro de PBO: Curve Optimizer > All Cores > Negative > 20'
               SMT = 'Busca "SMT Mode" en la configuración de CPU'
               EXPO = 'Busca "EXPO" o "DOCP" en el apartado de memoria' }
        }
    }
}

function Invoke-HLRyzen {
    param([Parameter(Mandatory)] $Hardware)

    $cpu = $Hardware.CPU
    if (-not $cpu.IsRyzen) {
        Add-HLResult -Module 'CPU' -Item 'Ryzen' -Status Skipped -Detail "CPU no Ryzen: $($cpu.Name)"
        return
    }
    $bios = Get-HLBiosPaths -Vendor $Hardware.Board.Vendor
    $short = ($cpu.Name -replace '^AMD\s+', '' -replace '\s+\d+-Core Processor$', '')

    Write-HLStep "Optimizando AMD $short..."

    # --- Chipset --------------------------------------------------------------
    $chipset = Get-HLChipsetDriver
    if ($chipset) {
        Write-HLSub "AMD Chipset Software $chipset" 'OK'
        Add-HLResult -Module 'CPU' -Item 'Chipset driver' -Status Info -Detail $chipset
    } else {
        Write-HLSub 'AMD Chipset Software' 'MANUAL (no instalado)'
        Add-HLManualStep 'Drivers' 'Instala AMD Chipset Software. Incluye el driver de PPM/CPPC que decide qué núcleo recibe los hilos del juego.' 'https://www.amd.com/es/support/download/drivers.html'
        Add-HLResult -Module 'CPU' -Item 'Chipset driver' -Status Manual -Detail 'No instalado'
    }

    # --- PBO + Curve Optimizer -------------------------------------------------
    if ($cpu.Family -in @('Zen4', 'Zen5') -and -not $cpu.IsX3D) {
        Write-HLSub 'PBO: Advanced + Curve Optimizer -20 all-core' 'MANUAL (BIOS)'
        Add-HLManualStep 'BIOS' "PBO: $($bios.PBO)"
        Add-HLManualStep 'BIOS' "Curve Optimizer: $($bios.CO). Un 7600X típico aguanta entre -15 y -30; -20 es un punto de partida conservador."
        Add-HLManualStep 'Estabilidad' ('Tras aplicar CO: Prime95 Small FFTs 5 min mínimo (carga), después CoreCycler 1 h (valida núcleo a núcleo en boost, que es donde falla un CO agresivo). ' +
            'Un CO inestable NO siempre da pantallazo azul: puede dar crashes de Warzone "DEV ERROR" o reinicios en reposo. Si pasa: sube a -15.') 'https://github.com/sp00n/corecycler'
        Write-HLWarn 'Testea estabilidad con Prime95 (5min mínimo) y CoreCycler tras tocar Curve Optimizer.'
        Add-HLResult -Module 'CPU' -Item 'PBO + Curve Optimizer' -Status Manual -Detail 'Ruta de BIOS en el reporte'
    } elseif ($cpu.IsX3D) {
        Write-HLSub 'PBO/CO' 'SKIP (X3D: solo CO; PBO limitado por AMD)'
        Add-HLManualStep 'BIOS' "X3D: Curve Optimizer -15 a -20 ($($bios.CO)). No subas límites de PBO: la caché 3D limita temperatura y voltaje."
    }

    # --- SMT -------------------------------------------------------------------
    # Postura de Hardline: en 6 núcleos NO se desactiva SMT. Warzone reparte
    # trabajo en 8+ hilos (render, streaming de texturas, audio, red) y con solo
    # 6 hilos los 1% lows empeoran. Desactivar SMT solo compensa en CPUs con
    # 12+ núcleos donde los hilos físicos sobran.
    if ($cpu.SMT) {
        if ($cpu.Cores -ge 12) {
            Write-HLSub "SMT activo en $($cpu.Cores) núcleos" 'MANUAL (opcional)'
            Add-HLManualStep 'BIOS' "SMT: con $($cpu.Cores) núcleos puedes probar SMT OFF ($($bios.SMT)). Compara 1% lows con CapFrameX antes de quedártelo."
        } else {
            Write-HLSub "SMT activo ($($cpu.Cores)C/$($cpu.Threads)T): se mantiene" 'OK'
            Write-HLInfo "Con $($cpu.Cores) núcleos, desactivar SMT reduce los 1% lows en Warzone. No se recomienda."
            Add-HLResult -Module 'CPU' -Item 'SMT' -Status Info -Detail "Mantener activo con $($cpu.Cores) núcleos"
        }
    }

    # --- Temperatura: aviso informativo -----------------------------------------
    if ($cpu.Family -eq 'Zen4') {
        Write-HLInfo 'Zen 4 llega a 95 °C por diseño en carga total: no es un fallo. En juego lo normal es 65-80 °C.'
    }

    Invoke-HLMemoryCheck -Hardware $Hardware -BiosPaths $bios
}

function Invoke-HLMemoryCheck {
    param([Parameter(Mandatory)] $Hardware, [hashtable]$BiosPaths)

    $ram = $Hardware.RAM
    Write-HLStep 'Revisando memoria...'
    Write-HLSub ("{0}GB {1}, {2} módulos, {3} MT/s (nominal {4})" -f $ram.TotalGB, $ram.Type, $ram.Modules, $ram.SpeedMTs, $ram.RatedMTs)

    switch ($ram.Profile) {
        'Inactivo' {
            Write-HLWarn "EXPO/XMP inactivo: la RAM corre a $($ram.SpeedMTs) MT/s. Es la mejora de 1% lows más grande disponible."
            Add-HLManualStep 'BIOS' "Activa EXPO: $($BiosPaths.EXPO)"
            Add-HLResult -Module 'RAM' -Item 'EXPO/XMP' -Status Manual -Detail "Inactivo ($($ram.SpeedMTs) MT/s)"
        }
        'Activo' {
            Write-HLSub 'EXPO/XMP' 'OK'
            Add-HLResult -Module 'RAM' -Item 'EXPO/XMP' -Status Info -Detail "Activo ($($ram.SpeedMTs) MT/s)"
        }
        default { Add-HLResult -Module 'RAM' -Item 'EXPO/XMP' -Status Info -Detail 'No determinable' }
    }

    if ($ram.Type -eq 'DDR5' -and $Hardware.CPU.Family -in @('Zen4', 'Zen5')) {
        if ($ram.SpeedMTs -gt 6400) {
            Write-HLWarn "DDR5 a $($ram.SpeedMTs) MT/s en AM5 suele forzar UCLK = MEMCLK/2. 6000-6400 con UCLK 1:1 da menos latencia."
        }
        # Windows no expone timings. ZenTimings los lee del SMU.
        Write-HLInfo 'Timings: Windows no los expone. Usa ZenTimings para verlos (tCL, tRCD, tRP, tRAS, tRFC).'
        Add-HLManualStep 'RAM' ('Revisa tRFC con ZenTimings. Los perfiles EXPO suelen traerlo holgado (800-1000 ciclos a 6000 MT/s = 265-330 ns). ' +
            'Para Hynix M/A-die, 160 ns es un objetivo razonable: a 6000 MT/s son 480 ciclos (ns x MT/s / 2000). ' +
            'Baja en pasos y valida con TestMem5 (config anta777 absolut) 1 h. Samsung/Micron aguantan menos: empieza en 220 ns.') 'https://zentimings.protonrom.com/'
        Add-HLManualStep 'RAM' 'DRAM Calculator for Ryzen solo cubre DDR4 (no sirve en AM5). Para DDR5 la referencia práctica son los vídeos de timings de Buildzoid (Actually Hardcore Overclocking).' 'https://www.youtube.com/@ActuallyHardcoreOverclocking'
    } elseif ($ram.Type -eq 'DDR4') {
        Add-HLManualStep 'RAM' 'DDR4: usa DRAM Calculator for Ryzen para timings secundarios (tRFC incluido) y valida con TestMem5.' 'https://www.techpowerup.com/download/ryzen-dram-calculator/'
    }

    if ($ram.Modules -gt 2 -and $ram.Type -eq 'DDR5') {
        Write-HLWarn '4 módulos DDR5 en AM5: el controlador rara vez pasa de 5200-5600 MT/s estable. 2 módulos rinden más.'
    }
}

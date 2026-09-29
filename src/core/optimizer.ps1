#Requires -Version 5.1
<#
    Hardline - orquestador.

    Decide qué módulos corren según el hardware detectado y los flags de
    instalación. Cada módulo se ejecuta aislado: si uno falla, se anota en el
    reporte y el resto sigue.
#>

$script:CoreDir = $PSScriptRoot
$script:SrcDir = Split-Path $PSScriptRoot -Parent

foreach ($f in @(
        'core\benchmarker.ps1',
        'core\report.ps1',
        'modules\windows\services.ps1',
        'modules\windows\registry.ps1',
        'modules\windows\power.ps1',
        'modules\windows\timer.ps1',
        'modules\windows\platforms.ps1',
        'modules\amd\gpu.ps1',
        'modules\amd\ryzen.ps1',
        'modules\network\optimize.ps1',
        'modules\game\warzone.ps1',
        'audio\setup.ps1'
    )) {
    . (Join-Path $script:SrcDir $f)
}

function Invoke-HLOptimization {
    param(
        [Parameter(Mandatory)] $Hardware,
        [switch] $SkipWindows,
        [switch] $SkipNetwork,
        [switch] $SkipGame,
        [string] $Platform = ''
    )

    if (-not $SkipWindows) {
        Write-HLStep 'Optimizando Windows...'
        Invoke-HLSafely 'Servicios' 'Servicios' { Invoke-HLServices -Hardware $Hardware }
        Invoke-HLSafely 'Plataformas' 'Plataformas de juego' { Invoke-HLPlatforms -Hardware $Hardware -Platform $Platform }
        Invoke-HLSafely 'Registro' 'Registro' { Invoke-HLRegistry -Hardware $Hardware }
        Invoke-HLSafely 'Energía' 'Plan de energía' { Invoke-HLPowerPlan -Hardware $Hardware }
        Invoke-HLSafely 'Timer' 'Timer resolution' { Install-HLTimerResolution -Hardware $Hardware }
        Write-HLOk 'Windows optimizado'
        Add-HLManualStep 'Windows' 'Comprueba la latencia DPC con LatencyMon (enlace en la sección Benchmark).'
    }

    if ($Hardware.CPU.IsRyzen) {
        Invoke-HLSafely 'CPU' 'Ryzen' { Invoke-HLRyzen -Hardware $Hardware }
    } else {
        Invoke-HLSafely 'RAM' 'Memoria' { Invoke-HLMemoryCheck -Hardware $Hardware -BiosPaths @{ EXPO = 'Busca "XMP" o "EXPO" en la sección de memoria de la BIOS' } }
    }

    if ($Hardware.GPU.Primary -and $Hardware.GPU.Primary.Vendor -eq 'AMD') {
        Invoke-HLSafely 'GPU AMD' 'Radeon' { Invoke-HLAmdGpu -Hardware $Hardware }
    } elseif ($Hardware.GPU.Primary) {
        Write-HLInfo "GPU $($Hardware.GPU.Primary.Name): Hardline solo trae módulo específico para Radeon. Los tweaks de Windows, red y juego se aplican igual."
        Add-HLResult -Module 'GPU' -Item $Hardware.GPU.Primary.Name -Status Skipped -Detail 'Sin módulo específico'
    }

    if (-not $SkipNetwork) {
        Write-HLStep 'Optimizando red...'
        Invoke-HLSafely 'Red' 'Red' { Invoke-HLNetwork -Hardware $Hardware }
    }

    if (-not $SkipGame) {
        Invoke-HLSafely 'Warzone' 'Config de Warzone' { Invoke-HLWarzone -Hardware $Hardware }
    }
}

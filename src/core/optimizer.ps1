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
        'modules\windows\gamesession.ps1',
        'modules\windows\latency.ps1',
        'modules\windows\experimental.ps1',
        'modules\gpu\shared.ps1',
        'modules\gpu\nvidia.ps1',
        'modules\gpu\intel.ps1',
        'modules\amd\gpu.ps1',
        'modules\amd\ryzen.ps1',
        'modules\network\optimize.ps1',
        'modules\network\diagnose.ps1',
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
        [switch] $SkipPlatforms,
        [switch] $SkipLatency,
        [switch] $Experimental,
        [switch] $SkipNetDiag,
        [switch] $DisableOtherPlatforms,
        [string] $Platform = '',
        [ValidateSet('', 'Yes', 'No')] [string] $GameSession = ''
    )

    $session = Get-HLGameSessionChoice -Choice $GameSession

    if (-not $SkipWindows) {
        Write-HLStep 'Optimizando Windows...'
        Invoke-HLSafely 'Servicios' 'Servicios' { Invoke-HLServices -Hardware $Hardware }
        Invoke-HLSafely 'Registro' 'Registro' { Invoke-HLRegistry -Hardware $Hardware }

        # Con modo partida, el plan de energía máximo puede ir solo durante la partida.
        $powerOnlyInGame = $false
        if ($session) {
            $powerOnlyInGame = Read-HLYesNo '¿Plan de energía máximo solo con Warzone abierto? (en reposo el PC consume y se calienta menos)' $true
        }
        Invoke-HLSafely 'Energía' 'Plan de energía' { Invoke-HLPowerPlan -Hardware $Hardware -CreateOnly:$powerOnlyInGame }
        Invoke-HLSafely 'Timer' 'Timer resolution' { Install-HLTimerResolution -Hardware $Hardware }
        Write-HLOk 'Windows optimizado'
        Add-HLManualStep 'Windows' 'Comprueba la latencia DPC con LatencyMon (enlace en la sección Benchmark).'
    }

    if (-not $SkipPlatforms) {
        Write-HLStep 'Plataformas de juego...'
        Invoke-HLSafely 'Plataformas' 'Plataformas de juego' { Invoke-HLPlatforms -Hardware $Hardware -Platform $Platform -DisableOthers:$DisableOtherPlatforms }
    }

    if (-not $SkipLatency) { Invoke-HLLatency -Hardware $Hardware }
    if ($Experimental) { Invoke-HLExperimental -Hardware $Hardware }

    if ($session) {
        Write-HLStep 'Modo partida...'
        Invoke-HLSafely 'Modo partida' 'Modo partida' { Install-HLGameSession -Hardware $Hardware }
    } else {
        Add-HLResult -Module 'Modo partida' -Item 'Tarea' -Status Skipped -Detail 'No elegido'
    }

    if ($Hardware.CPU.IsRyzen) {
        Invoke-HLSafely 'CPU' 'Ryzen' { Invoke-HLRyzen -Hardware $Hardware }
    } else {
        Invoke-HLSafely 'RAM' 'Memoria' { Invoke-HLMemoryCheck -Hardware $Hardware -BiosPaths @{ EXPO = 'Busca "XMP" o "EXPO" en la sección de memoria de la BIOS' } }
    }

    $gpuVendor = if ($Hardware.GPU.Primary) { $Hardware.GPU.Primary.Vendor } else { '' }
    switch ($gpuVendor) {
        'AMD'    { Invoke-HLSafely 'GPU AMD' 'Radeon' { Invoke-HLAmdGpu -Hardware $Hardware } }
        'NVIDIA' { Invoke-HLSafely 'GPU NVIDIA' 'GeForce' { Invoke-HLNvidiaGpu -Hardware $Hardware } }
        'Intel'  { Invoke-HLSafely 'GPU Intel' 'Intel Arc' { Invoke-HLIntelGpu -Hardware $Hardware } }
        default  { if ($Hardware.GPU.Primary) { Add-HLResult -Module 'GPU' -Item $Hardware.GPU.Primary.Name -Status Skipped -Detail 'Sin módulo específico' } }
    }

    if (-not $SkipNetwork) {
        Write-HLStep 'Optimizando red...'
        Invoke-HLSafely 'Red' 'Red' { Invoke-HLNetwork -Hardware $Hardware }
    }
    if (-not $SkipNetDiag) {
        Invoke-HLSafely 'Diagnóstico de red' 'Diagnóstico de red' { Invoke-HLNetDiagnosis -Hardware $Hardware | Out-Null }
    }

    if (-not $SkipGame) {
        Invoke-HLSafely 'Warzone' 'Config de Warzone' { Invoke-HLWarzone -Hardware $Hardware }
    }
}

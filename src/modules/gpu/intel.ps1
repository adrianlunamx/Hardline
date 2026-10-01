#Requires -Version 5.1
<#
    Hardline - GPU Intel Arc.

    En Arc, Resizable BAR no es opcional: sin él el rendimiento cae de forma
    drástica (Intel lo declara requisito). Es lo primero que se comprueba.
#>

function Invoke-HLIntelGpu {
    param([Parameter(Mandatory)] $Hardware)

    $gpu = $Hardware.GPU.Primary
    if (-not $gpu -or $gpu.Vendor -ne 'Intel' -or $gpu.Integrated) { return }
    Write-HLStep "Revisando $($gpu.Name)..."

    Invoke-HLGpuHealth -Hardware $Hardware -Module 'GPU Intel' -DriverLabel "driver $($gpu.DriverVersion)" `
        -DriverUrl 'https://www.intel.com/content/www/us/en/download-center/home.html' -MaxDriverAgeDays 90 `
        -RebarName 'Resizable BAR' -RebarNote 'En Intel Arc es obligatorio: sin ReBAR el rendimiento cae a la mitad o menos.'

    Write-HLSub 'Intel Graphics Software y juego' 'MANUAL (ver reporte)'
    foreach ($s in @(
            'Warzone > Gráficos: si aparece Intel XeLL (baja latencia), actívalo. XeSS en Calidad solo si no llegas a tus FPS objetivo; Frame Generation desactivado en competitivo.'
            'Intel Graphics Software (antes Arc Control) > Gráficos > perfil de cod.exe: Sincronización vertical según aplicación; Low Latency activado si el juego no ofrece XeLL.'
            'Desactiva la grabación y la superposición de Intel Graphics Software mientras juegas.'
        )) { Add-HLManualStep 'Intel Arc' $s }
    Add-HLResult -Module 'GPU Intel' -Item 'Ajustes del driver' -Status Manual -Detail 'Instrucciones en el reporte'
}

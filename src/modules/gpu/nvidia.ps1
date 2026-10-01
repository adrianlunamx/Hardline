#Requires -Version 5.1
<#
    Hardline - GPU NVIDIA GeForce.

    Igual que con AMD: se comprueba driver, Resizable BAR y estabilidad, y se
    dejan instrucciones exactas para el Panel de control de NVIDIA y el juego.
    No se escriben perfiles del driver (NVAPI/DRS): sin herramienta oficial es
    frágil y un perfil corrupto afecta a todos los juegos.

    HAGS: en NVIDIA, Hardline no lo desactiva. DLSS Frame Generation lo
    necesita activado y con los drivers actuales no hay ventaja medible en
    apagarlo.
#>

function Invoke-HLNvidiaGpu {
    param([Parameter(Mandatory)] $Hardware)

    $gpu = $Hardware.GPU.Primary
    if (-not $gpu -or $gpu.Vendor -ne 'NVIDIA') { return }
    Write-HLStep "Revisando $($gpu.Name)..."

    $ver = ConvertTo-HLNvidiaDriverVersion -WindowsVersion $gpu.DriverVersion
    $label = if ($ver) { "GeForce $ver" } else { "driver $($gpu.DriverVersion)" }
    Invoke-HLGpuHealth -Hardware $Hardware -Module 'GPU NVIDIA' -DriverLabel $label -DriverUrl 'https://www.nvidia.com/es-es/drivers/' `
        -RebarName 'Resizable BAR' -RebarNote 'NVIDIA lo habilita juego a juego desde el driver, pero necesita estar activo en la BIOS.'

    Write-HLSub 'Panel de control de NVIDIA y juego' 'MANUAL (ver reporte)'
    $steps = @(
        'Warzone > Gráficos: NVIDIA Reflex Low Latency = Activado + Boost. Con Reflex activo, el "Modo de baja latencia" del panel no se usa.'
        'Panel de control de NVIDIA > Administrar configuración 3D > Configuración de programa > cod.exe:'
        '   Modo de control de energía: Preferir rendimiento máximo.'
        '   Filtrado de texturas - Calidad: Alto rendimiento.'
        '   Tamaño de caché del sombreador: 10 GB o Ilimitado (Warzone recompila sombreadores en cada parche; con caché pequeña hay tirones al empezar).'
        '   Sincronización vertical: Activado SOLO si usas G-SYNC (con Reflex limita los FPS por debajo del refresco automáticamente). Sin G-SYNC: Desactivado.'
        'Configurar G-SYNC: "Habilitar para modo de pantalla completa y ventana", si tu monitor lo soporta. V-Sync del juego: desactivado.'
        'DLSS: Calidad solo si no llegas a tus FPS objetivo. DLSS Frame Generation: DESACTIVADO en competitivo (los frames generados no responden a tu ratón y añaden latencia).'
        'NVIDIA App: desactiva la superposición, Repetición instantánea y el filtro de juego (graban/procesan en segundo plano).'
        'Opcional: Panel > Pantalla > Ajustar configuración de color > Intensidad digital 60-70% para que las siluetas resalten más. Es preferencia visual, no rendimiento.'
    )
    foreach ($s in $steps) { Add-HLManualStep 'NVIDIA' $s }
    Add-HLManualStep 'Undervolt' 'NVIDIA: MSI Afterburner > Ctrl+F (curva). Fija ~0.900-0.950 V a tu frecuencia boost habitual y aplana la curva a partir de ahí. Valida 30 min en Warzone; si hay crash, +25 mV. Vuelve a ejecutar Hardline para ver el contador de TDR.' 'https://www.msi.com/Landing/afterburner/graphics-cards'
    Add-HLResult -Module 'GPU NVIDIA' -Item 'Panel de control y Reflex' -Status Manual -Detail 'Instrucciones en el reporte'
}

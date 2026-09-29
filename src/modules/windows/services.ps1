#Requires -Version 5.1
<#
    Hardline - servicios de Windows.

    Criterio: solo se tocan servicios cuyo trabajo no aporta nada durante una
    partida y que generan actividad de disco/CPU en segundo plano. Nada que
    rompa Windows Update, Defender, audio, red o el launcher del juego.

    Explicación completa por servicio: docs/TWEAKS_EXPLAINED.md#servicios
#>

function Get-HLServicePlan {
    param($Hardware)

    $plan = @(
        [pscustomobject]@{ Name = 'SysMain';           Target = 'Disabled'; Why = 'Superfetch. Precarga apps en RAM y genera I/O en segundo plano. Con NVMe y 16GB+ no aporta.' }
        [pscustomobject]@{ Name = 'WSearch';           Target = 'Disabled'; Why = 'Indexador de Windows Search. Reindexa en momentos arbitrarios. La búsqueda de apps en Inicio sigue funcionando; la de contenido de archivos se vuelve lenta.' }
        [pscustomobject]@{ Name = 'DiagTrack';         Target = 'Disabled'; Why = 'Telemetría (Connected User Experiences). Subidas periódicas y picos de CPU.' }
        [pscustomobject]@{ Name = 'dmwappushservice';  Target = 'Disabled'; Why = 'Enrutador de mensajes WAP para telemetría. Dependencia de DiagTrack.' }
        [pscustomobject]@{ Name = 'MapsBroker';        Target = 'Disabled'; Why = 'Descarga de mapas offline.' }
        [pscustomobject]@{ Name = 'RetailDemo';        Target = 'Disabled'; Why = 'Modo demo de tienda.' }
        [pscustomobject]@{ Name = 'WpcMonSvc';         Target = 'Disabled'; Why = 'Control parental.' }
        [pscustomobject]@{ Name = 'Fax';               Target = 'Disabled'; Why = 'Fax.' }
        [pscustomobject]@{ Name = 'WerSvc';            Target = 'Manual';   Why = 'Informe de errores. Queda en Manual: solo arranca si algo crashea.' }
        [pscustomobject]@{ Name = 'PcaSvc';            Target = 'Manual';   Why = 'Asistente de compatibilidad. Escanea ejecutables al lanzarlos.' }
    )

    # Los servicios de Xbox y Steam no están aquí: dependen de la plataforma
    # desde la que juegas y los gestiona src/modules/windows/platforms.ps1.
    return $plan
}

function Invoke-HLServices {
    param($Hardware)

    Write-HLSub 'Deshabilitando servicios innecesarios'
    $changed = 0
    foreach ($s in (Get-HLServicePlan -Hardware $Hardware)) {
        $r = Set-HLServiceStart -Name $s.Name -StartType $s.Target -Reason $s.Why
        switch ($r) {
            'NotFound'  { Add-HLResult -Module 'Servicios' -Item $s.Name -Status Skipped -Detail 'No existe en este sistema' }
            'Unchanged' { Add-HLResult -Module 'Servicios' -Item $s.Name -Status Skipped -Detail "Ya estaba en $($s.Target)" }
            'Changed'   { Add-HLResult -Module 'Servicios' -Item $s.Name -Status Applied -Detail "-> $($s.Target). $($s.Why)"; $changed++ }
        }
        Write-HLInfo ('{0,-18} {1,-9} {2}' -f $s.Name, $r, $s.Target)
    }
    Write-HLSub "Servicios modificados: $changed" 'OK'
}

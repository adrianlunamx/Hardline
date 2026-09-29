#Requires -Version 5.1
<#
    Hardline - plan de energía.

    Crea un plan a partir de la plantilla oculta "Ultimate Performance"
    (e9a42b02-...), lo renombra a "Hardline Ultimate Performance" para poder
    reconocerlo sin depender del idioma del sistema, y lo activa.

    Efecto real: sin aparcamiento de núcleos, estado mínimo de CPU al 100%,
    sin suspensión selectiva USB ni ASPM en PCIe. Reduce la latencia de salida
    de estados C/P profundos. Coste: 10-25 W más en reposo en un Ryzen 7000.

    https://learn.microsoft.com/windows-hardware/customize/power-settings/configure-power-settings
#>

$script:HLUltimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$script:HLPlanName = 'Hardline Ultimate Performance'
$script:GuidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-HLActivePowerScheme {
    $out = (& powercfg.exe /getactivescheme) -join ' '
    if ($out -match $script:GuidRegex) { return $Matches[0] }
    return $null
}

function Find-HLPowerScheme {
    param([string]$Name)
    foreach ($line in (& powercfg.exe /list)) {
        if ($line -match "($script:GuidRegex)\s+\((.+?)\)") {
            if ($Matches[2] -eq $Name) { return $Matches[1] }
        }
    }
    return $null
}

function Invoke-HLPowerPlan {
    param($Hardware)

    $prev = Get-HLActivePowerScheme
    $existing = Find-HLPowerScheme -Name $script:HLPlanName

    if ($existing -and $existing -eq $prev) {
        Write-HLSub 'Ultimate Performance plan' 'OK (ya activo)'
        Add-HLResult -Module 'Energía' -Item 'Plan Ultimate Performance' -Status Skipped -Detail 'Ya activo'
        return
    }
    if ($HL.DryRun) {
        Write-HLSub 'Ultimate Performance plan' 'SKIP (DryRun)'
        return
    }

    $created = $null
    $guid = $existing
    if (-not $guid) {
        $out = (& powercfg.exe -duplicatescheme $script:HLUltimateTemplate) -join ' '
        if ($out -notmatch $script:GuidRegex) {
            # Algunas ediciones (p. ej. S mode o builds recortadas) no traen la plantilla.
            # Alternativa: High performance (8c5e7fda-...).
            Write-HLWarn 'La plantilla Ultimate Performance no está disponible; se usa Alto rendimiento.'
            $out = (& powercfg.exe -duplicatescheme '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') -join ' '
            if ($out -notmatch $script:GuidRegex) { throw "powercfg no pudo duplicar ningún plan: $out" }
        }
        $guid = $Matches[0]
        $created = $guid
        # Descripción en ASCII: powercfg la recibe con la codepage de la consola.
        & powercfg.exe /changename $guid $script:HLPlanName 'Hardline: sin aparcamiento de nucleos, sin ASPM, sin suspension USB.' | Out-Null
    }

    # Ajustes dentro del plan creado (se borran junto con el plan en el rollback).
    # USB selective suspend: OFF. Evita micro-desconexiones de ratón/headset USB.
    & powercfg.exe /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
    # PCI Express Link State Power Management: OFF.
    & powercfg.exe /setacvalueindex $guid 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 | Out-Null
    # Estado mínimo del procesador: 100%.
    & powercfg.exe /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100 | Out-Null

    Add-HLManifestEntry -Type 'PowerScheme' -Data @{ PrevActive = $prev; Created = $created; NewActive = $guid }
    & powercfg.exe /setactive $guid | Out-Null

    Write-HLSub 'Ultimate Performance plan' 'OK'
    Add-HLResult -Module 'Energía' -Item 'Plan Ultimate Performance' -Status Applied -Detail "Activo: $guid (anterior: $prev)"

    if ($Hardware -and $Hardware.CPU.IsRyzen) {
        Write-HLInfo 'Ryzen: el consumo en reposo sube (núcleos sin aparcar). Es el precio de la menor latencia.'
    }
}

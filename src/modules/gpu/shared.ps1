#Requires -Version 5.1
<#
    Hardline - comprobaciones de GPU comunes a todos los fabricantes.
    Solo lectura.
#>

# Tamaño real de la ventana de memoria PCIe de la GPU (Resizable BAR / SAM).
function Get-HLRebarState {
    param([Parameter(Mandatory)] $Gpu)
    try {
        $dev = Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.PNPDeviceID -eq $Gpu.PnpId } | Select-Object -First 1
        if (-not $dev) { return $null }
        $ranges = @(Get-CimAssociatedInstance -InputObject $dev -ResultClassName Win32_DeviceMemoryAddress -ErrorAction Stop)
        if ($ranges.Count -eq 0) { return $null }
        $largest = ($ranges | ForEach-Object { [uint64]$_.EndingAddress - [uint64]$_.StartingAddress + 1 } | Measure-Object -Maximum).Maximum
        # Sin ReBAR la CPU ve una ventana de 256 MB de VRAM. Con ReBAR, la VRAM entera.
        return [pscustomobject]@{
            ApertureMB = [math]::Round($largest / 1MB)
            Enabled    = ($largest -gt 512MB)
        }
    } catch {
        Write-HLLog WARN "No se pudo leer la apertura PCIe de la GPU: $($_.Exception.Message)"
        return $null
    }
}

# Reinicios del driver de pantalla (TDR, evento 4101). Útil para validar undervolt/OC.
function Get-HLDisplayCrashes {
    param([int]$Days = 14)
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction Stop)
        return $events.Count
    } catch {
        # Get-WinEvent lanza excepción cuando no hay coincidencias.
        return 0
    }
}

function Get-HLRebarBiosPath {
    param([string]$BoardVendor)
    switch ($BoardVendor) {
        'ASUS'     { 'Advanced > PCI Subsystem Settings > Above 4G Decoding: Enabled, Re-Size BAR Support: Enabled' }
        'MSI'      { 'Settings > Advanced > PCIe/PCI Sub-system Settings > Above 4G memory: Enabled, Re-Size BAR Support: Enabled' }
        'Gigabyte' { 'Settings > IO Ports > Above 4G Decoding: Enabled, Re-Size BAR Support: Auto' }
        'ASRock'   { 'Advanced > PCI Configuration > Above 4G Decoding: Enabled, C.A.M. (Clever Access Memory): Enabled' }
        default    { 'Busca "Above 4G Decoding" y "Re-Size BAR" en la BIOS y actívalos' }
    }
}

<#
    Versión de driver de NVIDIA a partir de la de Windows:
    32.0.15.6094 -> últimos 5 dígitos de "15" + "6094" = 56094 -> 560.94
#>
function ConvertTo-HLNvidiaDriverVersion {
    param([string]$WindowsVersion)
    $parts = "$WindowsVersion".Split('.')
    if ($parts.Count -lt 4) { return $null }
    $digits = ($parts[2] + $parts[3].PadLeft(4, '0'))
    if ($digits.Length -lt 5) { return $null }
    $last5 = $digits.Substring($digits.Length - 5)
    return ('{0}.{1}' -f [int]$last5.Substring(0, 3), $last5.Substring(3))
}

<#
    Driver, ReBAR y TDR para cualquier fabricante. Devuelve nada; deja
    resultados y pasos manuales.
#>
function Invoke-HLGpuHealth {
    param(
        [Parameter(Mandatory)] $Hardware,
        [Parameter(Mandatory)] [string] $Module,
        [Parameter(Mandatory)] [string] $DriverLabel,
        [Parameter(Mandatory)] [string] $DriverUrl,
        [int] $MaxDriverAgeDays = 120,
        [string] $RebarName = 'Resizable BAR',
        [string] $RebarNote = ''
    )
    $gpu = $Hardware.GPU.Primary

    $age = if ($gpu.DriverDate) { [int]((Get-Date) - $gpu.DriverDate).TotalDays } else { $null }
    if ($null -ne $age -and $age -gt $MaxDriverAgeDays) {
        Write-HLWarn "Driver: $DriverLabel, $age días. Los drivers recientes traen optimizaciones específicas de Call of Duty."
        Add-HLManualStep 'GPU' "Actualiza el driver ($DriverLabel tiene $age días). Instalación limpia recomendada." $DriverUrl
        Add-HLResult -Module $Module -Item 'Driver' -Status Manual -Detail "$DriverLabel ($age días)"
    } else {
        Write-HLSub "Driver: $DriverLabel" 'OK'
        Add-HLResult -Module $Module -Item 'Driver' -Status Info -Detail $DriverLabel
    }

    $rebar = Get-HLRebarState -Gpu $gpu
    if ($null -eq $rebar) {
        Write-HLSub $RebarName 'MANUAL (no verificable desde Windows; mira GPU-Z)'
        Add-HLResult -Module $Module -Item $RebarName -Status Manual -Detail 'No se pudo leer la apertura PCIe'
    } elseif ($rebar.Enabled) {
        Write-HLSub "$RebarName (apertura $($rebar.ApertureMB) MB)" 'OK'
        Add-HLResult -Module $Module -Item $RebarName -Status Info -Detail "Activo, apertura $($rebar.ApertureMB) MB"
    } else {
        Write-HLSub "$RebarName (apertura $($rebar.ApertureMB) MB)" 'MANUAL (desactivado)'
        $path = Get-HLRebarBiosPath -BoardVendor $Hardware.Board.Vendor
        Add-HLManualStep 'BIOS' ("Activa $RebarName`: $path. Requiere CSM desactivado (arranque UEFI). $RebarNote").Trim()
        Add-HLResult -Module $Module -Item $RebarName -Status Manual -Detail 'Desactivado en BIOS'
    }

    $crashes = Get-HLDisplayCrashes -Days 14
    if ($crashes -gt 0) {
        Write-HLWarn "$crashes reinicios del driver de pantalla (TDR, evento 4101) en 14 días. Si tienes undervolt/OC, relájalo."
        Add-HLResult -Module $Module -Item 'Estabilidad' -Status Manual -Detail "$crashes TDR en 14 días"
    } else {
        Write-HLSub 'Crashes del driver (14 días)' 'OK (0)'
    }
}

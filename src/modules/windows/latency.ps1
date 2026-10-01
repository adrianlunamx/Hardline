#Requires -Version 5.1
<#
    Hardline - latencia avanzada.

    1. Modo MSI (Message Signaled Interrupts) para GPU, tarjeta de red y
       controladores USB.
       Con interrupciones por línea (INTx) varios dispositivos pueden compartir
       línea y el driver tiene que averiguar quién interrumpió. Con MSI cada
       dispositivo escribe su interrupción directamente: menos latencia DPC/ISR
       y menos picos. Muchos drivers ya lo activan solos; Hardline solo lo
       activa donde:
         - el hardware declara soporte MSI/MSI-X (DEVPKEY_PciDevice_InterruptSupport), y
         - no está ya activo.
       Requiere reinicio. Se verifica con LatencyMon (picos de ISR/DPC).
       https://learn.microsoft.com/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry

    2. Tarjeta de red: Interrupt Moderation OFF y RSS ON.
       Interrupt Moderation agrupa paquetes para generar menos interrupciones:
       ahorra CPU a costa de retrasar la entrega de cada paquete. En juego se
       prefiere entregar cada paquete en cuanto llega. RSS reparte el
       procesamiento de red entre núcleos en lugar de cargarlo todo en uno.
#>

# Bits de DEVPKEY_PciDevice_InterruptSupport: 1 = línea, 2 = MSI, 4 = MSI-X.
function Get-HLMsiCapability {
    param([Parameter(Mandatory)] [string] $InstanceId)
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_PciDevice_InterruptSupport' -ErrorAction Stop
        if ($null -eq $p.Data) { return $null }
        return [int]$p.Data
    } catch {
        return $null
    }
}

function Get-HLMsiTargets {
    param($Hardware)
    $list = New-Object System.Collections.Generic.List[object]

    # GPU dedicada
    if ($Hardware -and $Hardware.GPU.Primary -and -not $Hardware.GPU.Primary.Integrated -and $Hardware.GPU.Primary.PnpId) {
        $list.Add([pscustomobject]@{ Kind = 'GPU'; Name = $Hardware.GPU.Primary.Name; InstanceId = $Hardware.GPU.Primary.PnpId })
    }
    # Tarjetas de red físicas en PCIe (Ethernet y Wi-Fi)
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PnPDeviceID -like 'PCI\*' })) {
        $list.Add([pscustomobject]@{ Kind = 'Red'; Name = $a.InterfaceDescription; InstanceId = $a.PnPDeviceID })
    }
    # Controladores USB (xHCI): ratón, teclado y headset USB cuelgan de aquí.
    foreach ($u in @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\*' })) {
        $list.Add([pscustomobject]@{ Kind = 'USB'; Name = $u.FriendlyName; InstanceId = $u.InstanceId })
    }
    return $list
}

function Set-HLMsiMode {
    param($Hardware)

    $changed = 0
    foreach ($t in (Get-HLMsiTargets -Hardware $Hardware)) {
        $cap = Get-HLMsiCapability -InstanceId $t.InstanceId
        if ($null -eq $cap) {
            Add-HLResult -Module 'Latencia' -Item "MSI $($t.Kind): $($t.Name)" -Status Skipped -Detail 'Windows no informa del tipo de interrupción soportado: no se toca'
            continue
        }
        if (($cap -band 6) -eq 0) {
            Add-HLResult -Module 'Latencia' -Item "MSI $($t.Kind): $($t.Name)" -Status Skipped -Detail 'El hardware solo soporta interrupciones por línea'
            continue
        }
        $key = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($t.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        try {
            $ok = Set-HLRegistryValue -Path $key -Name 'MSISupported' -Value 1 -Type DWord -Reason "Modo MSI para $($t.Name)"
            if ($ok) {
                $changed++
                Add-HLResult -Module 'Latencia' -Item "MSI $($t.Kind): $($t.Name)" -Status Applied -Detail 'Activado (efectivo tras reiniciar)'
            } else {
                Add-HLResult -Module 'Latencia' -Item "MSI $($t.Kind): $($t.Name)" -Status Skipped -Detail 'Ya estaba en modo MSI'
            }
        } catch {
            Add-HLResult -Module 'Latencia' -Item "MSI $($t.Kind): $($t.Name)" -Status Failed -Detail $_.Exception.Message
        }
    }
    if ($changed -gt 0) { $HL.NeedsReboot = $true }
    Write-HLSub "Modo MSI de interrupciones ($changed dispositivos)" 'OK'
    Add-HLManualStep 'Latencia' 'Tras reiniciar, pasa LatencyMon 5 min: los picos de "ISR" y "DPC" deberían bajar. Si algún dispositivo deja de funcionar (muy raro), rollback.ps1 lo devuelve a su modo anterior.' 'https://www.resplendence.com/latencymon'
}

<#
    Aplica palabras clave NDIS a una NIC guardando el valor anterior.
    Solo toca las que el driver expone. Devuelve las que cambió.
#>
function Set-HLNicKeywords {
    param([Parameter(Mandatory)] [string] $AdapterName, [Parameter(Mandatory)] $Targets)
    $props = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -AllProperties -ErrorAction Stop)
    $changed = @()
    foreach ($t in $Targets) {
        $p = $props | Where-Object { $_.RegistryKeyword -eq $t.Keyword } | Select-Object -First 1
        if (-not $p) { continue }
        $prev = "$(@($p.RegistryValue)[0])"
        if ($prev -eq $t.Value) { continue }
        if ($HL.DryRun) { $changed += $t.Keyword; continue }
        Add-HLManifestEntry -Type 'NetAdapterProperty' -Data @{ Adapter = $AdapterName; Keyword = $t.Keyword; PrevValue = $prev; NewValue = $t.Value }
        Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $t.Keyword -RegistryValue $t.Value -NoRestart -ErrorAction Stop
        $changed += $t.Keyword
    }
    return $changed
}

function Set-HLNicLatency {
    param($Hardware)
    $targets = @(
        @{ Keyword = '*InterruptModeration'; Value = '0' }   # entregar cada paquete al llegar
        @{ Keyword = '*RSS';                 Value = '1' }   # repartir el procesamiento entre núcleos
    )
    $adapters = @($Hardware.Network.Adapters | Where-Object { -not $_.Wireless })
    if ($adapters.Count -eq 0) {
        Add-HLResult -Module 'Latencia' -Item 'NIC' -Status Skipped -Detail 'Sin adaptador Ethernet activo'
        return
    }
    foreach ($a in $adapters) {
        $changed = @(Set-HLNicKeywords -AdapterName $a.Name -Targets $targets)
        if ($changed.Count -gt 0) {
            Write-HLSub "NIC $($a.Name): $($changed -join ', ')" 'OK'
            Add-HLResult -Module 'Latencia' -Item "NIC $($a.Name)" -Status Applied -Detail ('Interrupt Moderation off / RSS on: ' + ($changed -join ', ') + '. El adaptador se reinicia al reiniciar el equipo.')
            $HL.NeedsReboot = $true
        } else {
            Add-HLResult -Module 'Latencia' -Item "NIC $($a.Name)" -Status Skipped -Detail 'Ya configurada o el driver no expone esas opciones'
        }
    }
}

function Invoke-HLLatency {
    param([Parameter(Mandatory)] $Hardware)
    Write-HLStep 'Latencia avanzada...'
    Invoke-HLSafely 'Latencia' 'Modo MSI' { Set-HLMsiMode -Hardware $Hardware }
    Invoke-HLSafely 'Latencia' 'NIC' { Set-HLNicLatency -Hardware $Hardware }
}

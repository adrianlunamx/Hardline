#Requires -Version 5.1
<#
    Hardline - red.

    Warzone usa UDP para el tráfico de juego. Eso descarta de entrada la mitad
    de los "tweaks de red" que circulan (Nagle, TcpAckFrequency, TCPNoDelay):
    solo afectan a TCP y no cambian nada in-game. Hardline no los aplica.

    Lo que sí se hace:
      - TCP autotuning en "normal" (window scaling). Afecta a descargas del
        launcher y parches, no al ping de juego. Solo se corrige si alguien lo
        dejó en "disabled"/"highlyrestricted" con un tweak antiguo.
      - Ahorro de energía de la NIC (EEE / Green Ethernet) OFF: EEE duerme el
        enlace entre paquetes y añade microlatencia al despertar.
      - DNS Cloudflare 1.1.1.1: no cambia el ping al servidor de juego, pero sí
        el tiempo de resolución del matchmaking y del launcher.
      - Política QoS con DSCP 46 (EF) para cod.exe. Solo tiene efecto si tu
        router respeta DSCP (muchos con SQM/QoS lo hacen; la mayoría de routers
        de operadora no).
#>

function Invoke-HLNetwork {
    param([Parameter(Mandatory)] $Hardware)

    $net = $Hardware.Network
    if (-not $net.Primary) {
        Write-HLWarn 'Sin adaptador de red activo con ruta por defecto. Se omite el módulo de red.'
        Add-HLResult -Module 'Red' -Item 'Adaptador' -Status Skipped -Detail 'No hay adaptador activo'
        return
    }

    if ($net.Primary.Wireless) {
        Write-HLWarn 'Estás por Wi-Fi. Ningún tweak compensa la variabilidad de latencia del Wi-Fi: usa cable si puedes.'
        Add-HLManualStep 'Red' 'Conecta por Ethernet. Wi-Fi añade jitter y pérdida de paquetes que ningún ajuste de Windows corrige.'
    }

    Invoke-HLSafely 'Red' 'TCP autotuning' { Set-HLTcpAutoTuning }
    foreach ($a in @($net.Adapters | Where-Object { -not $_.Wireless })) {
        Invoke-HLSafely 'Red' "Ahorro de energía NIC ($($a.Name))" { Set-HLNicPowerSaving -Adapter $a }
    }
    foreach ($a in @($net.Adapters)) {
        Invoke-HLSafely 'Red' "DNS ($($a.Name))" { Set-HLDns -Adapter $a }
    }
    Invoke-HLSafely 'Red' 'QoS cod.exe' { Set-HLQos -Hardware $Hardware }

    Write-HLSub 'Bufferbloat' 'MANUAL (test externo)'
    Add-HLManualStep 'Red' ('Haz el test de bufferbloat. Si sale B o peor, activa SQM (fq_codel/cake) o QoS en el router y limita el ancho de banda ' +
        'al ~90% del contratado. Es la causa número uno de picos de ping cuando alguien más usa la red.') 'https://www.waveform.com/tools/bufferbloat'
    if ($net.Primary.Gateway) {
        Add-HLManualStep 'Red' "Router detectado en $($net.Primary.Gateway). Si soporta QoS por DSCP, prioriza EF (46): Hardline ya marca el tráfico de cod.exe."
    }
}

function Set-HLTcpAutoTuning {
    $s = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue
    if (-not $s) { $s = Get-NetTCPSetting -ErrorAction Stop | Where-Object { $_.AutoTuningLevelLocal } | Select-Object -First 1 }
    $current = "$($s.AutoTuningLevelLocal)"
    if ($current -eq 'Normal') {
        Write-HLSub 'TCP window scaling (autotuning)' 'OK (ya en normal)'
        Add-HLResult -Module 'Red' -Item 'TCP autotuning' -Status Skipped -Detail 'Ya en Normal'
        return
    }
    if ($HL.DryRun) { Write-HLSub 'TCP window scaling (autotuning)' 'SKIP (DryRun)'; return }
    Add-HLManifestEntry -Type 'TcpAutoTuning' -Data @{ PrevLevel = $current }
    & netsh.exe int tcp set global autotuninglevel=normal | Out-Null
    Write-HLSub "TCP window scaling ($current -> normal)" 'OK'
    Add-HLResult -Module 'Red' -Item 'TCP autotuning' -Status Applied -Detail "$current -> Normal"
}

<#
    Palabras clave estándar de NDIS (*EEE) y las propietarias más comunes de
    Intel (I225/I226) y Realtek (8125/8111). Se usan las RegistryKeyword, no
    los DisplayName, porque estos están traducidos según el idioma del driver.
#>
function Set-HLNicPowerSaving {
    param([Parameter(Mandatory)] $Adapter)

    $targets = @(
        @{ Keyword = '*EEE';                   Value = '0'; Why = 'Energy Efficient Ethernet (estándar NDIS)' }
        @{ Keyword = 'EEELinkAdvertisement';   Value = '0'; Why = 'EEE en Intel I225/I226' }
        @{ Keyword = 'AdvancedEEE';            Value = '0'; Why = 'Advanced EEE (Realtek)' }
        @{ Keyword = 'EnableGreenEthernet';    Value = '0'; Why = 'Green Ethernet (Realtek)' }
        @{ Keyword = 'GigaLite';               Value = '0'; Why = 'Giga Lite (Realtek): baja el enlace a 500 Mbps para ahorrar' }
        @{ Keyword = 'PowerSavingMode';        Value = '0'; Why = 'Power Saving Mode (Realtek)' }
        @{ Keyword = 'ULPMode';                Value = '0'; Why = 'Ultra Low Power (Intel)' }
    )
    $props = @(Get-NetAdapterAdvancedProperty -Name $Adapter.Name -AllProperties -ErrorAction Stop)
    $changed = @()
    foreach ($t in $targets) {
        $p = $props | Where-Object { $_.RegistryKeyword -eq $t.Keyword } | Select-Object -First 1
        if (-not $p) { continue }
        $prev = @($p.RegistryValue)[0]
        if ("$prev" -eq $t.Value) { continue }
        if ($HL.DryRun) { $changed += $t.Keyword; continue }
        Add-HLManifestEntry -Type 'NetAdapterProperty' -Data @{ Adapter = $Adapter.Name; Keyword = $t.Keyword; PrevValue = "$prev"; NewValue = $t.Value }
        Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $t.Keyword -RegistryValue $t.Value -NoRestart -ErrorAction Stop
        $changed += $t.Keyword
    }
    if ($changed.Count -gt 0) {
        Write-HLSub "NIC $($Adapter.Name): ahorro de energía OFF ($($changed -join ', '))" 'OK'
        Add-HLResult -Module 'Red' -Item "NIC $($Adapter.Name)" -Status Applied -Detail ("Desactivado: " + ($changed -join ', ') + '. Se aplica al reiniciar el adaptador o el equipo.')
        $HL.NeedsReboot = $true
    } else {
        Write-HLSub "NIC $($Adapter.Name): ahorro de energía" 'OK (nada que cambiar)'
        Add-HLResult -Module 'Red' -Item "NIC $($Adapter.Name)" -Status Skipped -Detail 'Sin EEE/Green Ethernet activo o no soportado'
    }
}

function Set-HLDns {
    param([Parameter(Mandatory)] $Adapter)

    $v4 = @('1.1.1.1', '1.0.0.1')
    $v6 = @('2606:4700:4700::1111', '2606:4700:4700::1001')

    # El valor NameServer de la interfaz solo contiene los DNS estáticos.
    # Vacío = DNS por DHCP. Get-DnsClientServerAddress mezcla ambos, por eso
    # se lee el registro para poder restaurar exactamente.
    $key4 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($Adapter.Guid)"
    $static4 = "$((Get-ItemProperty $key4 -ErrorAction SilentlyContinue).NameServer)"
    $key6 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$($Adapter.Guid)"
    $static6 = "$((Get-ItemProperty $key6 -ErrorAction SilentlyContinue).NameServer)"
    $prev = @(($static4 -split '[, ]') + ($static6 -split '[, ]') | Where-Object { $_ })

    $hasV6 = [bool](Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike 'fe80*' })
    $target = if ($hasV6) { $v4 + $v6 } else { $v4 }

    if (($prev -join ',') -eq ($target -join ',')) {
        Write-HLSub "DNS $($Adapter.Name) -> Cloudflare" 'OK (ya configurado)'
        Add-HLResult -Module 'Red' -Item "DNS $($Adapter.Name)" -Status Skipped -Detail 'Ya en 1.1.1.1'
        return
    }
    if ($HL.DryRun) { Write-HLSub "DNS $($Adapter.Name) -> Cloudflare" 'SKIP (DryRun)'; return }

    Add-HLManifestEntry -Type 'Dns' -Data @{ InterfaceIndex = $Adapter.InterfaceIndex; InterfaceAlias = $Adapter.Name; InterfaceGuid = "$($Adapter.Guid)"; PrevServers = $prev; NewServers = $target }
    Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses $target -ErrorAction Stop
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    $from = if ($prev.Count) { $prev -join ', ' } else { 'DHCP' }
    Write-HLSub "DNS $($Adapter.Name): $from -> 1.1.1.1" 'OK'
    Add-HLResult -Module 'Red' -Item "DNS $($Adapter.Name)" -Status Applied -Detail "$from -> $($target -join ', ')"
}

function Set-HLQos {
    param([Parameter(Mandatory)] $Hardware)

    $name = 'Hardline-Warzone'
    if (Get-NetQosPolicy -Name $name -ErrorAction SilentlyContinue) {
        Write-HLSub 'QoS DSCP 46 para cod.exe' 'OK (ya existe)'
        Add-HLResult -Module 'Red' -Item 'QoS cod.exe' -Status Skipped -Detail 'La política ya existía'
        return
    }
    if ($HL.DryRun) { Write-HLSub 'QoS DSCP 46 para cod.exe' 'SKIP (DryRun)'; return }

    # En equipos fuera de dominio Windows ignora el marcado DSCP salvo que se
    # desactive la comprobación NLA del servicio QoS.
    Set-HLRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS' -Name 'Do not use NLA' -Value '1' -Type String `
        -Reason 'Permite que las políticas QoS marquen DSCP fuera de un dominio.' | Out-Null

    # Se registra antes de crear: si el proceso muere entre ambas líneas, el
    # rollback sabe que la política es nuestra (el undo tolera que no exista).
    Add-HLManifestEntry -Type 'QosPolicy' -Data @{ Name = $name }
    New-NetQosPolicy -Name $name -AppPathNameMatchCondition 'cod.exe' -IPProtocolMatchCondition Both `
        -DSCPAction 46 -NetworkProfile All -ErrorAction Stop | Out-Null

    Write-HLSub 'QoS DSCP 46 para cod.exe' 'OK'
    Add-HLResult -Module 'Red' -Item 'QoS cod.exe' -Status Applied -Detail 'DSCP 46 (EF). Efectivo solo si el router respeta DSCP.'
}

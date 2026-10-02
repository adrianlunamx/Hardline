#Requires -Version 5.1
<#
    Hardline - diagnóstico de red ("registro de balas").

    Lo que decide si una bala registra está en el servidor de Activision:
    ningún tweak de Windows lo cambia. Lo que SÍ depende de ti es lo que le
    llega al servidor desde tu PC, y eso es medible:

      Pérdida de paquetes  Un paquete perdido = un disparo o un movimiento que
                           el servidor recibe tarde o nunca.
      Jitter               Variación del ping. El juego compensa un ping
                           estable; un ping que salta es lo que produce
                           "le di primero y morí yo".
      Bufferbloat          Cuánto sube el ping cuando alguien (o algo) usa la
                           conexión. Es la causa número uno de partidas que
                           van bien y de repente no.
      MTU                  Si es menor de lo esperado, puede haber
                           fragmentación (VPN, PPPoE mal configurado).

    Se mide al router y a Internet por separado: así se sabe si el problema
    está en tu casa (cable, Wi-Fi, router) o en tu proveedor.

    Descarga ~100-250 MB de speed.cloudflare.com durante unos 10 s para el
    test de carga.
#>

function Measure-HLPingSeries {
    param([Parameter(Mandatory)] [string] $Target, [int]$Count = 50, [int]$IntervalMs = 50, [int]$TimeoutMs = 1000)
    $p = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        try {
            $r = $p.Send($Target, $TimeoutMs)
            if ($r.Status -eq 'Success') { $rtts.Add([double]$r.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        if ($IntervalMs -gt 0) { Start-Sleep -Milliseconds $IntervalMs }
    }
    $p.Dispose()
    return (Get-HLPingStats -Rtts $rtts.ToArray() -Lost $lost -Target $Target)
}

# Estadísticas de una serie de RTT. Separada para poder probarla sin red.
function Get-HLPingStats {
    param([double[]]$Rtts, [int]$Lost, [string]$Target = '')
    $n = @($Rtts).Count
    $total = $n + $Lost
    if ($n -eq 0) {
        return [pscustomobject]@{ Target = $Target; Sent = $total; LossPct = 100; AvgMs = $null; MedianMs = $null; P95Ms = $null; JitterMs = $null }
    }
    $sorted = @($Rtts | Sort-Object)
    $jit = 0.0
    for ($i = 1; $i -lt $n; $i++) { $jit += [math]::Abs($Rtts[$i] - $Rtts[$i - 1]) }
    [pscustomobject]@{
        Target   = $Target
        Sent     = $total
        LossPct  = [math]::Round(100.0 * $Lost / [math]::Max(1, $total), 1)
        AvgMs    = [math]::Round(($Rtts | Measure-Object -Average).Average, 1)
        MedianMs = $sorted[[int][math]::Floor(($n - 1) / 2)]
        P95Ms    = $sorted[[int][math]::Ceiling(0.95 * $n) - 1]
        JitterMs = $(if ($n -gt 1) { [math]::Round($jit / ($n - 1), 1) } else { 0 })
    }
}

# Nota tipo waveform.com según los ms que sube el ping bajo carga.
function Get-HLBufferbloatGrade {
    param([double]$AddedMs)
    if ($AddedMs -lt 5) { return 'A+' }
    if ($AddedMs -lt 30) { return 'A' }
    if ($AddedMs -lt 60) { return 'B' }
    if ($AddedMs -lt 200) { return 'C' }
    if ($AddedMs -lt 400) { return 'D' }
    return 'F'
}

function Measure-HLBufferbloat {
    param([string]$Target = '1.1.1.1', [int]$LoadSeconds = 10)
    $idle = Measure-HLPingSeries -Target $Target -Count 20 -IntervalMs 100

    # Carga de descarga en otro proceso: lee y descarta, sin escribir a disco.
    $job = Start-Job -ScriptBlock {
        param($Seconds)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $bytes = [long]0
        $buf = New-Object byte[] 262144
        try {
            while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
                $req = [Net.WebRequest]::Create('https://speed.cloudflare.com/__down?bytes=250000000')
                $req.Timeout = 15000
                $resp = $req.GetResponse()
                $s = $resp.GetResponseStream()
                while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
                    $n = $s.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $bytes += $n
                }
                $s.Close(); $resp.Close()
            }
        } catch { }
        [pscustomobject]@{ Bytes = $bytes; Seconds = $sw.Elapsed.TotalSeconds }
    } -ArgumentList ($LoadSeconds + 2)

    Start-Sleep -Seconds 2   # que la descarga coja velocidad
    $loaded = Measure-HLPingSeries -Target $Target -Count ([math]::Max(10, $LoadSeconds * 4)) -IntervalMs 200
    $r = Receive-Job -Job $job -Wait -AutoRemoveJob
    $mbps = if ($r -and $r.Seconds -gt 0) { [math]::Round($r.Bytes * 8 / $r.Seconds / 1e6, 0) } else { $null }

    $added = $null; $grade = $null
    if ($null -ne $idle.MedianMs -and $null -ne $loaded.MedianMs) {
        $added = [math]::Max([double]0, [double]$loaded.MedianMs - [double]$idle.MedianMs)
        $grade = Get-HLBufferbloatGrade -AddedMs $added
    }
    [pscustomobject]@{ Idle = $idle; Loaded = $loaded; AddedMs = $added; Grade = $grade; DownloadMbps = $mbps }
}

# MTU real del camino: ping con "no fragmentar" y búsqueda binaria del tamaño máximo.
function Measure-HLMtu {
    param([string]$Target = '1.1.1.1')
    $p = New-Object System.Net.NetworkInformation.Ping
    $opt = New-Object System.Net.NetworkInformation.PingOptions(64, $true)
    $fits = {
        param($size)
        try { return ($p.Send($Target, 1500, (New-Object byte[] $size), $opt).Status -eq 'Success') } catch { return $false }
    }
    if (-not (& $fits 548)) { $p.Dispose(); return $null }   # sin respuesta ni con paquetes pequeños
    $lo = 548; $hi = 1472
    while ($lo -lt $hi) {
        $mid = [int][math]::Ceiling(($lo + $hi) / 2)
        if (& $fits $mid) { $lo = $mid } else { $hi = $mid - 1 }
    }
    $p.Dispose()
    return ($lo + 28)   # + 20 de cabecera IP + 8 de ICMP
}

<#
    Convierte las mediciones en hallazgos con recomendación. Separada de la
    medición para poder probarla con datos inventados.
#>
function Get-HLNetFindings {
    param($Diag)
    $f = New-Object System.Collections.Generic.List[object]
    $add = { param($sev, $title, $text) $f.Add([pscustomobject]@{ Severity = $sev; Title = $title; Text = $text }) }

    if ($Diag.Wireless) {
        & $add 'warn' 'Wi-Fi' 'Estás por Wi-Fi: añade jitter y pérdidas que ningún ajuste corrige. Un cable Ethernet es la mejora de red más grande posible.'
    }
    $gw = $Diag.Gateway; $net = $Diag.Internet
    if ($gw -and $gw.LossPct -gt 0.5) {
        & $add 'bad' 'Pérdida en tu red local' ("{0}% de paquetes perdidos hasta el router: el problema está en casa (cable, Wi-Fi, router o adaptador de red)." -f $gw.LossPct)
    } elseif ($net -and $net.LossPct -gt 0.5) {
        & $add 'bad' 'Pérdida en Internet' ("{0}% de pérdida hacia Internet pero 0% hasta el router: el problema está en tu proveedor. Repite a otra hora y, si persiste, abre incidencia con estos datos." -f $net.LossPct)
    } else {
        & $add 'ok' 'Pérdida de paquetes' 'Sin pérdidas apreciables.'
    }
    if ($net -and $null -ne $net.JitterMs) {
        if ($net.JitterMs -gt 8) { & $add 'bad' 'Jitter alto' ("{0} ms de variación de ping. Por encima de ~5 ms se nota en los duelos." -f $net.JitterMs) }
        elseif ($net.JitterMs -gt 4) { & $add 'warn' 'Jitter moderado' ("{0} ms. Aceptable, mejorable con cable y SQM." -f $net.JitterMs) }
        else { & $add 'ok' 'Jitter' ("{0} ms: estable." -f $net.JitterMs) }
    }
    $bb = $Diag.Bufferbloat
    if ($bb -and $bb.Grade) {
        $sev = switch ($bb.Grade) { { $_ -in 'A+', 'A' } { 'ok' } 'B' { 'warn' } default { 'bad' } }
        $txt = "Nota {0}: el ping sube {1} ms al descargar." -f $bb.Grade, $bb.AddedMs
        if ($sev -ne 'ok') { $txt += ' Activa SQM (fq_codel/cake) o QoS en el router y limita al ~90% de tu velocidad contratada; si el router no lo permite, evita descargas y streams mientras juegas.' }
        & $add $sev 'Bufferbloat' $txt
    }
    if ($Diag.Mtu) {
        if ($Diag.Mtu -lt 1450) { & $add 'warn' 'MTU baja' ("MTU {0}: típico de una VPN o túnel. Si no usas VPN, revisa la configuración PPPoE del router." -f $Diag.Mtu) }
        elseif ($Diag.Mtu -lt 1500) { & $add 'ok' 'MTU' ("MTU {0}: normal en conexiones PPPoE (fibra de muchos proveedores)." -f $Diag.Mtu) }
        else { & $add 'ok' 'MTU' 'MTU 1500: sin fragmentación.' }
    }
    return $f
}

function Invoke-HLNetDiagnosis {
    param([Parameter(Mandatory)] $Hardware)
    Write-HLStep 'Diagnóstico de red (~40 s, descarga de prueba incluida)...'
    $gwIp = if ($Hardware.Network.Primary) { $Hardware.Network.Primary.Gateway } else { $null }

    Write-Progress -Activity 'Diagnóstico de red' -Status 'Router' -PercentComplete 5
    $gw = if ($gwIp) { Measure-HLPingSeries -Target $gwIp -Count 100 -IntervalMs 20 } else { $null }
    Write-Progress -Activity 'Diagnóstico de red' -Status 'Internet (1.1.1.1)' -PercentComplete 25
    $net = Measure-HLPingSeries -Target '1.1.1.1' -Count 100 -IntervalMs 20
    Write-Progress -Activity 'Diagnóstico de red' -Status 'Bufferbloat (descarga de prueba)' -PercentComplete 45
    $bb = $null
    try { $bb = Measure-HLBufferbloat } catch { Write-HLLog WARN "Bufferbloat: $($_.Exception.Message)" }
    Write-Progress -Activity 'Diagnóstico de red' -Status 'MTU' -PercentComplete 90
    $mtu = Measure-HLMtu
    Write-Progress -Activity 'Diagnóstico de red' -Completed

    $diag = [pscustomobject]@{
        Time        = Get-Date
        Wireless    = [bool]($Hardware.Network.Primary -and $Hardware.Network.Primary.Wireless)
        Gateway     = $gw
        Internet    = $net
        Bufferbloat = $bb
        Mtu         = $mtu
        Findings    = $null
    }
    $diag.Findings = @(Get-HLNetFindings -Diag $diag)
    $HL.NetDiag = $diag

    if ($gw) { Write-HLInfo ('Router {0}: {1} ms, jitter {2} ms, pérdida {3}%' -f $gwIp, $gw.AvgMs, $gw.JitterMs, $gw.LossPct) }
    Write-HLInfo ('Internet: {0} ms, jitter {1} ms, pérdida {2}%' -f $net.AvgMs, $net.JitterMs, $net.LossPct)
    if ($bb -and $bb.Grade) { Write-HLInfo ('Bufferbloat: nota {0} (+{1} ms bajo carga, descarga ~{2} Mbps)' -f $bb.Grade, $bb.AddedMs, $bb.DownloadMbps) }
    if ($mtu) { Write-HLInfo "MTU: $mtu" }
    foreach ($x in $diag.Findings) {
        switch ($x.Severity) {
            'bad'  { Write-HLWarn "$($x.Title): $($x.Text)"; Add-HLResult -Module 'Diagnóstico de red' -Item $x.Title -Status Manual -Detail $x.Text }
            'warn' { Write-HLWarn "$($x.Title): $($x.Text)"; Add-HLResult -Module 'Diagnóstico de red' -Item $x.Title -Status Manual -Detail $x.Text }
            default { Add-HLResult -Module 'Diagnóstico de red' -Item $x.Title -Status Info -Detail $x.Text }
        }
    }
    return $diag
}

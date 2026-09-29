#Requires -Version 5.1
<#
    Hardline - benchmarks pre/post.

    Lo que se mide siempre (no requiere nada instalado, ~20 s):
      - Resolución actual del timer del sistema (NtQueryTimerResolution).
      - Jitter real de Sleep(1): 300 muestras, media y p99. Es el indicador más
        directo de lo que ganas con timer resolution + plan de energía.
      - Ping a 1.1.1.1 y al router: media, jitter, pérdida.
      - Tiempo de resolución DNS.

    Lo que se mide si está instalado:
      - CapFrameX: se leen las capturas más recientes (avg FPS, 1% low, 0.1% low).
        Hardline no puede lanzar la partida por ti: graba una captura de 60 s en
        el mismo sitio (p. ej. el campo de tiro) antes y después.
      - LatencyMon: solo se comprueba que exista y se indica cómo usarlo.
#>

function Initialize-HLTimerApi {
    if ('Hardline.Timer' -as [type]) { return }
    Add-Type -Namespace Hardline -Name Timer -MemberDefinition @'
[DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint Minimum, out uint Maximum, out uint Current);
'@
}

function Measure-HLTimer {
    Initialize-HLTimerApi
    $min = 0; $max = 0; $cur = 0
    [void][Hardline.Timer]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)

    $n = 300
    $samples = New-Object double[] $n
    $sw = New-Object System.Diagnostics.Stopwatch
    for ($i = 0; $i -lt $n; $i++) {
        $sw.Restart()
        [System.Threading.Thread]::Sleep(1)
        $sw.Stop()
        $samples[$i] = $sw.Elapsed.TotalMilliseconds
    }
    $sorted = $samples | Sort-Object
    [pscustomobject]@{
        TimerResMs  = [math]::Round($cur / 10000.0, 3)
        TimerBestMs = [math]::Round($max / 10000.0, 3)
        Sleep1AvgMs = [math]::Round(($samples | Measure-Object -Average).Average, 3)
        Sleep1P99Ms = [math]::Round($sorted[[int]($n * 0.99) - 1], 3)
    }
}

function Measure-HLPing {
    param([string]$Target, [int]$Count = 20)
    if (-not $Target) { return $null }
    $p = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        try {
            $r = $p.Send($Target, 1000)
            if ($r.Status -eq 'Success') { $rtts.Add([double]$r.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds 100
    }
    $p.Dispose()
    if ($rtts.Count -eq 0) { return [pscustomobject]@{ Target = $Target; AvgMs = $null; JitterMs = $null; LossPct = 100 } }
    $jit = 0.0
    for ($i = 1; $i -lt $rtts.Count; $i++) { $jit += [math]::Abs($rtts[$i] - $rtts[$i - 1]) }
    $jit = if ($rtts.Count -gt 1) { $jit / ($rtts.Count - 1) } else { 0 }
    [pscustomobject]@{
        Target   = $Target
        AvgMs    = [math]::Round(($rtts | Measure-Object -Average).Average, 1)
        JitterMs = [math]::Round($jit, 1)
        LossPct  = [math]::Round(100.0 * $lost / $Count, 1)
    }
}

function Measure-HLDns {
    $times = @()
    for ($i = 0; $i -lt 5; $i++) {
        # Subdominio aleatorio: fuerza consulta al servidor (sin caché).
        $name = 'hl{0}.cloudflare.com' -f ([guid]::NewGuid().ToString('N').Substring(0, 10))
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { Resolve-DnsName -Name $name -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue | Out-Null } catch { }
        $sw.Stop()
        $times += $sw.Elapsed.TotalMilliseconds
    }
    return [math]::Round((($times | Sort-Object)[2]), 1)   # mediana
}

function Get-HLCapFrameXDir {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $d = Join-Path $docs 'CapFrameX\Captures'
    if (Test-Path $d) { return $d }
    return $null
}

<#
    Lee una captura JSON de CapFrameX. El formato guarda los frametimes en
    Runs[].CaptureData.MsBetweenPresents. Se calcula igual que CapFrameX:
    1% low = FPS del percentil 99 de frametime.
#>
function Read-HLCapFrameXCapture {
    param([Parameter(Mandatory)] [string] $Path)
    try {
        $j = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $ft = @()
        foreach ($run in @($j.Runs)) {
            if ($run.CaptureData -and $run.CaptureData.MsBetweenPresents) { $ft += @($run.CaptureData.MsBetweenPresents) }
        }
        if ($ft.Count -lt 100) { return $null }
        $sorted = $ft | Sort-Object
        $avg = ($ft | Measure-Object -Average).Average
        $p99 = $sorted[[int]($sorted.Count * 0.99) - 1]
        $p999 = $sorted[[int]($sorted.Count * 0.999) - 1]
        $proc = if ($j.Info -and $j.Info.ProcessName) { $j.Info.ProcessName } else { '' }
        [pscustomobject]@{
            File     = Split-Path $Path -Leaf
            Process  = $proc
            Time     = (Get-Item $Path).LastWriteTime
            AvgFps   = [math]::Round(1000 / $avg, 1)
            Low1Fps  = [math]::Round(1000 / $p99, 1)
            Low01Fps = [math]::Round(1000 / $p999, 1)
            Frames   = $ft.Count
        }
    } catch {
        Write-HLLog WARN "No se pudo leer la captura $Path : $($_.Exception.Message)"
        return $null
    }
}

function Invoke-HLBenchmark {
    param([Parameter(Mandatory)] [ValidateSet('Pre', 'Post')] [string] $Phase, $Hardware)

    Write-HLSub "Benchmark de latencia del sistema ($Phase)"
    Write-Progress -Activity 'Hardline benchmark' -Status 'Timer y Sleep(1)' -PercentComplete 10
    $timer = Measure-HLTimer
    Write-Progress -Activity 'Hardline benchmark' -Status 'Ping 1.1.1.1' -PercentComplete 40
    $pingCf = Measure-HLPing -Target '1.1.1.1'
    Write-Progress -Activity 'Hardline benchmark' -Status 'Ping router' -PercentComplete 70
    $gw = if ($Hardware -and $Hardware.Network.Primary) { $Hardware.Network.Primary.Gateway } else { $null }
    $pingGw = Measure-HLPing -Target $gw
    Write-Progress -Activity 'Hardline benchmark' -Status 'DNS' -PercentComplete 90
    $dns = Measure-HLDns
    Write-Progress -Activity 'Hardline benchmark' -Completed

    $capture = $null
    $cfx = Get-HLCapFrameXDir
    if ($cfx) {
        $latest = Get-ChildItem $cfx -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $capture = Read-HLCapFrameXCapture -Path $latest.FullName }
    }

    $result = [pscustomobject]@{
        Phase   = $Phase
        Time    = Get-Date
        Timer   = $timer
        PingCf  = $pingCf
        PingGw  = $pingGw
        DnsMs   = $dns
        Capture = $capture
    }

    Write-HLInfo ('Timer {0} ms | Sleep(1) media {1} ms, p99 {2} ms' -f $timer.TimerResMs, $timer.Sleep1AvgMs, $timer.Sleep1P99Ms)
    if ($null -ne $pingCf.AvgMs) { Write-HLInfo ('Ping 1.1.1.1: {0} ms, jitter {1} ms, pérdida {2}%' -f $pingCf.AvgMs, $pingCf.JitterMs, $pingCf.LossPct) }
    if ($pingGw -and $null -ne $pingGw.AvgMs) { Write-HLInfo ('Ping router: {0} ms, jitter {1} ms' -f $pingGw.AvgMs, $pingGw.JitterMs) }
    Write-HLInfo "DNS (mediana): $dns ms"
    if ($capture) { Write-HLInfo ('CapFrameX {0}: {1} FPS avg, {2} 1% low, {3} 0.1% low' -f $capture.File, $capture.AvgFps, $capture.Low1Fps, $capture.Low01Fps) }

    if ($Phase -eq 'Pre') {
        if (-not $cfx) {
            Add-HLManualStep 'Benchmark' 'Instala CapFrameX para medir FPS y 1% lows reales en Warzone. Graba 60 s en el mismo recorrido antes y después; Hardline lee la última captura automáticamente.' 'https://www.capframex.com/'
        }
        $latMon = @("$env:ProgramFiles\LatencyMon\LatMon.exe", "${env:ProgramFiles(x86)}\LatencyMon\LatMon.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($latMon) {
            Add-HLManualStep 'Benchmark' "LatencyMon instalado: ejecútalo 5 min con el sistema en reposo. Si 'highest DPC routine execution time' pasa de 500 us, mira qué driver aparece en la pestaña Drivers (típico: red, audio USB, nvlddmkm/amdkmdag)."
        } else {
            Add-HLManualStep 'Benchmark' 'Instala LatencyMon para comprobar la latencia DPC/ISR de tus drivers. Picos > 500 us causan stutter y crujidos de audio que ningún tweak de Windows arregla.' 'https://www.resplendence.com/latencymon'
        }
    }
    return $result
}

function Format-HLBenchComparison {
    param($Pre, $Post)
    if (-not $Pre -or -not $Post) { return @() }
    $rows = New-Object System.Collections.Generic.List[string]
    $fmt = '{0,-26} {1,12} {2,12}'
    $rows.Add(($fmt -f 'Métrica', 'Antes', 'Después'))
    $rows.Add(($fmt -f 'Resolución timer (ms)', $Pre.Timer.TimerResMs, $Post.Timer.TimerResMs))
    $rows.Add(($fmt -f 'Sleep(1) media (ms)', $Pre.Timer.Sleep1AvgMs, $Post.Timer.Sleep1AvgMs))
    $rows.Add(($fmt -f 'Sleep(1) p99 (ms)', $Pre.Timer.Sleep1P99Ms, $Post.Timer.Sleep1P99Ms))
    if ($Pre.PingCf -and $Post.PingCf) {
        $rows.Add(($fmt -f 'Ping 1.1.1.1 (ms)', $Pre.PingCf.AvgMs, $Post.PingCf.AvgMs))
        $rows.Add(($fmt -f 'Jitter 1.1.1.1 (ms)', $Pre.PingCf.JitterMs, $Post.PingCf.JitterMs))
    }
    $rows.Add(($fmt -f 'DNS mediana (ms)', $Pre.DnsMs, $Post.DnsMs))
    if ($Pre.Capture -and $Post.Capture -and $Pre.Capture.File -ne $Post.Capture.File) {
        $rows.Add(($fmt -f 'FPS medio', $Pre.Capture.AvgFps, $Post.Capture.AvgFps))
        $rows.Add(($fmt -f '1% low', $Pre.Capture.Low1Fps, $Post.Capture.Low1Fps))
    }
    return $rows
}

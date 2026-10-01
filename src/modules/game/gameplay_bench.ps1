#Requires -Version 5.1
<#
    Hardline - medir partida.

    Mide Warzone mientras juegas, no un benchmark sintético: cada frame que
    el juego presenta, durante 60 s, con PresentMon (Intel, código abierto,
    lee los eventos ETW de Windows; no toca el proceso del juego).

    Qué sale:
      - FPS medios.
      - 1% y 0.1% lows: los FPS de los peores frames. Es lo que notas como
        tirones; dos configuraciones con los mismos FPS medios pueden sentirse
        muy distintas.
      - Tirones: % de frames que tardan más del doble que el frame típico.
      - Latencia de imagen (si el driver la expone).

    Cada medición se guarda. La siguiente se compara con la anterior; si entre
    medio aplicaste Hardline, la comparación es antes/después. Para que valga,
    mide en el mismo sitio (mismo modo, mismo mapa o el campo de tiro) y con
    la misma forma de jugar.

    PresentMon se descarga de su release oficial en GitHub la primera vez. Se
    comprueba el SHA256 que publica GitHub y la firma digital de Intel antes
    de ejecutarlo.

    Uso:  gameplay_bench.ps1 [-Seconds 60] [-Delay 20] [-NoOpen]
#>
param(
    [ValidateRange(20, 300)] [int] $Seconds = 60,
    [ValidateRange(0, 120)] [int] $Delay = 20,
    [string] $Root = '',
    [switch] $NoOpen
)

if (-not $Root) { $Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
. (Join-Path $Root 'src\core\common.ps1')

# --------------------------------------------------------------------------
# Cálculo (sin hardware: se prueba en tests\validate.ps1)
# --------------------------------------------------------------------------

# Media de la fracción más lenta de los frames, en FPS.
function Get-HLLowFps {
    param([double[]] $SortedDesc, [double] $Fraction)
    $k = [Math]::Max(1, [int][Math]::Ceiling($SortedDesc.Count * $Fraction))
    $sum = 0.0
    for ($i = 0; $i -lt $k; $i++) { $sum += $SortedDesc[$i] }
    return [Math]::Round(1000.0 / ($sum / $k), 1)
}

<#
    Estadística de una captura. FrameTimesMs: duración de cada frame en ms.
    FPS medios ponderados por tiempo (frames / segundos), no media de FPS.
#>
function Get-HLFrameStats {
    param([double[]] $FrameTimesMs, [double[]] $LatencyMs = @())
    $ft = @($FrameTimesMs | Where-Object { $_ -gt 0 -and $_ -lt 1000 })
    if ($ft.Count -lt 30) { return $null }
    $sum = ($ft | Measure-Object -Sum).Sum
    $desc = [double[]]@($ft | Sort-Object -Descending)
    $asc = [double[]]@($ft | Sort-Object)
    $median = $asc[[int][Math]::Floor(($asc.Count - 1) / 2)]
    $p99 = $asc[[int][Math]::Ceiling(($asc.Count - 1) * 0.99)]
    $stutters = @($ft | Where-Object { $_ -gt 2 * $median }).Count
    $lat = @($LatencyMs | Where-Object { $_ -gt 0 -and $_ -lt 1000 })
    [pscustomobject]@{
        Frames     = $ft.Count
        Seconds    = [Math]::Round($sum / 1000.0, 1)
        AvgFps     = [Math]::Round(1000.0 * $ft.Count / $sum, 1)
        Low1Fps    = Get-HLLowFps -SortedDesc $desc -Fraction 0.01
        Low01Fps   = Get-HLLowFps -SortedDesc $desc -Fraction 0.001
        MedianMs   = [Math]::Round($median, 2)
        P99Ms      = [Math]::Round($p99, 2)
        StutterPct = [Math]::Round(100.0 * $stutters / $ft.Count, 2)
        LatencyMs  = if ($lat.Count -gt 0) { [Math]::Round((($lat | Measure-Object -Average).Average), 1) } else { $null }
    }
}

<#
    Compara dos capturas. Una diferencia por debajo del umbral es ruido entre
    partidas, no un cambio: se marca como "igual".
#>
function Compare-HLFrameStats {
    param([Parameter(Mandatory)] $Before, [Parameter(Mandatory)] $After)
    $defs = @(
        @{ Key = 'AvgFps';     Label = 'FPS medios';        Higher = $true;  Noise = 3 }
        @{ Key = 'Low1Fps';    Label = '1% lows';           Higher = $true;  Noise = 5 }
        @{ Key = 'Low01Fps';   Label = '0.1% lows';         Higher = $true;  Noise = 8 }
        @{ Key = 'StutterPct'; Label = 'Tirones (%)';       Higher = $false; Noise = 0 }
        @{ Key = 'LatencyMs';  Label = 'Latencia (ms)';     Higher = $false; Noise = 5 }
    )
    foreach ($d in $defs) {
        $b = $Before.($d.Key); $a = $After.($d.Key)
        if ($null -eq $b -or $null -eq $a) { continue }
        $b = [double]$b; $a = [double]$a
        if ($d.Key -eq 'StutterPct') {
            # Puntos porcentuales: con valores cercanos a 0 un % relativo exagera.
            $delta = [Math]::Round($a - $b, 2)
            $better = if ([Math]::Abs($delta) -lt 0.3) { 0 } elseif ($delta -lt 0) { 1 } else { -1 }
            $text = '{0:+0.00;-0.00;0} pts' -f $delta
        } else {
            $pct = if ($b -ne 0) { [Math]::Round(100.0 * ($a - $b) / $b, 1) } else { 0 }
            $sign = if ($d.Higher) { 1 } else { -1 }
            $better = if ([Math]::Abs($pct) -lt $d.Noise) { 0 } elseif ($pct * $sign -gt 0) { 1 } else { -1 }
            $text = '{0:+0.0;-0.0;0} %' -f $pct
        }
        [pscustomobject]@{ Label = $d.Label; Before = $b; After = $a; Change = $text; Better = $better }
    }
}

# Resumen en una frase, a partir de lo que más se nota: 1% lows y tirones.
function Get-HLGameplayVerdict {
    param([Parameter(Mandatory)] $Rows)
    $lows = $Rows | Where-Object { $_.Label -eq '1% lows' } | Select-Object -First 1
    $st = $Rows | Where-Object { $_.Label -eq 'Tirones (%)' } | Select-Object -First 1
    $score = 0
    if ($lows) { $score += 2 * $lows.Better }
    if ($st) { $score += $st.Better }
    foreach ($r in $Rows) { if ($r.Label -in @('FPS medios', 'Latencia (ms)')) { $score += $r.Better } }
    if ($score -ge 2) { return 'Mejora real: se nota en fluidez.' }
    if ($score -le -2) { return 'Peor que antes. Revisa el reporte (¿mismo mapa y modo? ¿algo abierto en segundo plano?) o revierte.' }
    return 'Sin diferencia clara: dentro de lo que varía una partida a otra.'
}

<#
    Filas de un CSV de PresentMon (objetos de Import-Csv) a tiempos de frame.
    PresentMon 2.x: FrameTime / DisplayLatency. 1.x: MsBetweenPresents.
#>
function ConvertFrom-HLPresentMonRows {
    param([Parameter(Mandatory)] $Rows, [string] $Process = 'cod.exe')
    $rows = @($Rows | Where-Object { -not $_.Application -or $_.Application -eq $Process })
    if ($rows.Count -eq 0) { return [pscustomobject]@{ FrameTimes = @(); Latency = @() } }
    $props = $rows[0].PSObject.Properties.Name
    $ftCol = @('FrameTime', 'MsBetweenPresents') | Where-Object { $_ -in $props } | Select-Object -First 1
    $latCol = @('DisplayLatency', 'MsClickToPhotonLatency') | Where-Object { $_ -in $props } | Select-Object -First 1
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $num = { param($v) $x = 0.0; if ([double]::TryParse("$v", [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { $x } else { $null } }
    $ft = if ($ftCol) { [double[]]@($rows | ForEach-Object { & $num $_.$ftCol } | Where-Object { $null -ne $_ }) } else { [double[]]@() }
    $lat = if ($latCol) { [double[]]@($rows | ForEach-Object { & $num $_.$latCol } | Where-Object { $null -ne $_ }) } else { [double[]]@() }
    return [pscustomobject]@{ FrameTimes = $ft; Latency = $lat }
}

# Ejecutable de consola de la release (no el instalador de la app con overlay).
function Select-HLPresentMonAsset {
    param([Parameter(Mandatory)] $Assets)
    return @($Assets | Where-Object { $_.name -match '^PresentMon-[\d.]+-x64\.exe$' } | Select-Object -First 1)
}

# Argumentos de captura: 2.x usa "--opcion"; 1.x, "-opcion".
function Get-HLPresentMonArgs {
    param([Parameter(Mandatory)] [string] $Csv, [int] $Seconds, [ValidateSet(1, 2)] [int] $Syntax = 2)
    $p = if ($Syntax -eq 2) { '--' } else { '-' }
    $quiet = if ($Syntax -eq 2) { '--no_console_stats' } else { '-no_top' }
    return @("${p}process_name", 'cod.exe', "${p}output_file", "`"$Csv`"", "${p}timed", "$Seconds", "${p}terminate_after_timed",
        "${p}session_name", ('Hardline{0}' -f (Get-Random -Maximum 99999)), $quiet)
}

# --------------------------------------------------------------------------
# PresentMon
# --------------------------------------------------------------------------

function Get-HLPresentMon {
    $dir = Join-Path $Root 'tools\presentmon'
    $existing = Get-ChildItem $dir -Filter 'PresentMon-*-x64.exe' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($existing -and (Test-HLIntelSignature $existing.FullName)) { return $existing.FullName }

    Write-HLStep 'Descargando PresentMon (Intel, una sola vez)...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/GameTechDev/PresentMon/releases/latest' -UseBasicParsing -UserAgent 'Hardline' -ErrorAction Stop
    $asset = Select-HLPresentMonAsset -Assets $rel.assets
    if (-not $asset) { throw "La release $($rel.tag_name) de PresentMon no trae el ejecutable de consola esperado." }
    $sha = if ("$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $Matches[1] } else { '' }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out = Join-Path $dir $asset.name
    if (-not (Invoke-HLDownload -Urls @($asset.browser_download_url) -OutFile $out -Sha256 $sha -ExpectPE)) { throw 'No se pudo descargar PresentMon (o el SHA256 no coincide).' }
    if (-not (Test-HLIntelSignature $out)) {
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        throw 'PresentMon descargado sin firma válida de Intel: se ha borrado sin ejecutarlo.'
    }
    Write-HLOk "PresentMon $($rel.tag_name) (SHA256 y firma de Intel comprobados)"
    return $out
}

function Test-HLIntelSignature {
    param([string]$Path)
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        return ($sig.Status -eq 'Valid' -and "$($sig.SignerCertificate.Subject)" -match 'Intel')
    } catch { return $false }
}

function Invoke-HLPresentMonCapture {
    param([Parameter(Mandatory)] [string] $Exe, [Parameter(Mandatory)] [string] $Csv, [int] $Seconds)
    foreach ($syntax in @(2, 1)) {
        Remove-Item $Csv -Force -ErrorAction SilentlyContinue
        $p = Start-Process -FilePath $Exe -ArgumentList (Get-HLPresentMonArgs -Csv $Csv -Seconds $Seconds -Syntax $syntax) -WindowStyle Hidden -PassThru
        if (-not $p.WaitForExit(($Seconds + 30) * 1000)) { try { $p.Kill() } catch { Write-HLLog WARN 'PresentMon no terminó a tiempo' } }
        if ((Test-Path $Csv) -and (Get-Item $Csv).Length -gt 0) { return $true }
        Write-HLLog WARN "PresentMon (sintaxis $syntax) terminó con código $($p.ExitCode) sin CSV"
    }
    return $false
}

# --------------------------------------------------------------------------
# Flujo
# --------------------------------------------------------------------------

function Write-HLGameplayHtml {
    param($Stats, $Rows, [string]$Verdict, [string]$Title, [string]$Path)
    $enc = { param($s) [Net.WebUtility]::HtmlEncode("$s") }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hardline - partida</title>
<style>
:root{--bg:#0e1116;--fg:#e6eaf0;--mut:#8a93a3;--line:#2a313c;--good:#3fb950;--bad:#f85149;--acc:#ff5a1f}
@media (prefers-color-scheme: light){:root{--bg:#fff;--fg:#1b1f24;--mut:#57606a;--line:#d0d7de;--good:#1a7f37;--bad:#cf222e}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",system-ui,sans-serif;margin:0;padding:24px 16px;max-width:760px;margin-inline:auto}
h1{font-size:22px;margin:0 0 4px}h1 b{color:var(--acc)}p{color:var(--mut);margin:4px 0 16px}
table{border-collapse:collapse;width:100%;margin:12px 0}td,th{padding:8px 10px;border-bottom:1px solid var(--line);text-align:right}td:first-child,th:first-child{text-align:left}
th{color:var(--mut);font-weight:600}.g{color:var(--good);font-weight:600}.b{color:var(--bad);font-weight:600}.v{font-size:18px;font-weight:600;margin:16px 0}
</style></head><body><h1><b>HARDLINE</b> · medición de partida</h1>
"@)
    [void]$sb.Append("<p>$(& $enc $Title)</p>")
    if ($Rows) {
        [void]$sb.Append("<div class=`"v`">$(& $enc $Verdict)</div><table><tr><th></th><th>Antes</th><th>Ahora</th><th>Cambio</th></tr>")
        foreach ($r in $Rows) {
            $cls = if ($r.Better -gt 0) { 'g' } elseif ($r.Better -lt 0) { 'b' } else { '' }
            [void]$sb.Append("<tr><td>$(& $enc $r.Label)</td><td>$($r.Before)</td><td>$($r.After)</td><td class=`"$cls`">$(& $enc $r.Change)</td></tr>")
        }
        [void]$sb.Append('</table>')
    }
    [void]$sb.Append('<table><tr><th>Esta medición</th><th></th></tr>')
    foreach ($kv in @(@('FPS medios', $Stats.AvgFps), @('1% lows', $Stats.Low1Fps), @('0.1% lows', $Stats.Low01Fps), @('Frame típico (ms)', $Stats.MedianMs),
            @('Percentil 99 (ms)', $Stats.P99Ms), @('Tirones (%)', $Stats.StutterPct), @('Latencia de imagen (ms)', $(if ($null -ne $Stats.LatencyMs) { $Stats.LatencyMs } else { 'no disponible' })),
            @('Frames / segundos', "$($Stats.Frames) / $($Stats.Seconds)"))) {
        [void]$sb.Append("<tr><td>$(& $enc $kv[0])</td><td>$(& $enc $kv[1])</td></tr>")
    }
    [void]$sb.Append('</table><p>Para comparar, mide siempre en el mismo sitio (mismo modo y mapa, o el campo de tiro) y jugando igual. Una diferencia pequeña entre dos partidas es ruido, no un cambio.</p></body></html>')
    [IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-HLGameplayBench {
    param([int]$Seconds = 60, [int]$Delay = 20)
    Write-Host ''
    Write-Host 'HARDLINE - medir partida' -ForegroundColor Cyan
    if (-not (Test-HLAdmin)) { Write-HLWarn 'PresentMon necesita permisos de administrador para leer los eventos de Windows. Ábrelo desde la interfaz o con install.ps1 -GameplayBenchOnly.'; return $null }

    $exe = Get-HLPresentMon
    $reports = Join-Path $Root 'reports'
    if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports -Force | Out-Null }

    if (-not (Get-Process -Name 'cod' -ErrorAction SilentlyContinue)) {
        Write-Host 'Abre Warzone. La medición empieza sola cuando el juego esté abierto (espera hasta 10 min).' -ForegroundColor Yellow
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Get-Process -Name 'cod' -ErrorAction SilentlyContinue)) {
            if ($sw.Elapsed.TotalMinutes -ge 10) { Write-HLWarn 'Warzone no se abrió en 10 minutos.'; return $null }
            Start-Sleep -Seconds 2
        }
    }
    Write-Host "Warzone abierto. Entra en partida (o en el campo de tiro) y juega con normalidad." -ForegroundColor Cyan
    if ($Delay -gt 0) {
        Write-Host "La medición empieza en $Delay s y dura $Seconds s. Sonará un aviso al empezar y otro al terminar." -ForegroundColor DarkGray
        Start-Sleep -Seconds $Delay
    }
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { Write-HLLog DEBUG 'Sin sonido de aviso' }
    Write-Host "Midiendo $Seconds s..." -ForegroundColor DarkGray

    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $csv = Join-Path $env:TEMP "hardline_presentmon_$stamp.csv"
    if (-not (Invoke-HLPresentMonCapture -Exe $exe -Csv $csv -Seconds $Seconds)) { Write-HLErr 'PresentMon no generó datos. ¿Estaba Warzone en primer plano y en partida?'; return $null }
    try { [System.Media.SystemSounds]::Exclamation.Play() } catch { Write-HLLog DEBUG 'Sin sonido de aviso' }

    $data = ConvertFrom-HLPresentMonRows -Rows (Import-Csv $csv)
    Remove-Item $csv -Force -ErrorAction SilentlyContinue
    $stats = Get-HLFrameStats -FrameTimesMs $data.FrameTimes -LatencyMs $data.Latency
    if (-not $stats) { Write-HLErr 'Muy pocos frames capturados: ¿estaba el juego minimizado o en un menú cargando?'; return $null }

    # Con qué comparar: la medición anterior. Si desde entonces se aplicó Hardline, es antes/después.
    $prevFile = Get-ChildItem $reports -Filter 'gameplay_*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $lastApply = Get-ChildItem (Join-Path $Root 'backups') -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $rows = $null; $verdict = ''; $title = "Primera medición ($stamp). Aplica Hardline, reinicia y vuelve a medir en el mismo sitio para ver la diferencia."
    if ($prevFile) {
        $prev = Get-Content $prevFile.FullName -Raw | ConvertFrom-Json
        $rows = @(Compare-HLFrameStats -Before $prev.Stats -After $stats)
        $verdict = Get-HLGameplayVerdict -Rows $rows
        $title = if ($lastApply -and $lastApply.LastWriteTime -gt $prevFile.LastWriteTime) { "Antes ($($prev.Stamp)) y después de aplicar Hardline ($stamp)" } else { "Comparado con la medición anterior ($($prev.Stamp))" }
    }
    [pscustomobject]@{ Stamp = $stamp; Seconds = $Seconds; Stats = $stats } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $reports "gameplay_$stamp.json") -Encoding UTF8
    $html = Join-Path $reports "partida_$stamp.html"
    Write-HLGameplayHtml -Stats $stats -Rows $rows -Verdict $verdict -Title $title -Path $html

    Write-Host ''
    Write-Host $title -ForegroundColor Cyan
    if ($rows) {
        Write-Host ('    {0,-16} {1,9} {2,9} {3,12}' -f '', 'Antes', 'Ahora', 'Cambio') -ForegroundColor DarkGray
        foreach ($r in $rows) {
            $c = if ($r.Better -gt 0) { 'Green' } elseif ($r.Better -lt 0) { 'Red' } else { 'Gray' }
            Write-Host ('    {0,-16} {1,9} {2,9} {3,12}' -f $r.Label, $r.Before, $r.After, $r.Change) -ForegroundColor $c
        }
        Write-Host "    $verdict" -ForegroundColor Cyan
    } else {
        Write-Host ('    FPS medios {0}   1% lows {1}   0.1% lows {2}   tirones {3} %' -f $stats.AvgFps, $stats.Low1Fps, $stats.Low01Fps, $stats.StutterPct) -ForegroundColor Gray
    }
    Write-Host "Reporte: $html" -ForegroundColor DarkGray
    return [pscustomobject]@{ Stats = $stats; Rows = $rows; Verdict = $verdict; Html = $html }
}

if ($MyInvocation.InvocationName -ne '.') {
    $r = Invoke-HLGameplayBench -Seconds $Seconds -Delay $Delay
    if ($r -and $r.Html -and -not $NoOpen) { Start-Process -FilePath $r.Html -ErrorAction SilentlyContinue }
}

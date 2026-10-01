#Requires -Version 5.1
<#
    Hardline - reporte final en reports/YYYY-MM-DD_HH-MM.txt
#>

function Save-HLBenchmark {
    param($Bench)
    if (-not $Bench) { return }
    $path = Join-Path $HL.ReportDir ("bench_{0}_{1}.json" -f $HL.Stamp, $Bench.Phase.ToLowerInvariant())
    $Bench | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
}

function Get-HLLastBenchmark {
    param([ValidateSet('pre', 'post')] [string]$Phase = 'pre')
    $f = Get-ChildItem $HL.ReportDir -Filter "bench_*_$Phase.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    return (Get-Content $f.FullName -Raw | ConvertFrom-Json)
}

function Write-HLReport {
    param([Parameter(Mandatory)] $Hardware)

    $path = Join-Path $HL.ReportDir ("{0}.txt" -f $HL.Stamp)
    $sb = New-Object System.Text.StringBuilder
    function L([string]$s = '') { [void]$sb.AppendLine($s) }

    L "HARDLINE v$HLVersion - reporte"
    L ("Fecha: {0:yyyy-MM-dd HH:mm}   Equipo: {1}   Usuario: {2}" -f (Get-Date), $env:COMPUTERNAME, $env:USERNAME)
    if ($HL.DryRun) { L 'MODO DRYRUN: no se aplicó ningún cambio.' }
    L ('=' * 78)
    L ''
    L 'HARDWARE'
    L ('  CPU      {0} ({1}C/{2}T, {3})' -f $Hardware.CPU.Name, $Hardware.CPU.Cores, $Hardware.CPU.Threads, $Hardware.CPU.Family)
    if ($Hardware.GPU.Primary) { L ('  GPU      {0} {1}GB, driver {2}' -f $Hardware.GPU.Primary.Name, $Hardware.GPU.Primary.VRAMGB, $Hardware.GPU.Primary.DriverVersion) }
    L ('  RAM      {0}GB {1} @ {2} MT/s, EXPO/XMP {3}' -f $Hardware.RAM.TotalGB, $Hardware.RAM.Type, $Hardware.RAM.SpeedMTs, $Hardware.RAM.Profile)
    L ('  Disco    {0} {1}' -f $Hardware.Storage.SystemBus, $Hardware.Storage.SystemModel)
    L ('  Placa    {0} {1}, BIOS {2}' -f $Hardware.Board.Vendor, $Hardware.Board.Product, $Hardware.Board.BiosVersion)
    L ('  OS       {0} build {1}' -f $Hardware.OS.Caption, $Hardware.OS.Build)
    if ($Hardware.Game.Primary) { L ('  Warzone  {0}' -f $Hardware.Game.Primary) }
    L ''

    foreach ($status in @('Applied', 'Manual', 'Failed', 'Skipped', 'Info')) {
        $items = @($HL.Results | Where-Object { $_.Status -eq $status })
        if ($items.Count -eq 0) { continue }
        $title = switch ($status) {
            'Applied' { 'CAMBIOS APLICADOS' } 'Manual' { 'REQUIERE ACCIÓN MANUAL' } 'Failed' { 'FALLOS' }
            'Skipped' { 'OMITIDO (ya estaba bien o no aplica)' } 'Info' { 'INFORMACIÓN' }
        }
        L "$title ($($items.Count))"
        foreach ($i in $items) { L ('  [{0}] {1}: {2}' -f $i.Module, $i.Item, $i.Detail) }
        L ''
    }

    if ($HL.Manual.Count -gt 0) {
        L 'PASOS MANUALES (BIOS, Adrenalin, Windows, juego)'
        $n = 1
        foreach ($group in ($HL.Manual | Group-Object Area)) {
            L "  $($group.Name)"
            foreach ($m in $group.Group) {
                L ("   {0,2}. {1}" -f $n, $m.Text)
                if ($m.Link) { L ("       {0}" -f $m.Link) }
                $n++
            }
        }
        L ''
    }

    $cmp = @(Format-HLBenchComparison -Pre $HL.BenchPre -Post $HL.BenchPost)
    if ($cmp.Count -gt 0) {
        L 'BENCHMARK'
        foreach ($r in $cmp) { L "  $r" }
        L '  Nota: timer resolution, HAGS y servicios se aplican del todo tras reiniciar.'
        L '  Para medir después del reinicio: .\install.ps1 -BenchmarkOnly'
        L ''
    }

    if ($HL.NetDiag) {
        $d = $HL.NetDiag
        L 'DIAGNÓSTICO DE RED'
        if ($d.Gateway) { L ('  Router     {0} ms, jitter {1} ms, pérdida {2}%' -f $d.Gateway.AvgMs, $d.Gateway.JitterMs, $d.Gateway.LossPct) }
        if ($d.Internet) { L ('  Internet   {0} ms, jitter {1} ms, pérdida {2}%' -f $d.Internet.AvgMs, $d.Internet.JitterMs, $d.Internet.LossPct) }
        if ($d.Bufferbloat -and $d.Bufferbloat.Grade) { L ('  Bufferbloat nota {0} (+{1} ms bajo carga)' -f $d.Bufferbloat.Grade, $d.Bufferbloat.AddedMs) }
        if ($d.Mtu) { L "  MTU        $($d.Mtu)" }
        foreach ($x in $d.Findings) { L ('  [{0}] {1}: {2}' -f $x.Severity, $x.Title, $x.Text) }
        L ''
    }

    L 'REVERTIR'
    L "  Todo lo de esta sesión:   .\rollback.ps1 -Stamp $($HL.Stamp)"
    L '  Última sesión:            .\rollback.ps1'
    L '  Alternativa:              Panel de control > Recuperación > Restaurar sistema > punto "Hardline_*"'
    L "  Manifiesto de cambios:    $(Join-Path $HL.BackupDir 'manifest.json')"
    L "  Log detallado:            $($HL.LogFile)"
    if ($HL.NeedsReboot) { L ''; L 'REINICIO NECESARIO para completar los cambios.' }

    if (-not (Test-Path $HL.ReportDir)) { New-Item -ItemType Directory -Path $HL.ReportDir -Force | Out-Null }
    Set-Content -Path $path -Value $sb.ToString() -Encoding UTF8
    return $path
}

# --------------------------------------------------------------------------
# Reporte HTML (mismo contenido que el .txt, más legible y con enlaces)
# --------------------------------------------------------------------------

# Filas de la comparativa: métrica, antes, después y si "menos es mejor".
function Get-HLBenchRows {
    param($Pre, $Post)
    if (-not $Pre -or -not $Post) { return @() }
    $rows = @(
        [pscustomobject]@{ Metric = 'Resolución del timer (ms)'; Pre = $Pre.Timer.TimerResMs;  Post = $Post.Timer.TimerResMs;  Lower = $true }
        [pscustomobject]@{ Metric = 'Sleep(1) media (ms)';       Pre = $Pre.Timer.Sleep1AvgMs; Post = $Post.Timer.Sleep1AvgMs; Lower = $true }
        [pscustomobject]@{ Metric = 'Sleep(1) p99 (ms)';         Pre = $Pre.Timer.Sleep1P99Ms; Post = $Post.Timer.Sleep1P99Ms; Lower = $true }
    )
    if ($Pre.PingCf -and $Post.PingCf) {
        $rows += [pscustomobject]@{ Metric = 'Ping 1.1.1.1 (ms)';   Pre = $Pre.PingCf.AvgMs;    Post = $Post.PingCf.AvgMs;    Lower = $true }
        $rows += [pscustomobject]@{ Metric = 'Jitter 1.1.1.1 (ms)'; Pre = $Pre.PingCf.JitterMs; Post = $Post.PingCf.JitterMs; Lower = $true }
    }
    $rows += [pscustomobject]@{ Metric = 'DNS mediana (ms)'; Pre = $Pre.DnsMs; Post = $Post.DnsMs; Lower = $true }
    if ($Pre.Capture -and $Post.Capture -and $Pre.Capture.File -ne $Post.Capture.File) {
        $rows += [pscustomobject]@{ Metric = 'FPS medio'; Pre = $Pre.Capture.AvgFps;  Post = $Post.Capture.AvgFps;  Lower = $false }
        $rows += [pscustomobject]@{ Metric = '1% low';    Pre = $Pre.Capture.Low1Fps; Post = $Post.Capture.Low1Fps; Lower = $false }
    }
    return $rows
}

function Write-HLReportHtml {
    param([Parameter(Mandatory)] $Hardware)

    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode("$t") }
    $path = Join-Path $HL.ReportDir ("{0}.html" -f $HL.Stamp)
    $sb = New-Object System.Text.StringBuilder
    # Sin alias cortos: "h" ya es Get-History y los alias tienen prioridad sobre las funciones.
    function Add-HtmlLine([string]$s) { [void]$sb.AppendLine($s) }

    Add-HtmlLine '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    Add-HtmlLine ("<title>Hardline {0}</title>" -f (& $enc $HL.Stamp))
    Add-HtmlLine @'
<style>
:root{--bg:#0E1116;--panel:#161B22;--line:#2A313C;--fg:#E6EAF0;--mut:#8A93A3;--acc:#FF5A1F;--ok:#3FB950;--warn:#D29922;--bad:#F85149}
@media (prefers-color-scheme:light){:root{--bg:#F6F8FA;--panel:#FFFFFF;--line:#D0D7DE;--fg:#1F2328;--mut:#59636E;--ok:#1A7F37;--warn:#9A6700;--bad:#CF222E}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
main{max-width:980px;margin:0 auto;padding:28px 16px 60px}h1{margin:0;font-size:28px;letter-spacing:.04em}h1 span{color:var(--acc)}
h2{font-size:17px;margin:34px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--line)}
.sub{color:var(--mut);margin:4px 0 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-top:20px}
.tile{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 14px}.tile b{display:block;font-size:26px}.tile small{color:var(--mut)}
table{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--mut);font-weight:600;font-size:13px}
tr:last-child td{border-bottom:0}.tag{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;font-weight:600;border:1px solid currentColor}
.Applied{color:var(--ok)}.Manual{color:var(--warn)}.Failed{color:var(--bad)}.Skipped,.Info{color:var(--mut)}
ol{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 16px 12px 40px;margin:0}li{margin:6px 0}
a{color:var(--acc)}code{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:1px 6px;font-size:13px}
.better{color:var(--ok);font-weight:600}.worse{color:var(--bad);font-weight:600}.warnbox{border-left:3px solid var(--warn);padding:8px 12px;background:var(--panel);border-radius:6px}
</style></head><body><main>
'@
    Add-HtmlLine ("<h1>HARD<span>LINE</span></h1><p class=""sub"">v{0} · {1:yyyy-MM-dd HH:mm} · {2}{3}</p>" -f $HLVersion, (Get-Date), (& $enc $env:COMPUTERNAME), $(if ($HL.DryRun) { ' · <b>DRYRUN: no se aplicó nada</b>' } else { '' }))

    $count = { param($st) @($HL.Results | Where-Object { $_.Status -eq $st }).Count }
    Add-HtmlLine '<div class="grid">'
    Add-HtmlLine ("<div class=""tile""><b class=""Applied"">{0}</b><small>cambios aplicados</small></div>" -f (& $count 'Applied'))
    Add-HtmlLine ("<div class=""tile""><b class=""Manual"">{0}</b><small>pasos manuales</small></div>" -f $HL.Manual.Count)
    Add-HtmlLine ("<div class=""tile""><b class=""Failed"">{0}</b><small>fallos</small></div>" -f (& $count 'Failed'))
    Add-HtmlLine ("<div class=""tile""><b>{0}</b><small>omitidos (ya estaban bien)</small></div>" -f (& $count 'Skipped'))
    Add-HtmlLine '</div>'
    if ($HL.NeedsReboot -and -not $HL.DryRun) { Add-HtmlLine '<p class="warnbox"><b>Reinicio necesario</b> para completar HAGS, timer, servicios y drivers de audio.</p>' }

    Add-HtmlLine '<h2>Hardware</h2><table>'
    # Hashtable ordenado: un @(@(..), @(..)) se aplanaría en una lista de strings.
    $hwRows = [ordered]@{
        'CPU'     = ('{0} ({1}C/{2}T, {3})' -f $Hardware.CPU.Name, $Hardware.CPU.Cores, $Hardware.CPU.Threads, $Hardware.CPU.Family)
        'GPU'     = $(if ($Hardware.GPU.Primary) { '{0} {1} GB, driver {2}' -f $Hardware.GPU.Primary.Name, $Hardware.GPU.Primary.VRAMGB, $Hardware.GPU.Primary.DriverVersion } else { '-' })
        'RAM'     = ('{0} GB {1} @ {2} MT/s, EXPO/XMP {3}' -f $Hardware.RAM.TotalGB, $Hardware.RAM.Type, $Hardware.RAM.SpeedMTs, $Hardware.RAM.Profile)
        'Disco'   = ('{0} {1}' -f $Hardware.Storage.SystemBus, $Hardware.Storage.SystemModel)
        'Placa'   = ('{0} {1}, BIOS {2}' -f $Hardware.Board.Vendor, $Hardware.Board.Product, $Hardware.Board.BiosVersion)
        'Sistema' = ('{0} build {1}' -f $Hardware.OS.Caption, $Hardware.OS.Build)
    }
    foreach ($k in $hwRows.Keys) { Add-HtmlLine ("<tr><th>{0}</th><td>{1}</td></tr>" -f $k, (& $enc $hwRows[$k])) }
    Add-HtmlLine '</table>'

    $bench = @(Get-HLBenchRows -Pre $HL.BenchPre -Post $HL.BenchPost)
    if ($bench.Count -gt 0) {
        Add-HtmlLine '<h2>Antes / después</h2><table><tr><th>Métrica</th><th>Antes</th><th>Después</th><th>Cambio</th></tr>'
        foreach ($b in $bench) {
            $delta = ''; $cls = ''
            if ($null -ne $b.Pre -and $null -ne $b.Post -and [double]$b.Pre -ne 0) {
                $pct = ([double]$b.Post - [double]$b.Pre) / [double]$b.Pre * 100
                $good = if ($b.Lower) { $pct -lt -1 } else { $pct -gt 1 }
                $bad = if ($b.Lower) { $pct -gt 1 } else { $pct -lt -1 }
                $cls = if ($good) { 'better' } elseif ($bad) { 'worse' } else { '' }
                $delta = '{0:+0;-0;0}%' -f $pct
            }
            Add-HtmlLine ("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td class=""{3}"">{4}</td></tr>" -f (& $enc $b.Metric), $b.Pre, $b.Post, $cls, $delta)
        }
        Add-HtmlLine '</table><p class="sub">Timer, HAGS y servicios se aplican del todo tras reiniciar. Para medir de nuevo: <code>.\install.ps1 -BenchmarkOnly</code></p>'
    }

    if ($HL.NetDiag) {
        $d = $HL.NetDiag
        Add-HtmlLine '<h2>Diagnóstico de red</h2><div class="grid">'
        $tile = { param($val, $label, $cls) Add-HtmlLine ("<div class=""tile""><b class=""{2}"">{0}</b><small>{1}</small></div>" -f (& $enc $val), (& $enc $label), $cls) }
        if ($d.Internet) {
            & $tile ("{0}%" -f $d.Internet.LossPct) 'pérdida (Internet)' $(if ($d.Internet.LossPct -gt 0.5) { 'Failed' } else { 'Applied' })
            & $tile ("{0} ms" -f $d.Internet.JitterMs) 'jitter' $(if ($d.Internet.JitterMs -gt 8) { 'Failed' } elseif ($d.Internet.JitterMs -gt 4) { 'Manual' } else { 'Applied' })
        }
        if ($d.Bufferbloat -and $d.Bufferbloat.Grade) {
            $g = $d.Bufferbloat.Grade
            & $tile $g ("bufferbloat (+{0} ms)" -f $d.Bufferbloat.AddedMs) $(if ($g -in 'A+', 'A') { 'Applied' } elseif ($g -eq 'B') { 'Manual' } else { 'Failed' })
        }
        if ($d.Mtu) { & $tile $d.Mtu 'MTU' '' }
        Add-HtmlLine '</div><ol>'
        foreach ($x in $d.Findings) {
            $cls = switch ($x.Severity) { 'bad' { 'Failed' } 'warn' { 'Manual' } default { 'Applied' } }
            Add-HtmlLine ("<li><b class=""{0}"">{1}</b>: {2}</li>" -f $cls, (& $enc $x.Title), (& $enc $x.Text))
        }
        Add-HtmlLine '</ol><p class="sub">El registro de balas lo decide el servidor; lo que sí depende de ti es que tus paquetes lleguen completos, a tiempo y con ping estable.</p>'
    }

    if ($HL.Manual.Count -gt 0) {
        Add-HtmlLine '<h2>Pasos manuales</h2>'
        foreach ($group in ($HL.Manual | Group-Object Area)) {
            Add-HtmlLine ("<h3>{0}</h3><ol>" -f (& $enc $group.Name))
            foreach ($m in $group.Group) {
                $link = if ($m.Link) { (' <a href="{0}" target="_blank" rel="noopener">enlace</a>' -f (& $enc $m.Link)) } else { '' }
                Add-HtmlLine ("<li>{0}{1}</li>" -f (& $enc $m.Text), $link)
            }
            Add-HtmlLine '</ol>'
        }
    }

    Add-HtmlLine '<h2>Detalle</h2><table><tr><th>Estado</th><th>Módulo</th><th>Elemento</th><th>Detalle</th></tr>'
    $order = @{ Failed = 0; Manual = 1; Applied = 2; Info = 3; Skipped = 4 }
    foreach ($r in ($HL.Results | Sort-Object { $order[$_.Status] })) {
        $label = switch ($r.Status) { 'Applied' { 'aplicado' } 'Manual' { 'manual' } 'Failed' { 'fallo' } 'Skipped' { 'omitido' } default { 'info' } }
        Add-HtmlLine ("<tr><td><span class=""tag {0}"">{1}</span></td><td>{2}</td><td>{3}</td><td>{4}</td></tr>" -f $r.Status, $label, (& $enc $r.Module), (& $enc $r.Item), (& $enc $r.Detail))
    }
    Add-HtmlLine '</table>'

    Add-HtmlLine '<h2>Revertir</h2><ol>'
    Add-HtmlLine ("<li>Esta sesión: <code>.\rollback.ps1 -Stamp {0}</code></li>" -f (& $enc $HL.Stamp))
    Add-HtmlLine '<li>Última sesión: <code>.\rollback.ps1</code></li>'
    Add-HtmlLine '<li>Restaurar sistema &gt; punto <code>Hardline_*</code></li>'
    Add-HtmlLine ("<li>Manifiesto: <code>{0}</code></li>" -f (& $enc (Join-Path $HL.BackupDir 'manifest.json')))
    Add-HtmlLine '</ol></main></body></html>'

    if (-not (Test-Path $HL.ReportDir)) { New-Item -ItemType Directory -Path $HL.ReportDir -Force | Out-Null }
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    return $path
}

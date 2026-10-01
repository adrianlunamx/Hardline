#Requires -Version 5.1
<#
    Hardline - guía de pasos manuales.

    Lo que Hardline no puede hacer por ti (BIOS, panel de la GPU, menús del
    juego) se ordena por fases, de lo que más se nota y menos cuesta a lo
    avanzado, y se ofrece de tres formas:

      - reports\guia.html: página con casillas y progreso. Se abre al
        terminar y tiene acceso directo en Inicio > Hardline.
      - Interfaz: botón "Guía de pasos", un paso cada vez.
      - Consola: al terminar, pregunta si quieres que te guíe ahí mismo.

    Lo marcado como hecho se guarda en config\guide_state.json (interfaz y
    consola) y se refleja en la página la próxima vez que se genera; lo que
    marques en la página se recuerda en ese navegador.
#>

# Fase de cada área. Order decide el orden en la guía.
$script:HLGuidePhases = @(
    @{ Order = 1; Title = 'Ahora, en Windows';            Hint = 'Unos minutos. Lo que más se nota.';                       Areas = @('Pantalla', 'Overlays', 'Windows', 'Drivers') }
    @{ Order = 2; Title = 'En Warzone';                   Hint = 'Con el juego abierto, en los menús de ajustes.';           Areas = @('Warzone', 'Mando', 'Audio') }
    @{ Order = 3; Title = 'Panel de la tarjeta gráfica';  Hint = 'NVIDIA App / Panel de control, Adrenalin o Intel Graphics.'; Areas = @('GPU', 'NVIDIA', 'Adrenalin', 'Intel Arc', 'Latencia') }
    @{ Order = 4; Title = 'Red y router';                 Hint = 'Cable, router y lo que pasa fuera de tu PC.';              Areas = @('Red') }
    @{ Order = 5; Title = 'BIOS, al reiniciar';           Hint = 'Pulsa Supr o F2 al encender. Guarda con F10.';             Areas = @('BIOS', 'RAM') }
    @{ Order = 6; Title = 'Avanzado (opcional)';          Hint = 'Más rendimiento a cambio de probar estabilidad.';          Areas = @('Undervolt', 'Estabilidad') }
    @{ Order = 7; Title = 'Comprobar';                    Hint = 'Medir que lo anterior sirve de verdad.';                   Areas = @('Benchmark', 'Comprobar la diferencia') }
)

function Get-HLGuideStepId {
    param([string]$Area, [string]$Text)
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$Area|$Text"))
        return (-join ($b[0..5] | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

<#
    Pasos manuales ($HL.Manual: Area, Text, Link) ordenados por fase. Las áreas
    que no están en ninguna fase van a "Ahora, en Windows" para no perderse.
    Se quitan duplicados exactos.
#>
function Get-HLGuideSteps {
    param($Manual)
    $seen = @{}
    $i = 0
    # Sin @() en la cabecera: "foreach ($m in @($lista))" con una List[object]
    # (lo que es $HL.Manual) falla en PowerShell con "Los tipos de argumentos no coinciden".
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Manual) { foreach ($x in $Manual) { $items.Add($x) } }
    $steps = foreach ($m in $items) {
        if (-not $m -or -not $m.Text) { continue }
        $id = Get-HLGuideStepId -Area $m.Area -Text $m.Text
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $phase = $script:HLGuidePhases | Where-Object { $m.Area -in $_.Areas } | Select-Object -First 1
        if (-not $phase) { $phase = $script:HLGuidePhases[0] }
        $seq = $i
        $i += 1
        [pscustomobject]@{
            Id = $id; PhaseOrder = $phase.Order; Phase = $phase.Title; PhaseHint = $phase.Hint
            Area = "$($m.Area)"; Text = "$($m.Text)"; Link = "$($m.Link)"; Seq = $seq
        }
    }
    # Número de fase visible, correlativo aunque alguna fase no tenga pasos.
    $sorted = @($steps | Sort-Object PhaseOrder, Seq)
    $num = 0; $last = -1
    foreach ($s in $sorted) {
        if ($s.PhaseOrder -ne $last) { $num++; $last = $s.PhaseOrder }
        $s | Add-Member -NotePropertyName PhaseNum -NotePropertyValue $num
    }
    return $sorted
}

function Get-HLGuideState {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'config\guide_state.json'
    $done = @{}
    if (Test-Path $f) {
        try { foreach ($id in @((Get-Content $f -Raw | ConvertFrom-Json).Done)) { if ($id) { $done["$id"] = $true } } } catch { Write-HLLog WARN "guide_state.json ilegible: $($_.Exception.Message)" }
    }
    return $done
}

function Save-HLGuideState {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [hashtable] $Done)
    $dir = Join-Path $Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $ids = @($Done.Keys | Where-Object { $Done[$_] } | Sort-Object)
    [pscustomobject]@{ Done = $ids } | ConvertTo-Json | Set-Content (Join-Path $dir 'guide_state.json') -Encoding UTF8
}

function ConvertTo-HLGuideHtml {
    param([Parameter(Mandatory)] $Steps, [hashtable] $Done = @{}, [string] $Stamp = '', [string] $ReportName = '')
    $enc = { param($s) [Net.WebUtility]::HtmlEncode("$s") }
    $sb = New-Object System.Text.StringBuilder
    $add = { param($s) [void]$sb.Append($s) }
    & $add @"
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hardline - guía de pasos</title>
<style>
:root{--bg:#0e1116;--panel:#161b22;--fg:#e6eaf0;--mut:#8a93a3;--line:#2a313c;--acc:#ff5a1f;--ok:#3fb950}
@media (prefers-color-scheme: light){:root{--bg:#f6f8fa;--panel:#fff;--fg:#1b1f24;--mut:#57606a;--line:#d0d7de;--ok:#1a7f37}}
*{box-sizing:border-box}body{background:var(--bg);color:var(--fg);font:15px/1.55 "Segoe UI",system-ui,sans-serif;margin:0;padding:24px 16px 64px}
main{max-width:820px;margin:0 auto}h1{font-size:24px;margin:0}h1 b{color:var(--acc)}h2{font-size:17px;margin:28px 0 2px}
.sub{color:var(--mut);margin:4px 0 0}.hint{color:var(--mut);font-size:13px;margin:0 0 8px}
.bar{position:sticky;top:0;background:var(--bg);padding:14px 0 10px;z-index:1}.track{height:8px;background:var(--line);border-radius:4px;overflow:hidden}
.fill{height:100%;background:var(--ok);width:0;transition:width .2s}.count{font-size:13px;color:var(--mut);margin-top:6px;display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap}
.step{display:flex;gap:12px;align-items:flex-start;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px 14px;margin:8px 0}
.step input{width:20px;height:20px;margin:2px 0 0;flex:none;accent-color:var(--ok);cursor:pointer}
.step label{cursor:pointer;flex:1}.area{font-size:12px;color:var(--acc);font-weight:600;text-transform:uppercase;letter-spacing:.04em}
.step.done{opacity:.55}.step.done .txt{text-decoration:line-through}.step.next{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc)}
a{color:var(--acc)}button{background:none;border:1px solid var(--line);color:var(--mut);border-radius:6px;padding:3px 10px;cursor:pointer;font:inherit;font-size:13px}
.empty{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px}
@media print{.bar{position:static}.step{break-inside:avoid}button{display:none}}
</style></head><body><main>
<h1><b>HARDLINE</b> · guía de pasos</h1>
"@
    $sub = 'Lo que Hardline no puede hacer por ti, en orden: primero lo que más se nota y menos cuesta.'
    if ($Stamp) { $sub += " Sesión $Stamp." }
    & $add "<p class=`"sub`">$(& $enc $sub)"
    if ($ReportName) { & $add " <a href=`"$(& $enc $ReportName)`">Ver el reporte completo</a>" }
    & $add '</p>'

    $steps = @($Steps | Where-Object { $_ -and $_.Id -and $_.Text })
    if ($steps.Count -eq 0) {
        & $add '<p class="empty">No hay pasos manuales pendientes en esta sesión.</p></main></body></html>'
        return $sb.ToString()
    }
    & $add '<div class="bar"><div class="track"><div class="fill" id="fill"></div></div><div class="count"><span id="count"></span><button type="button" id="reset">Desmarcar todo</button></div></div>'
    $n = 0
    foreach ($g in ($steps | Group-Object PhaseOrder | Sort-Object { [int]$_.Name })) {
        $first = $g.Group[0]
        & $add "<h2>$($first.PhaseNum). $(& $enc $first.Phase)</h2><p class=`"hint`">$(& $enc $first.PhaseHint)</p>"
        foreach ($s in $g.Group) {
            $n++
            $chk = if ($Done.ContainsKey($s.Id)) { ' checked data-pre="1"' } else { '' }
            $link = if ($s.Link -match '^https?://') { " <a href=`"$(& $enc $s.Link)`" target=`"_blank`" rel=`"noopener`">Abrir enlace</a>" } else { '' }
            & $add "<div class=`"step`"><input type=`"checkbox`" id=`"s$($s.Id)`" data-id=`"$($s.Id)`"$chk><label for=`"s$($s.Id)`"><span class=`"area`">$(& $enc $s.Area)</span><br><span class=`"txt`">$(& $enc $s.Text)</span>$link</label></div>"
        }
    }
    & $add @'
<script>
(function(){
  var key='hardline-guide';var st={};
  try{st=JSON.parse(localStorage.getItem(key)||'{}')||{};}catch(e){st={};}
  var boxes=[].slice.call(document.querySelectorAll('.step input'));
  boxes.forEach(function(b){var id=b.dataset.id;if(Object.prototype.hasOwnProperty.call(st,id)){b.checked=!!st[id];}});
  function paint(){
    var done=0,next=null;
    boxes.forEach(function(b){var row=b.parentNode;row.classList.toggle('done',b.checked);row.classList.remove('next');if(b.checked){done++;}else if(!next){next=row;}});
    if(next){next.classList.add('next');}
    document.getElementById('fill').style.width=(100*done/boxes.length)+'%';
    document.getElementById('count').textContent=done+' de '+boxes.length+' hechos'+(next?'':' · todo listo');
  }
  function save(){try{localStorage.setItem(key,JSON.stringify(st));}catch(e){}}
  boxes.forEach(function(b){b.addEventListener('change',function(){st[b.dataset.id]=b.checked;save();paint();});});
  document.getElementById('reset').addEventListener('click',function(){boxes.forEach(function(b){b.checked=false;st[b.dataset.id]=false;});save();paint();});
  paint();
})();
</script></main></body></html>
'@
    return $sb.ToString()
}

<#
    Escribe reports\guia_<stamp>.html, reports\guia.html (siempre la última,
    para el acceso directo) y reports\guia.json (para la interfaz).
#>
function Save-HLGuide {
    param([Parameter(Mandatory)] [string] $Root, $Manual, [string] $Stamp = '', [string] $ReportName = '')
    $reports = Join-Path $Root 'reports'
    if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports -Force | Out-Null }
    $steps = Get-HLGuideSteps -Manual $Manual
    [pscustomobject]@{ Stamp = $Stamp; Report = $ReportName; Steps = $steps } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $reports 'guia.json') -Encoding UTF8
    return (Update-HLGuideHtml -Root $Root -Stamp $Stamp)
}

# Regenera las páginas a partir de guia.json y del estado guardado.
function Update-HLGuideHtml {
    param([Parameter(Mandatory)] [string] $Root, [string] $Stamp = '')
    $reports = Join-Path $Root 'reports'
    $data = Get-HLGuideData -Root $Root
    if (-not $data) { return $null }
    if (-not $Stamp) { $Stamp = "$($data.Stamp)" }
    $html = ConvertTo-HLGuideHtml -Steps $data.Steps -Done (Get-HLGuideState -Root $Root) -Stamp $Stamp -ReportName "$($data.Report)"
    $utf8 = New-Object Text.UTF8Encoding($false)
    $main = Join-Path $reports 'guia.html'
    [IO.File]::WriteAllText($main, $html, $utf8)
    if ($Stamp) { [IO.File]::WriteAllText((Join-Path $reports "guia_$Stamp.html"), $html, $utf8) }
    return $main
}

function Get-HLGuideData {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'reports\guia.json'
    if (-not (Test-Path $f)) { return $null }
    try {
        $d = Get-Content $f -Raw | ConvertFrom-Json
        return [pscustomobject]@{ Stamp = $d.Stamp; Report = $d.Report; Steps = @($d.Steps | Where-Object { $_ -and $_.Id -and $_.Text }) }
    } catch { return $null }
}

<#
    Guía en la consola: un paso cada vez. Enter = hecho, s = saltar,
    q = salir. Lo hecho se guarda y se refleja en guia.html.
#>
function Invoke-HLGuideConsole {
    param([Parameter(Mandatory)] [string] $Root)
    $data = Get-HLGuideData -Root $Root
    if (-not $data -or $data.Steps.Count -eq 0) { Write-HLInfo 'No hay pasos manuales pendientes.'; return }
    $done = Get-HLGuideState -Root $Root
    $pending = @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) })
    $total = $data.Steps.Count
    $phase = ''
    Write-Host ''
    Write-Host "Guía de pasos: $($pending.Count) pendientes de $total. Enter = hecho, s = saltar, q = salir." -ForegroundColor Cyan
    foreach ($s in $pending) {
        if ($s.Phase -ne $phase) {
            $phase = $s.Phase
            Write-Host ''
            Write-Host ("== {0}. {1} ==" -f $s.PhaseNum, $s.Phase) -ForegroundColor Cyan
            Write-Host "   $($s.PhaseHint)" -ForegroundColor DarkGray
        }
        $n = @($done.Keys | Where-Object { $done[$_] }).Count + 1
        Write-Host ''
        Write-Host ("[{0}/{1}] {2}" -f $n, $total, $s.Area) -ForegroundColor Yellow
        Write-Host "   $($s.Text)"
        if ($s.Link) { Write-Host "   $($s.Link)" -ForegroundColor DarkGray }
        $a = Read-Host '   Enter = hecho, s = saltar, q = salir'
        if ($a -match '^\s*q') { break }
        if ($a -match '^\s*s') { continue }
        $done[$s.Id] = $true
        Save-HLGuideState -Root $Root -Done $done
    }
    Update-HLGuideHtml -Root $Root | Out-Null
    $left = @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) }).Count
    if ($left -eq 0) { Write-HLOk 'Guía completa.' } else { Write-HLInfo "Quedan $left pasos. Retómalos desde Inicio > Hardline > Guía de pasos o el botón de la interfaz." }
}

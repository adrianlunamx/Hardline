#Requires -Version 5.1
<#
    Hardline - guía de pasos manuales.

    Lo que Hardline no puede hacer por ti (BIOS, panel de la GPU, menús del
    juego) se ordena por fases, de lo que más se nota y menos cuesta a lo
    avanzado, y se ofrece de tres formas:

      - Interfaz: botón "Guía de pasos", un paso cada vez. Si el paso es en
        un panel de Windows (Sonido, Mezclador, Pantalla...) o en un programa
        (Equalizer APO, HeSuVi, Voicemeeter), un botón lo abre directamente.
      - reports\guia.html: página con casillas y progreso. Acceso directo en
        Inicio > Hardline.
      - Consola: al terminar, pregunta si quieres que te guíe ahí mismo.

    Cada paso se enseña una sola vez: al terminar de aplicar solo aparecen
    los pasos nuevos (los que nunca has visto). Los que viste y no marcaste
    siguen en el botón "Guía de pasos" y en la página. Lo hecho y lo visto se
    guardan en config\guide_state.json.
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

<#
    Paneles y programas que la guía sabe abrir. Uri: enlace ms-settings (se
    abre también desde la página HTML). File/Args: comando. Exe: rutas
    candidatas. Script: .ps1 de Hardline. Hint: cómo llegar a mano, para la
    página HTML (no puede lanzar programas) o si el programa no está.
#>
$script:HLGuideActions = [ordered]@{
    'sound-playback'     = @{ Label = 'Abrir Sonido (Reproducción)'; File = 'control.exe'; Args = 'mmsys.cpl,,0'; Hint = 'Win + R, escribe mmsys.cpl y pulsa Enter.' }
    'sound-recording'    = @{ Label = 'Abrir Sonido (Grabación)'; File = 'control.exe'; Args = 'mmsys.cpl,,1'; Hint = 'Win + R, escribe mmsys.cpl, Enter y pestaña Grabación.' }
    'sound-settings'     = @{ Label = 'Abrir Configuración de sonido'; Uri = 'ms-settings:sound'; Hint = 'Configuración > Sistema > Sonido.' }
    'volume-mixer'       = @{ Label = 'Abrir Mezclador de volumen'; Uri = 'ms-settings:apps-volume'; Hint = 'Configuración > Sistema > Sonido > Mezclador de volumen.' }
    'display'            = @{ Label = 'Abrir Pantalla avanzada'; Uri = 'ms-settings:display-advanced'; Hint = 'Configuración > Sistema > Pantalla > Pantalla avanzada.' }
    'apps'               = @{ Label = 'Abrir Aplicaciones instaladas'; Uri = 'ms-settings:appsfeatures'; Hint = 'Configuración > Aplicaciones > Aplicaciones instaladas.' }
    'eqapo-configurator' = @{ Label = 'Abrir Configurator de Equalizer APO'; Exe = @('%ProgramFiles%\EqualizerAPO\Configurator.exe'); Hint = 'Inicio > Equalizer APO > Configurator.' }
    'hesuvi'             = @{ Label = 'Abrir HeSuVi'; Exe = @('%ProgramFiles%\EqualizerAPO\config\HeSuVi\HeSuVi.exe'); Hint = 'Carpeta de Equalizer APO > config > HeSuVi > HeSuVi.exe.' }
    'voicemeeter'        = @{ Label = 'Abrir Voicemeeter'; Voicemeeter = $true; Hint = 'Inicio > Voicemeeter.' }
    'eq-panel'           = @{ Label = 'Abrir Hardline EQ'; Script = 'src\gui\eq_panel.ps1'; Hidden = $true; Hint = 'Inicio > Hardline > Hardline EQ.' }
    'footstep-test'      = @{ Label = 'Abrir el test de pasos'; Script = 'src\audio\footstep_test.ps1'; Hint = 'Inicio > Hardline > Hardline test de pasos.' }
}

# Si el paso no dice qué abrir, se deduce del texto. Gana la primera regla que encaja.
$script:HLGuideActionRules = @(
    @{ Pattern = 'Mezclador de volumen'; Action = 'volume-mixer' }
    @{ Pattern = 'Configurator'; Action = 'eqapo-configurator' }
    @{ Pattern = '7\.1 Surround|Configurar > 7\.1|en 7\.1'; Action = 'sound-playback' }
    @{ Pattern = '^HeSuVi:'; Action = 'hesuvi' }
    @{ Pattern = 'Mejoras de audio|Audio espacial|Ecualización de sonoridad|desactiva sus efectos|Panel de sonido'; Action = 'sound-playback' }
    @{ Pattern = 'Sonido > (Entrada|Grabación)|micrófono predeterminado|desactiva(r)? (la|las|cada) entrada'; Action = 'sound-recording' }
    @{ Pattern = 'Sonido > Salida|Sonido > (Todos los dispositivos|Más opciones)'; Action = 'sound-settings' }
    @{ Pattern = 'Desinstala|Configuración > Aplicaciones'; Action = 'apps' }
    @{ Pattern = 'Frecuencia de actualización|Pantalla avanzada'; Action = 'display' }
    @{ Pattern = 'Hardline EQ|panel del EQ'; Action = 'eq-panel' }
    @{ Pattern = 'test de pasos'; Action = 'footstep-test' }
    @{ Pattern = 'Run on Windows Startup'; Action = 'voicemeeter' }
)

function Resolve-HLGuideAction {
    param([string]$Text, [string]$Action = '')
    if ($Action -and $script:HLGuideActions.Contains($Action)) { return $Action }
    foreach ($r in $script:HLGuideActionRules) { if ($Text -match $r.Pattern) { return $r.Action } }
    return ''
}

function Get-HLGuideActionSpec {
    param([string]$Action)
    if (-not $Action -or -not $script:HLGuideActions.Contains($Action)) { return $null }
    return $script:HLGuideActions[$Action]
}

<#
    Qué se ejecutaría para abrir $Action: @{ File; Args; Hidden } o $null si
    el programa no está instalado. Sin efectos: se prueba en tests.
#>
function Get-HLGuideActionCommand {
    param([Parameter(Mandatory)] [string] $Action, [Parameter(Mandatory)] [string] $Root)
    $a = Get-HLGuideActionSpec $Action
    if (-not $a) { return $null }
    if ($a.Uri) { return @{ File = $a.Uri; Args = ''; Hidden = $false } }
    if ($a.File) { return @{ File = $a.File; Args = $a.Args; Hidden = $false } }
    if ($a.Exe) {
        foreach ($p in $a.Exe) { $x = [Environment]::ExpandEnvironmentVariables($p); if (Test-Path -LiteralPath $x) { return @{ File = $x; Args = ''; Hidden = $false } } }
        return $null
    }
    if ($a.Voicemeeter) {
        . (Join-Path $Root 'src\audio\voicemeeter.ps1')
        $dir = Get-HLVoicemeeterDir
        $exe = if ($dir) { Get-HLVoicemeeterExe -Dir $dir } else { $null }
        if ($exe) { return @{ File = $exe; Args = ''; Hidden = $false } }
        return $null
    }
    if ($a.Script) {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $style = if ($a.Hidden) { '-WindowStyle Hidden' } else { '-NoExit' }
        return @{ File = $ps; Args = ('-NoProfile -ExecutionPolicy Bypass {0} -File "{1}" -Root "{2}"' -f $style, (Join-Path $Root $a.Script), $Root); Hidden = [bool]$a.Hidden }
    }
    return $null
}

# Abre el panel o programa. Devuelve $true si se lanzó; si no, el texto de ayuda.
function Invoke-HLGuideAction {
    param([Parameter(Mandatory)] [string] $Action, [Parameter(Mandatory)] [string] $Root)
    $cmd = Get-HLGuideActionCommand -Action $Action -Root $Root
    if (-not $cmd) { return "No está instalado. $((Get-HLGuideActionSpec $Action).Hint)" }
    try {
        $p = @{ FilePath = $cmd.File; ErrorAction = 'Stop' }
        if ($cmd.Args) { $p.ArgumentList = $cmd.Args }
        if ($cmd.Hidden) { $p.WindowStyle = 'Hidden' }
        Start-Process @p
        return $true
    } catch {
        Write-HLLog WARN "Guía: no se pudo abrir $Action ($($_.Exception.Message))"
        return "No se pudo abrir. $((Get-HLGuideActionSpec $Action).Hint)"
    }
}

<#
    Id estable del paso. Los números se ignoran: "el driver tiene 41 días" y
    "tiene 42 días" son el mismo paso y no deben volver a salir como nuevos.
#>
function Get-HLGuideStepId {
    param([string]$Area, [string]$Text, [switch]$Legacy)
    $t = if ($Legacy) { $Text } else { $Text -replace '\d+([.,]\d+)?', '#' }
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$Area|$t"))
        return (-join ($b[0..5] | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

<#
    Pasos manuales ($HL.Manual: Area, Text, Link, Action) ordenados por fase.
    Las áreas que no están en ninguna fase van a "Ahora, en Windows" para no
    perderse. Se quitan duplicados exactos. Si dos pasos distintos de la
    misma sesión solo se diferencian en un número (dos monitores), el
    segundo usa el id exacto para no compartir el "hecho".
#>
function Get-HLGuideSteps {
    param($Manual)
    $seen = @{}
    $ids = @{}
    $i = 0
    # Sin @() en la cabecera: "foreach ($m in @($lista))" con una List[object]
    # (lo que es $HL.Manual) falla en PowerShell con "Los tipos de argumentos no coinciden".
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Manual) { foreach ($x in $Manual) { $items.Add($x) } }
    $steps = foreach ($m in $items) {
        if (-not $m -or -not $m.Text) { continue }
        $exact = Get-HLGuideStepId -Area $m.Area -Text $m.Text -Legacy
        if ($seen.ContainsKey($exact)) { continue }
        $seen[$exact] = $true
        $id = Get-HLGuideStepId -Area $m.Area -Text $m.Text
        if ($ids.ContainsKey($id)) { $id = $exact }
        $ids[$id] = $true
        $phase = $script:HLGuidePhases | Where-Object { $m.Area -in $_.Areas } | Select-Object -First 1
        if (-not $phase) { $phase = $script:HLGuidePhases[0] }
        $seq = $i
        $i += 1
        $act = $m.PSObject.Properties['Action']
        [pscustomobject]@{
            Id = $id; LegacyId = $exact
            PhaseOrder = $phase.Order; Phase = $phase.Title; PhaseHint = $phase.Hint
            Area = "$($m.Area)"; Text = "$($m.Text)"; Link = "$($m.Link)"; Seq = $seq
            Action = (Resolve-HLGuideAction -Text "$($m.Text)" -Action $(if ($act) { "$($act.Value)" } else { '' }))
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

function Read-HLGuideStateFile {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'config\guide_state.json'
    $st = @{ Done = @{}; Seen = @{} }
    if (Test-Path $f) {
        try {
            $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($id in @($j.Done)) { if ($id) { $st.Done["$id"] = $true } }
            if ($j.PSObject.Properties['Seen']) { foreach ($id in @($j.Seen)) { if ($id) { $st.Seen["$id"] = $true } } }
        } catch { Write-HLLog WARN "guide_state.json ilegible: $($_.Exception.Message)" }
    }
    return $st
}

<#
    Pasos hechos. Con -Steps, lo marcado antes de la 1.12.0 (ids que
    dependían de los números del texto) cuenta para el id nuevo.
#>
function Get-HLGuideState {
    param([Parameter(Mandatory)] [string] $Root, $Steps = $null)
    $done = (Read-HLGuideStateFile -Root $Root).Done
    foreach ($s in @($Steps)) {
        if ($s -and $s.PSObject.Properties['LegacyId'] -and $s.LegacyId -and $done.ContainsKey("$($s.LegacyId)")) { $done["$($s.Id)"] = $true }
    }
    return $done
}

# Pasos que ya se enseñaron alguna vez (interfaz o consola).
function Get-HLGuideSeen {
    param([Parameter(Mandatory)] [string] $Root, $Steps = $null)
    $seen = (Read-HLGuideStateFile -Root $Root).Seen
    foreach ($s in @($Steps)) {
        if ($s -and $s.PSObject.Properties['LegacyId'] -and $s.LegacyId -and $seen.ContainsKey("$($s.LegacyId)")) { $seen["$($s.Id)"] = $true }
    }
    return $seen
}

# Sin -Seen se conserva lo visto que ya hubiera en el archivo.
function Save-HLGuideState {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [hashtable] $Done, [hashtable] $Seen = $null)
    $dir = Join-Path $Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($null -eq $Seen) { $Seen = (Read-HLGuideStateFile -Root $Root).Seen }
    $ids = @($Done.Keys | Where-Object { $Done[$_] } | Sort-Object)
    $seenIds = @($Seen.Keys | Where-Object { $Seen[$_] } | Sort-Object)
    $json = [pscustomobject]@{ Done = $ids; Seen = $seenIds } | ConvertTo-Json
    # Sin BOM: lo leen también herramientas que no lo esperan.
    [IO.File]::WriteAllText((Join-Path $dir 'guide_state.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Add-HLGuideSeen {
    param([Parameter(Mandatory)] [string] $Root, [string[]] $Ids)
    $st = Read-HLGuideStateFile -Root $Root
    foreach ($id in @($Ids | Where-Object { $_ })) { $st.Seen[$id] = $true }
    Save-HLGuideState -Root $Root -Done $st.Done -Seen $st.Seen
}

# Pendientes que nunca se han enseñado: lo único que aparece solo al terminar de aplicar.
function Get-HLGuideNewSteps {
    param([Parameter(Mandatory)] [string] $Root)
    $data = Get-HLGuideData -Root $Root
    if (-not $data) { return @() }
    $done = Get-HLGuideState -Root $Root -Steps $data.Steps
    $seen = Get-HLGuideSeen -Root $Root -Steps $data.Steps
    return @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) -and -not $seen.ContainsKey($_.Id) })
}

function ConvertTo-HLGuideHtml {
    param([Parameter(Mandatory)] $Steps, [hashtable] $Done = @{}, [string] $Stamp = '', [string] $ReportName = '', [hashtable] $Seen = $null)
    $enc = { param($s) [Net.WebUtility]::HtmlEncode("$s") }
    $sb = New-Object System.Text.StringBuilder
    $add = { param($s) [void]$sb.Append($s) }
    & $add @"
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hardline - guía de pasos</title>
<style>
:root{--bg:#0b0d12;--panel:#12161e;--panel2:#171c26;--fg:#eef1f6;--mut:#8b94a5;--line:#232a36;--acc:#ff5a1f;--acc2:#ff8a3d;--ok:#3fb950}
@media (prefers-color-scheme: light){:root{--bg:#f5f6f8;--panel:#fff;--panel2:#f7f8fa;--fg:#14171c;--mut:#5b6472;--line:#dde1e7;--ok:#1a7f37}}
*{box-sizing:border-box}body{background:var(--bg);color:var(--fg);font:15px/1.55 "Segoe UI Variable Text","Segoe UI",system-ui,sans-serif;margin:0;padding:28px 16px 72px}
main{max-width:820px;margin:0 auto}h1{font-size:26px;margin:0;letter-spacing:-.01em}h1 b{background:linear-gradient(90deg,var(--acc),var(--acc2));-webkit-background-clip:text;background-clip:text;color:transparent}
h2{font-size:17px;margin:32px 0 2px}.sub{color:var(--mut);margin:6px 0 0}.hint{color:var(--mut);font-size:13px;margin:0 0 10px}
.bar{position:sticky;top:0;background:var(--bg);padding:16px 0 12px;z-index:1}.track{height:6px;background:var(--line);border-radius:3px;overflow:hidden}
.fill{height:100%;background:linear-gradient(90deg,var(--acc),var(--acc2));width:0;transition:width .25s}.count{font-size:13px;color:var(--mut);margin-top:8px;display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap}
.step{display:flex;gap:14px;align-items:flex-start;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:10px 0;transition:border-color .15s}
.step input{width:20px;height:20px;margin:2px 0 0;flex:none;accent-color:var(--ok);cursor:pointer}
.step label{cursor:pointer;flex:1}.area{font-size:11px;color:var(--acc);font-weight:700;text-transform:uppercase;letter-spacing:.06em}
.new{font-size:10px;font-weight:700;letter-spacing:.06em;background:var(--acc);color:#fff;border-radius:999px;padding:1px 7px;margin-left:6px;vertical-align:1px}
.how{display:block;margin-top:8px;font-size:13px;color:var(--mut)}.how a,.lnk{display:inline-block;margin-top:8px;font-size:13px;font-weight:600;color:var(--acc);text-decoration:none;border:1px solid var(--line);border-radius:8px;padding:4px 10px;background:var(--panel2)}
.how a:hover,.lnk:hover{border-color:var(--acc)}
.step.done{opacity:.5}.step.done .txt{text-decoration:line-through}.step.next{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc)}
a{color:var(--acc)}button{background:none;border:1px solid var(--line);color:var(--mut);border-radius:8px;padding:3px 10px;cursor:pointer;font:inherit;font-size:13px}
.empty{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px}
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
    foreach ($g in ($steps | Group-Object PhaseOrder | Sort-Object { [int]$_.Name })) {
        $first = $g.Group[0]
        & $add "<h2>$($first.PhaseNum). $(& $enc $first.Phase)</h2><p class=`"hint`">$(& $enc $first.PhaseHint)</p>"
        foreach ($s in $g.Group) {
            $chk = if ($Done.ContainsKey($s.Id)) { ' checked data-pre="1"' } else { '' }
            $isNew = $null -ne $Seen -and -not $Seen.ContainsKey($s.Id) -and -not $Done.ContainsKey($s.Id)
            $badge = if ($isNew) { '<span class="new">NUEVO</span>' } else { '' }
            $how = ''
            $act = if ($s.PSObject.Properties['Action']) { Get-HLGuideActionSpec "$($s.Action)" } else { $null }
            if ($act) {
                # La página no puede lanzar programas: enlace solo para ms-settings, si no, cómo llegar.
                $how = if ($act.Uri) { "<span class=`"how`"><a href=`"$(& $enc $act.Uri)`">$(& $enc $act.Label)</a></span>" } else { "<span class=`"how`">Cómo abrirlo: $(& $enc $act.Hint)</span>" }
            }
            $link = if ($s.Link -match '^https?://') { " <a class=`"lnk`" href=`"$(& $enc $s.Link)`" target=`"_blank`" rel=`"noopener`">Abrir enlace</a>" } else { '' }
            & $add "<div class=`"step`"><input type=`"checkbox`" id=`"s$($s.Id)`" data-id=`"$($s.Id)`"$chk><label for=`"s$($s.Id)`"><span class=`"area`">$(& $enc $s.Area)</span>$badge<br><span class=`"txt`">$(& $enc $s.Text)</span>$how$link</label></div>"
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
    $html = ConvertTo-HLGuideHtml -Steps $data.Steps -Done (Get-HLGuideState -Root $Root -Steps $data.Steps) -Seen (Get-HLGuideSeen -Root $Root -Steps $data.Steps) -Stamp $Stamp -ReportName "$($data.Report)"
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
        $d = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $steps = @($d.Steps | Where-Object { $_ -and $_.Id -and $_.Text })
        # guia.json de versiones anteriores: sin acción deducida.
        foreach ($s in $steps) {
            if (-not $s.PSObject.Properties['Action']) { $s | Add-Member -NotePropertyName Action -NotePropertyValue (Resolve-HLGuideAction -Text $s.Text) }
        }
        return [pscustomobject]@{ Stamp = $d.Stamp; Report = $d.Report; Steps = $steps }
    } catch { return $null }
}

<#
    Guía en la consola: un paso cada vez. Enter = hecho, a = abrir el panel,
    s = saltar, q = salir. Con -OnlyNew solo los que nunca se han enseñado
    (lo que se ofrece al terminar de aplicar). Lo hecho y lo visto se guarda
    y se refleja en guia.html.
#>
function Invoke-HLGuideConsole {
    param([Parameter(Mandatory)] [string] $Root, [switch] $OnlyNew)
    $data = Get-HLGuideData -Root $Root
    if (-not $data -or $data.Steps.Count -eq 0) { Write-HLInfo 'No hay pasos manuales pendientes.'; return }
    $done = Get-HLGuideState -Root $Root -Steps $data.Steps
    $seen = Get-HLGuideSeen -Root $Root -Steps $data.Steps
    $pending = @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) -and (-not $OnlyNew -or -not $seen.ContainsKey($_.Id)) })
    if ($pending.Count -eq 0) { Write-HLInfo 'No hay pasos nuevos.'; return }
    $total = $pending.Count
    $phase = ''
    $n = 0
    Write-Host ''
    Write-Host "Guía de pasos: $total $(if ($OnlyNew) { 'nuevos' } else { 'pendientes' }). Enter = hecho, a = abrir el panel, s = saltar, q = salir." -ForegroundColor Cyan
    foreach ($s in $pending) {
        $n++
        $seen[$s.Id] = $true
        if ($s.Phase -ne $phase) {
            $phase = $s.Phase
            Write-Host ''
            Write-Host ("== {0}. {1} ==" -f $s.PhaseNum, $s.Phase) -ForegroundColor Cyan
            Write-Host "   $($s.PhaseHint)" -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host ("[{0}/{1}] {2}" -f $n, $total, $s.Area) -ForegroundColor Yellow
        Write-Host "   $($s.Text)"
        $act = Get-HLGuideActionSpec "$($s.Action)"
        if ($act) { Write-Host "   a = $($act.Label)" -ForegroundColor DarkCyan }
        if ($s.Link) { Write-Host "   $($s.Link)" -ForegroundColor DarkGray }
        $quit = $false
        while ($true) {
            $a = Read-Host '   Enter = hecho, a = abrir, s = saltar, q = salir'
            if ($a -match '^\s*a' -and $act) {
                $r = Invoke-HLGuideAction -Action $s.Action -Root $Root
                if ($r -ne $true) { Write-HLWarn $r }
                continue
            }
            if ($a -match '^\s*q') { $quit = $true; break }
            if ($a -notmatch '^\s*s') { $done[$s.Id] = $true }
            break
        }
        Save-HLGuideState -Root $Root -Done $done -Seen $seen
        if ($quit) { break }
    }
    Update-HLGuideHtml -Root $Root | Out-Null
    $left = @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) }).Count
    if ($left -eq 0) { Write-HLOk 'Guía completa.' } else { Write-HLInfo "Quedan $left pasos. Retómalos desde Inicio > Hardline > Guía de pasos o el botón de la interfaz." }
}

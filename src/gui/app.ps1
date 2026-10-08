#Requires -Version 5.1
<#
    Hardline - interfaz gráfica (WPF).

    La ventana no aplica nada por sí misma: construye los parámetros a partir
    de lo marcado y lanza install.ps1 / rollback.ps1 / footstep_test.ps1 en un
    proceso aparte, sin consola. Así la GUI y el modo consola ejecutan
    exactamente el mismo código, con el mismo manifiesto y el mismo rollback.

    La salida del proceso va a un archivo temporal que un DispatcherTimer lee
    cada 250 ms (los manejadores de eventos .NET en otros hilos no tienen
    runspace de PowerShell; el timer corre en el hilo de la interfaz). Las
    líneas "[*] ..." de esa salida son las fases: se muestran arriba del
    registro mientras se aplica.

    Se lanza con:  install.ps1 -Gui   o el acceso directo Inicio > Hardline.
#>
param([Parameter(Mandatory)] [string] $Root)

. (Join-Path $Root 'src\core\common.ps1')
. (Join-Path $Root 'src\core\guide.ps1')
. (Join-Path $Root 'src\core\news.ps1')
. (Join-Path $Root 'src\core\detector.ps1')
. (Join-Path $Root 'src\gui\theme.ps1')
. (Join-Path $Root 'src\gui\news_ui.ps1')

# --------------------------------------------------------------------------
# Construcción de argumentos (sin dependencias de WPF: se prueba en tests)
# --------------------------------------------------------------------------

<#
    $State: hashtable con las casillas y opciones de la ventana.
    Devuelve la lista de argumentos para install.ps1.
#>
function ConvertTo-HLGuiArguments {
    param([Parameter(Mandatory)] [hashtable] $State, [switch] $DryRun)
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-Unattended')
    if ($DryRun) { $a.Add('-DryRun') }
    $map = [ordered]@{ Windows = '-SkipWindows'; Display = '-SkipDisplay'; Platforms = '-SkipPlatforms'; Latency = '-SkipLatency'; Network = '-SkipNetwork'
        NetDiag = '-SkipNetDiag'; Game = '-SkipGame'; Controller = '-SkipController'; Audio = '-SkipAudio'; Bench = '-SkipBenchmark' }
    foreach ($k in $map.Keys) { if (-not $State[$k]) { $a.Add($map[$k]) } }
    $a.Add('-GameSession'); $a.Add($(if ($State.Session) { 'Yes' } else { 'No' }))
    if ($State.Experimental) { $a.Add('-Experimental') }
    if ($State.Platform) { $a.Add('-Platform'); $a.Add($State.Platform) }
    if ($State.DisableOthers) { $a.Add('-DisableOtherPlatforms') }
    if ($State.Audio) {
        if ($State.Headset) { $a.Add('-Headset'); $a.Add($State.Headset) }
        if ($State.AudioMode) { $a.Add('-AudioMode'); $a.Add($State.AudioMode) }
        if ($State.Intensity) { $a.Add('-EqIntensity'); $a.Add($State.Intensity) }
        if ($State.CleanAudio) { $a.Add('-CleanAudio') }
        if ($State.HeSuVi) { $a.Add('-HeSuVi') }
        if ($State.OutputDevice) { $a.Add('-AudioDevice'); $a.Add($State.OutputDevice) }
        if ($State.Dynamics) { $a.Add('-AudioDynamics'); $a.Add($State.Dynamics) }
    }
    return $a.ToArray()
}

# Versión instalada en disco (puede ser más nueva que la de esta ventana tras actualizar).
function Get-HLInstalledVersion {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'src\core\common.ps1'
    if (-not (Test-Path $f)) { return '' }
    $m = Select-String -Path $f -Pattern "HLVersion = '([^']+)'" | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return ''
}

# ¿La release publicada es más nueva que la instalada? Sin dato = no.
function Test-HLUpdateAvailable {
    param([string] $Latest, [string] $Current)
    if (-not $Latest -or $Latest -notmatch '^v?\d+(\.\d+)*$') { return $false }
    try { return ((Compare-HLVersion $Latest $Current) -gt 0) } catch { return $false }
}

# Comilla cada argumento para una línea -Command de powershell.exe.
function ConvertTo-HLCommandLine {
    param([Parameter(Mandatory)] [string] $Script, [string[]] $Arguments)
    $parts = foreach ($x in $Arguments) {
        if ($x -match '^-[A-Za-z]+$') { $x } else { "'" + ($x -replace "'", "''") + "'" }
    }
    return ("[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$ProgressPreference = 'SilentlyContinue'; & '{0}' {1}" -f ($Script -replace "'", "''"), ($parts -join ' ')).TrimEnd()
}

# --------------------------------------------------------------------------
# Guía de pasos: un paso cada vez
# --------------------------------------------------------------------------

# Índice del siguiente paso no hecho a partir de $From (dando la vuelta); -1 si no queda ninguno.
function Get-HLNextPendingIndex {
    param([Parameter(Mandatory)] $Steps, [Parameter(Mandatory)] [hashtable] $Done, [int] $From = -1)
    $n = @($Steps).Count
    for ($k = 1; $k -le $n; $k++) {
        $j = ($From + $k) % $n
        if (-not $Done.ContainsKey($Steps[$j].Id)) { return $j }
    }
    return -1
}

<#
    Pasos que enseña el asistente: todos, o con -OnlyNew solo los pendientes
    que nunca se han enseñado (lo que se abre solo al terminar de aplicar).
#>
function Select-HLGuideSteps {
    param([Parameter(Mandatory)] $Steps, [Parameter(Mandatory)] [hashtable] $Done, [Parameter(Mandatory)] [hashtable] $Seen, [switch] $OnlyNew)
    if (-not $OnlyNew) { return @($Steps) }
    return @($Steps | Where-Object { -not $Done.ContainsKey($_.Id) -and -not $Seen.ContainsKey($_.Id) })
}

function Show-HLGuideWindow {
    param($Owner, [switch] $OnlyNew)
    $data = Get-HLGuideData -Root $Root
    if (-not $data -or $data.Steps.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No hay pasos manuales todavía. Pulsa Aplicar y al terminar aparecerán aquí.', 'Hardline') | Out-Null
        return
    }
    $done = Get-HLGuideState -Root $Root -Steps $data.Steps
    $seen = Get-HLGuideSeen -Root $Root -Steps $data.Steps
    $steps = @(Select-HLGuideSteps -Steps $data.Steps -Done $done -Seen $seen -OnlyNew:$OnlyNew)
    if ($steps.Count -eq 0) { return }
    # "NUEVO" se calcula al abrir: lo que se ve en esta ventana deja de serlo la próxima vez.
    $isNew = @{}
    foreach ($s in $steps) { if (-not $seen.ContainsKey($s.Id) -and -not $done.ContainsKey($s.Id)) { $isNew[$s.Id] = $true } }

    $r = New-HLWindow -Path (Join-Path $PSScriptRoot 'guide.xaml') -Root $Root
    $w = $r.Window
    $g = $r.Ui
    if ($Owner) { $w.Owner = $Owner } else { $w.WindowStartupLocation = 'CenterScreen' }
    $g.gMode.Text = if ($OnlyNew) { 'PASOS NUEVOS' } else { 'GUÍA DE PASOS' }
    $pos = @{ I = [Math]::Max(0, (Get-HLNextPendingIndex -Steps $steps -Done $done)) }
    $save = { Save-HLGuideState -Root $Root -Done $done -Seen $seen }

    $render = {
        $s = $steps[$pos.I]
        $seen[$s.Id] = $true
        $isDone = $done.ContainsKey($s.Id)
        $count = @($steps | Where-Object { $done.ContainsKey($_.Id) }).Count
        $g.gPhase.Text = '{0}. {1}' -f $s.PhaseNum, $s.Phase
        $g.gHint.Text = $s.PhaseHint
        $g.gCount.Text = 'Paso {0} de {1}  ·  {2} hechos' -f ($pos.I + 1), $steps.Count, $count
        $g.gProgress.Value = $count / $steps.Count
        $g.gArea.Text = "$($s.Area)".ToUpperInvariant()
        $g.gNew.Visibility = if ($isNew.ContainsKey($s.Id)) { 'Visible' } else { 'Collapsed' }
        $g.gText.Text = $s.Text
        $g.gState.Text = if ($isDone) { 'Hecho' } else { '' }
        $g.gDone.Content = if ($isDone) { 'Desmarcar' } else { 'Hecho' }
        $spec = Get-HLGuideActionSpec "$($s.Action)"
        $g.gAction.Visibility = if ($spec) { 'Visible' } else { 'Collapsed' }
        if ($spec) { $g.gActionText.Text = $spec.Label }
        $g.gActionHint.Text = ''
        $g.gLink.Visibility = if ("$($s.Link)" -match '^https?://') { 'Visible' } else { 'Collapsed' }
        $g.gPrev.IsEnabled = $pos.I -gt 0
        $g.gSkip.IsEnabled = $pos.I -lt $steps.Count - 1
    }

    $g.gDone.Add_Click({
            $s = $steps[$pos.I]
            if ($done.ContainsKey($s.Id)) { $done.Remove($s.Id); & $save; & $render; return }
            $done[$s.Id] = $true
            & $save
            $next = Get-HLNextPendingIndex -Steps $steps -Done $done -From $pos.I
            if ($next -lt 0) {
                & $render
                $msg = if ($OnlyNew) { 'Pasos nuevos hechos. Los que saltaste siguen en «Guía de pasos».' } else { 'Todos los pasos hechos. Ahora usa «Medir partida» para comprobar la diferencia.' }
                [System.Windows.MessageBox]::Show($msg, 'Hardline') | Out-Null
                $w.Close()
                return
            }
            $pos.I = $next
            & $render
        })
    $g.gAction.Add_Click({
            $res = Invoke-HLGuideAction -Action "$($steps[$pos.I].Action)" -Root $Root
            $g.gActionHint.Text = if ($res -eq $true) { 'Abierto. Cuando termines, vuelve aquí y pulsa Hecho.' } else { "$res" }
        })
    $g.gSkip.Add_Click({ if ($pos.I -lt $steps.Count - 1) { $pos.I++; & $render } })
    $g.gPrev.Add_Click({ if ($pos.I -gt 0) { $pos.I--; & $render } })
    $g.gLink.Add_Click({ $l = "$($steps[$pos.I].Link)"; if ($l -match '^https?://') { Start-Process $l } })
    $g.gList.Add_Click({ & $save; $h = Update-HLGuideHtml -Root $Root; if ($h) { Start-Process -FilePath $h } })
    $w.Add_Closed({ & $save; Update-HLGuideHtml -Root $Root | Out-Null })
    & $render
    [void]$w.ShowDialog()
}

# Texto de la tarjeta "Guía de pasos" de la ventana principal.
function Get-HLGuideSummaryText {
    param([Parameter(Mandatory)] [string] $Root)
    $data = Get-HLGuideData -Root $Root
    if (-not $data -or $data.Steps.Count -eq 0) { return 'Aún no hay pasos: aparecen al aplicar.' }
    $done = Get-HLGuideState -Root $Root -Steps $data.Steps
    $seen = Get-HLGuideSeen -Root $Root -Steps $data.Steps
    $pending = @($data.Steps | Where-Object { -not $done.ContainsKey($_.Id) })
    if ($pending.Count -eq 0) { return "Todo hecho ($($data.Steps.Count) pasos)." }
    $new = @($pending | Where-Object { -not $seen.ContainsKey($_.Id) }).Count
    if ($new -gt 0) { return "$($pending.Count) pendientes · $new nuevos" }
    return "$($pending.Count) pendientes de $($data.Steps.Count)"
}

# --------------------------------------------------------------------------
# Ventana
# --------------------------------------------------------------------------

# Fase a partir de una línea de salida "[*] Texto..." de install.ps1; $null si no lo es.
function Get-HLPhaseFromLine {
    param([string] $Line)
    if ($Line -match '^\[\*\]\s+(.+?)\.*\s*$') { return $Matches[1] }
    return $null
}

function Show-HLGui {
    $r = New-HLWindow -Path (Join-Path $PSScriptRoot 'main.xaml') -Root $Root
    $window = $r.Window
    $ui = $r.Ui
    $ui.txtVersion.Text = "v$HLVersion"
    $ui.txtVersion.ToolTip = $Root

    $refreshGuide = { try { $ui.txtGuideSummary.Text = Get-HLGuideSummaryText -Root $Root } catch { Write-HLLog DEBUG 'Sin resumen de la guía' } }
    $refreshNews = {
        $unseen = @(Get-HLAnnouncements -Root $Root | Where-Object { $_.Kind -eq 'release' })
        $ui.dotNews.Visibility = if ($unseen.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    }
    & $refreshGuide
    & $refreshNews

    # Salidas para A1: la elegida aquí manda; "Automática" nunca coge el HDMI/DP del monitor si hay otra.
    $autoItem = New-Object System.Windows.Controls.ComboBoxItem
    $autoItem.Content = 'Automática (headset detectado o salida de Windows)'; $autoItem.Tag = ''
    [void]$ui.cmbOutput.Items.Add($autoItem)
    try {
        foreach ($ep in @(Get-HLAudioEndpoints | Where-Object { $_.Render -and $_.Name -notmatch 'CABLE|Voicemeeter|VB-Audio' } | Sort-Object Name -Unique)) {
            $it = New-Object System.Windows.Controls.ComboBoxItem
            $it.Content = $ep.Name; $it.Tag = $ep.Name
            [void]$ui.cmbOutput.Items.Add($it)
        }
    } catch { Write-HLLog DEBUG 'Sin lista de salidas de audio' }
    $ui.cmbOutput.SelectedIndex = 0

    $script:job = $null      # @{ Process; LogPath; Position; OnExit }
    $buttons = @('btnApply', 'btnDryRun', 'btnRollback', 'btnNetDiag', 'btnBench', 'btnFootstep', 'btnControllerTest', 'btnGameplay')

    $setBusy = {
        param([bool]$busy, [string]$status)
        foreach ($b in $buttons) { $ui[$b].IsEnabled = -not $busy }
        $ui.prgBusy.IsIndeterminate = $busy
        if (-not $busy) { $ui.prgBusy.Value = 0 }
        if ($busy) { $ui.txtPhase.Text = $status; $ui.pnlStats.Visibility = 'Collapsed' }
        if ($status) { $ui.txtStatus.Text = $status }
    }
    $appendLog = {
        param([string]$text)
        $ui.txtLog.AppendText($text)
        $ui.txtLog.ScrollToEnd()
        # Las fases "[*] ..." pasan a la cabecera. La salida llega a trozos: la
        # última línea, si está a medias, espera al siguiente.
        $parts = ($script:logTail + $text) -split "`r?`n"
        $script:logTail = $parts[-1]
        for ($k = 0; $k -lt $parts.Count - 1; $k++) {
            $ph = Get-HLPhaseFromLine $parts[$k]
            if ($ph) { $ui.txtPhase.Text = $ph }
        }
    }
    $script:logTail = ''
    $ui.btnLogToggle.Add_Click({
            $show = $ui.brdLog.Visibility -ne 'Visible'
            $ui.brdLog.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
            $ui.btnLogToggle.Content = if ($show) { 'Ocultar registro' } else { 'Ver registro' }
        })
    # Resumen de lo aplicado (lo escribe install.ps1 en config\last_apply.json).
    $showStats = {
        param([string] $After)
        $sum = Get-HLApplySummary -Root $Root
        if (-not $sum -or "$($sum.Stamp)" -lt $After) { return $null }
        $ui.txtStatApplied.Text = "$($sum.Applied)"
        $ui.txtStatManual.Text = "$($sum.NewManual)"
        $ui.txtStatManualLabel.Text = if ([int]$sum.NewManual -eq 1) { 'paso nuevo en la guía' } else { 'pasos nuevos en la guía' }
        $ui.txtStatFailed.Text = "$($sum.Failed)"
        $ui.txtStatFailed.Foreground = $window.FindResource($(if ([int]$sum.Failed -gt 0) { 'Danger' } else { 'Muted' }))
        $ui.pnlStats.Visibility = 'Visible'
        return $sum
    }
    $getState = {
        @{
            Windows = [bool]$ui.chkWindows.IsChecked; Display = [bool]$ui.chkDisplay.IsChecked; Platforms = [bool]$ui.chkPlatforms.IsChecked
            Session = [bool]$ui.chkSession.IsChecked; Latency = [bool]$ui.chkLatency.IsChecked
            Network = [bool]$ui.chkNetwork.IsChecked; NetDiag = [bool]$ui.chkNetDiag.IsChecked
            Game = [bool]$ui.chkGame.IsChecked; Controller = [bool]$ui.chkController.IsChecked
            Audio = [bool]$ui.chkAudio.IsChecked
            Bench = [bool]$ui.chkBench.IsChecked; Experimental = [bool]$ui.chkExperimental.IsChecked
            Platform = "$($ui.cmbPlatform.SelectedItem.Tag)"; DisableOthers = [bool]$ui.chkDisableOthers.IsChecked
            Headset = $ui.txtHeadset.Text.Trim(); AudioMode = "$($ui.cmbAudioMode.SelectedItem.Tag)"
            Intensity = "$($ui.cmbIntensity.SelectedItem.Tag)"; CleanAudio = [bool]$ui.chkCleanAudio.IsChecked
            HeSuVi = [bool]$ui.chkHeSuVi.IsChecked
            OutputDevice = "$($ui.cmbOutput.SelectedItem.Tag)"; Dynamics = "$($ui.cmbDynamics.SelectedItem.Tag)"
        }
    }
    $openLatestReport = {
        $r = Get-ChildItem (Join-Path $Root 'reports') -Filter '*.html' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($r) { Start-Process -FilePath $r.FullName } else { [System.Windows.MessageBox]::Show('Todavía no hay reportes.', 'Hardline') | Out-Null }
    }

    # Lanza un script en un proceso aparte y vuelca su salida al log.
    $startJob = {
        param([string]$label, [string]$scriptPath, [string[]]$arguments, [scriptblock]$onExit)
        if ($script:job) { return }
        $log = Join-Path $env:TEMP ("hardline_gui_{0}.log" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $cmd = ConvertTo-HLCommandLine -Script $scriptPath -Arguments $arguments
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $ui.txtLog.Clear()
        & $appendLog ("> {0} {1}`r`n`r`n" -f (Split-Path $scriptPath -Leaf), ($arguments -join ' '))
        $p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Hidden -PassThru
        $script:job = @{ Process = $p; LogPath = $log; Position = [long]0; OnExit = $onExit; Label = $label }
        & $setBusy $true "$label..."
    }

    $readNew = {
        $j = $script:job
        if (-not $j -or -not (Test-Path $j.LogPath)) { return }
        try {
            $fs = [IO.File]::Open($j.LogPath, 'Open', 'Read', 'ReadWrite')
            try {
                if ($fs.Length -gt $j.Position) {
                    $fs.Position = $j.Position
                    $buf = New-Object byte[] ($fs.Length - $j.Position)
                    $n = $fs.Read($buf, 0, $buf.Length)
                    $j.Position += $n
                    & $appendLog ([Text.Encoding]::UTF8.GetString($buf, 0, $n))
                }
            } finally { $fs.Dispose() }
        } catch { }
    }

    # Versión nueva: se consulta en segundo plano al abrir y cada 30 minutos mientras
    # la ventana siga abierta, sin retrasarla.
    $script:updJob = $null
    $script:updTag = ''
    $script:installedVersion = $HLVersion
    $script:updTicks = 0
    $startUpdateCheck = {
        if ($script:updJob) { return }
        try {
            $script:updJob = Start-Job -ArgumentList $HLRepo -ScriptBlock {
                param($repo)
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                    (Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 8 -UseBasicParsing -Headers @{ 'User-Agent' = 'Hardline' }).tag_name
                } catch { '' }
            }
        } catch { Write-HLLog DEBUG 'Sin comprobación de versión' }
    }
    & $startUpdateCheck

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
            $script:updTicks++
            if ($script:updTicks -ge 7200) { $script:updTicks = 0; & $startUpdateCheck }   # 7200 x 250 ms = 30 min
            if ($script:updJob -and $script:updJob.State -ne 'Running') {
                $tag = "$(Receive-Job $script:updJob -ErrorAction SilentlyContinue | Select-Object -Last 1)"
                Remove-Job $script:updJob -Force -ErrorAction SilentlyContinue
                $script:updJob = $null
                if (Test-HLUpdateAvailable -Latest $tag -Current $script:installedVersion) {
                    $script:updTag = $tag
                    $ui.btnUpdate.Content = "Actualizar a $tag"
                    $ui.btnUpdate.Visibility = 'Visible'
                    $ui.txtVersion.Text = "v$($script:installedVersion)  ·  nueva: $tag"
                }
            }
            if (-not $script:job) { return }
            & $readNew
            if ($script:job.Process.HasExited) {
                & $readNew
                $j = $script:job
                $err = if (Test-Path "$($j.LogPath).err") { (Get-Content "$($j.LogPath).err" -Raw) } else { '' }
                if ($err -and $err.Trim()) { & $appendLog ("`r`n[errores]`r`n" + $err) }
                $code = $j.Process.ExitCode
                Remove-Item $j.LogPath, "$($j.LogPath).err" -Force -ErrorAction SilentlyContinue
                $script:job = $null
                & $setBusy $false ("{0}: terminado{1}." -f $j.Label, $(if ($code) { " (código $code)" } else { '' }))
                $doneText = @{ 'Aplicando' = 'Ajustes aplicados'; 'Simulando' = 'Simulación terminada'; 'Revirtiendo' = 'Cambios revertidos'; 'Actualizando' = 'Actualización terminada' }
                $ui.txtPhase.Text = if ($code) { "$($j.Label): terminó con errores" } elseif ($doneText.ContainsKey($j.Label)) { $doneText[$j.Label] } else { "$($j.Label): listo" }
                if ($j.OnExit) { & $j.OnExit }
            }
        })
    $timer.Start()

    $install = Join-Path $Root 'install.ps1'
    $ui.btnApply.Add_Click({
            $state = & $getState
            $msg = "Se aplicarán los módulos marcados. Se crea un restore point y todo queda en el manifiesto para revertir.`n`n¿Continuar?"
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'YesNo', 'Question') -ne 'Yes') { return }
            $script:applyStart = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
            & $startJob 'Aplicando' $install (ConvertTo-HLGuiArguments -State $state) {
                $sum = & $showStats $script:applyStart
                & $refreshGuide
                # Al terminar solo se enseñan los pasos que nunca has visto; los demás siguen en la guía.
                $gd = Get-HLGuideData -Root $Root
                $new = if ($gd) { @(Get-HLGuideNewSteps -Root $Root).Count } else { 0 }
                if ($new -gt 0) {
                    $ui.txtStatus.Text = "Aplicado. $new pasos nuevos en la guía: te abro el primero."
                    Show-HLGuideWindow -Owner $window -OnlyNew
                    & $refreshGuide
                } elseif ($sum) {
                    $ui.txtStatus.Text = 'Aplicado. Sin pasos nuevos en la guía.' + $(if ($sum.NeedsReboot) { ' Reinicia para completar algunos ajustes.' } else { '' })
                } else { & $openLatestReport }
            }
        })
    $ui.btnDryRun.Add_Click({ & $startJob 'Simulando' $install (ConvertTo-HLGuiArguments -State (& $getState) -DryRun) { & $openLatestReport } })
    $ui.btnRollback.Add_Click({
            # Cada vez que se aplica se crea una sesión: revertir solo la última dejaría
            # puestos los cambios de las anteriores.
            $pending = @(Get-ChildItem (Join-Path $Root 'backups') -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') }).Count
            if ($pending -eq 0) { [System.Windows.MessageBox]::Show('No hay cambios de Hardline pendientes de revertir.', 'Hardline') | Out-Null; return }
            $msg = "¿Revertir todos los cambios de Hardline? ($pending sesiones pendientes, de la más nueva a la más antigua)"
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'YesNo', 'Warning') -ne 'Yes') { return }
            & $startJob 'Revirtiendo' (Join-Path $Root 'rollback.ps1') @('-All', '-Unattended') $null
        })
    $ui.btnNetDiag.Add_Click({ & $startJob 'Diagnóstico de red' $install @('-NetDiagOnly') { & $openLatestReport } })
    $ui.btnBench.Add_Click({ & $startJob 'Benchmark' $install @('-BenchmarkOnly') $null })
    $ui.btnFootstep.Add_Click({ & $startJob 'Test de pasos' (Join-Path $Root 'src\audio\footstep_test.ps1') @() $null })
    $ui.btnGameplay.Add_Click({
            $msg = "Medir partida (60 s de juego real):`n`n1. Abre Warzone y entra en partida o en el campo de tiro.`n2. La medición empieza 20 s después de abrir el juego (suena un aviso) y dura 60 s.`n3. Juega con normalidad hasta el segundo aviso.`n`nPara comparar, mide antes y después de aplicar, en el mismo modo y mapa."
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'OKCancel', 'Information') -ne 'OK') { return }
            & $startJob 'Medir partida' (Join-Path $Root 'src\modules\game\gameplay_bench.ps1') @('-Root', $Root, '-NoOpen') { & $openLatestReport }
        })
    $ui.btnControllerTest.Add_Click({
            [System.Windows.MessageBox]::Show("Test de mando (~15 s):`n`n1. Al empezar, suelta el mando y no lo toques (5 s).`n2. Cuando lo indique la salida, gira los dos sticks sin parar (5 s).`n`nLos resultados aparecen en el panel de salida.", 'Hardline') | Out-Null
            & $startJob 'Test de mando' (Join-Path $Root 'src\modules\input\controller_test.ps1') @() $null
        })
    $ui.btnUpdate.Add_Click({
            if ($script:job) { [System.Windows.MessageBox]::Show('Espera a que termine la tarea en curso.', 'Hardline') | Out-Null; return }
            $msg = "Se descarga Hardline $($script:updTag) (SHA256 verificado) encima de esta instalación, sin cerrar la ventana. Backups, reportes, mediciones, perfiles y la guía se conservan.`n`n¿Continuar?"
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'YesNo', 'Question') -ne 'Yes') { return }
            $before = $script:installedVersion
            & $startJob 'Actualizando' (Join-Path $Root 'install.ps1') @('-UpdateOnly') {
                $now = Get-HLInstalledVersion -Root $Root
                if ($now -and (Test-HLUpdateAvailable -Latest $now -Current $before)) {
                    $script:installedVersion = $now
                    $ui.btnUpdate.Visibility = 'Collapsed'
                    # Las tareas (Aplicar, Benchmark...) arrancan procesos nuevos: ya usan la versión nueva.
                    $ui.txtVersion.Text = "v$now instalada"
                    $ui.txtVersion.ToolTip = "Esta ventana es de la v${HLVersion}: reábrela para ver los cambios de la interfaz."
                    $ui.txtStatus.Text = "Actualizado a v$now. Los botones ya usan la versión nueva."
                } else {
                    $ui.txtStatus.Text = 'No se pudo actualizar: revisa el panel de salida.'
                }
            }
        })
    $ui.btnReport.Add_Click({ & $openLatestReport })
    $ui.btnEqPanel.Add_Click({
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (Join-Path $Root 'src\gui\eq_panel.ps1')), '-Root', ('"{0}"' -f $Root)) -WindowStyle Hidden
        })
    $ui.btnGuide.Add_Click({ Show-HLGuideWindow -Owner $window; & $refreshGuide })
    $ui.btnNews.Add_Click({
            Show-HLNewsWindow -Root $Root -Owner $window
            foreach ($c in @(Get-HLAnnouncements -Root $Root | Where-Object { $_.Kind -eq 'release' })) { Set-HLAnnouncementSeen -Root $Root -Card $c }
            & $refreshNews
        })
    $ui.btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$Root`"" })
    $ui.chkAudio.Add_Click({
            foreach ($c in @('txtHeadset', 'cmbAudioMode', 'cmbIntensity', 'chkCleanAudio', 'chkHeSuVi', 'cmbOutput', 'cmbDynamics')) { $ui[$c].IsEnabled = [bool]$ui.chkAudio.IsChecked }
        })

    $window.Add_Closing({
            param($s, $e)
            if ($script:job -and -not $script:job.Process.HasExited) {
                $r = [System.Windows.MessageBox]::Show('Hay una tarea en curso. Si cierras, seguirá ejecutándose en segundo plano. ¿Cerrar?', 'Hardline', 'YesNo', 'Warning')
                if ($r -ne 'Yes') { $e.Cancel = $true; return }
            }
            $timer.Stop()
        })
    [void]$window.ShowDialog()
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-HLAdmin)) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show('Hardline necesita permisos de administrador. Ábrelo desde el acceso directo o con install.ps1 -Gui.', 'Hardline') | Out-Null
        return
    }
    try {
        Show-HLGui
    } catch {
        # Si la ventana no se puede construir, que se vea el motivo en lugar de cerrarse sin más.
        $msg = "$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)"
        try { Add-Content -Path (Join-Path $Root 'logs\gui_error.log') -Value ("{0}`r`n{1}`r`n" -f (Get-Date -Format 's'), $msg) -Encoding UTF8 } catch { Write-Verbose 'Sin log de la interfaz' }
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("La interfaz no pudo abrirse:`r`n`r`n$msg`r`n`r`nDetalle en logs\gui_error.log. Mientras tanto, el modo consola funciona: install.ps1 sin -Gui.", 'Hardline') | Out-Null
    }
}

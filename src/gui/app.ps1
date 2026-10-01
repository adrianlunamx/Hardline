#Requires -Version 5.1
<#
    Hardline - interfaz gráfica (WPF).

    La ventana no aplica nada por sí misma: construye los parámetros a partir
    de lo marcado y lanza install.ps1 / rollback.ps1 / footstep_test.ps1 en un
    proceso aparte, sin consola. Así la GUI y el modo consola ejecutan
    exactamente el mismo código, con el mismo manifiesto y el mismo rollback.

    La salida del proceso va a un archivo temporal que un DispatcherTimer lee
    cada 250 ms (los manejadores de eventos .NET en otros hilos no tienen
    runspace de PowerShell; el timer corre en el hilo de la interfaz).

    Se lanza con:  install.ps1 -Gui   o el acceso directo Inicio > Hardline.
#>
param([Parameter(Mandatory)] [string] $Root)

. (Join-Path $Root 'src\core\common.ps1')
. (Join-Path $Root 'src\core\guide.ps1')

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
    }
    return $a.ToArray()
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

function Show-HLGuideWindow {
    param($Owner)
    $data = Get-HLGuideData -Root $Root
    if (-not $data -or $data.Steps.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No hay pasos manuales todavía. Pulsa Aplicar y al terminar aparecerán aquí.', 'Hardline') | Out-Null
        return
    }
    [xml]$gx = Get-Content (Join-Path $PSScriptRoot 'guide.xaml') -Raw -Encoding UTF8
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $gx))
    if ($Owner) { $w.Owner = $Owner }
    $g = @{}
    foreach ($n in @('gPhase', 'gHint', 'gCount', 'gProgress', 'gArea', 'gText', 'gState', 'gLink', 'gPrev', 'gSkip', 'gDone', 'gList')) { $g[$n] = $w.FindName($n) }

    $steps = @($data.Steps)
    $done = Get-HLGuideState -Root $Root
    $pos = @{ I = [Math]::Max(0, (Get-HLNextPendingIndex -Steps $steps -Done $done)) }

    $render = {
        $s = $steps[$pos.I]
        $isDone = $done.ContainsKey($s.Id)
        $count = @($steps | Where-Object { $done.ContainsKey($_.Id) }).Count
        $g.gPhase.Text = '{0}. {1}' -f $s.PhaseNum, $s.Phase
        $g.gHint.Text = $s.PhaseHint
        $g.gCount.Text = 'Paso {0} de {1}  ·  {2} hechos' -f ($pos.I + 1), $steps.Count, $count
        $g.gProgress.Value = $count / $steps.Count
        $g.gArea.Text = "$($s.Area)".ToUpperInvariant()
        $g.gText.Text = $s.Text
        $g.gState.Text = if ($isDone) { 'Hecho' } else { '' }
        $g.gDone.Content = if ($isDone) { 'Desmarcar' } else { 'Hecho' }
        $g.gLink.Visibility = if ("$($s.Link)" -match '^https?://') { 'Visible' } else { 'Collapsed' }
        $g.gPrev.IsEnabled = $pos.I -gt 0
        $g.gSkip.IsEnabled = $pos.I -lt $steps.Count - 1
    }

    $g.gDone.Add_Click({
            $s = $steps[$pos.I]
            if ($done.ContainsKey($s.Id)) { $done.Remove($s.Id); Save-HLGuideState -Root $Root -Done $done; & $render; return }
            $done[$s.Id] = $true
            Save-HLGuideState -Root $Root -Done $done
            $next = Get-HLNextPendingIndex -Steps $steps -Done $done -From $pos.I
            if ($next -lt 0) {
                & $render
                [System.Windows.MessageBox]::Show('Todos los pasos hechos. Ahora usa "Medir partida" para comprobar la diferencia.', 'Hardline') | Out-Null
                return
            }
            $pos.I = $next
            & $render
        })
    $g.gSkip.Add_Click({ if ($pos.I -lt $steps.Count - 1) { $pos.I++; & $render } })
    $g.gPrev.Add_Click({ if ($pos.I -gt 0) { $pos.I--; & $render } })
    $g.gLink.Add_Click({ $l = "$($steps[$pos.I].Link)"; if ($l -match '^https?://') { Start-Process $l } })
    $g.gList.Add_Click({ $h = Update-HLGuideHtml -Root $Root; if ($h) { Start-Process -FilePath $h } })
    $w.Add_Closed({ Update-HLGuideHtml -Root $Root | Out-Null })
    & $render
    [void]$w.ShowDialog()
}

# --------------------------------------------------------------------------
# Ventana
# --------------------------------------------------------------------------

function Show-HLGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    [xml]$xaml = Get-Content (Join-Path $PSScriptRoot 'main.xaml') -Raw -Encoding UTF8
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $ui = @{}
    # Los nombres dentro de plantillas (ControlTemplate) viven en otro ámbito: FindName no los ve.
    foreach ($n in ($xaml.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])]'))) {
        $name = $n.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $ui[$name] = $window.FindName($name) }
    }
    $ui.txtVersion.Text = "v$HLVersion  ·  $Root"

    $script:job = $null      # @{ Process; LogPath; Position; OnExit }
    $buttons = @('btnApply', 'btnDryRun', 'btnRollback', 'btnNetDiag', 'btnBench', 'btnFootstep', 'btnControllerTest', 'btnGameplay')

    $setBusy = {
        param([bool]$busy, [string]$status)
        foreach ($b in $buttons) { $ui[$b].IsEnabled = -not $busy }
        $ui.prgBusy.IsIndeterminate = $busy
        if ($status) { $ui.txtStatus.Text = $status }
    }
    $appendLog = {
        param([string]$text)
        $ui.txtLog.AppendText($text)
        $ui.txtLog.ScrollToEnd()
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

    # Versión nueva: se consulta en segundo plano para no retrasar la ventana.
    $script:updJob = $null
    $script:updTag = ''
    try {
        $script:updJob = Start-Job -ArgumentList $HLRepo -ScriptBlock {
            param($repo)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                (Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 8 -UseBasicParsing -Headers @{ 'User-Agent' = 'Hardline' }).tag_name
            } catch { '' }
        }
    } catch { Write-HLLog DEBUG 'Sin comprobación de versión' }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
            if ($script:updJob -and $script:updJob.State -ne 'Running') {
                $tag = "$(Receive-Job $script:updJob -ErrorAction SilentlyContinue | Select-Object -Last 1)"
                Remove-Job $script:updJob -Force -ErrorAction SilentlyContinue
                $script:updJob = $null
                if (Test-HLUpdateAvailable -Latest $tag -Current $HLVersion) {
                    $script:updTag = $tag
                    $ui.btnUpdate.Content = "Actualizar a $tag"
                    $ui.btnUpdate.Visibility = 'Visible'
                    $ui.txtVersion.Text = "v$HLVersion  ·  hay una versión nueva: $tag"
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
                if ($j.OnExit) { & $j.OnExit }
            }
        })
    $timer.Start()

    $install = Join-Path $Root 'install.ps1'
    $ui.btnApply.Add_Click({
            $state = & $getState
            $msg = "Se aplicarán los módulos marcados. Se crea un restore point y todo queda en el manifiesto para revertir.`n`n¿Continuar?"
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'YesNo', 'Question') -ne 'Yes') { return }
            & $startJob 'Aplicando' $install (ConvertTo-HLGuiArguments -State $state) {
                # Al terminar, la guía de pasos manuales; si no hay pasos, el reporte.
                $gd = Get-HLGuideData -Root $Root
                if ($gd -and $gd.Steps.Count -gt 0 -and (Get-Date) - (Get-Item (Join-Path $Root 'reports\guia.json')).LastWriteTime -lt [TimeSpan]::FromMinutes(30)) {
                    $ui.txtStatus.Text = 'Aplicado. Te queda la guía de pasos manuales.'
                    Show-HLGuideWindow -Owner $window
                } else { & $openLatestReport }
            }
        })
    $ui.btnDryRun.Add_Click({ & $startJob 'Simulando' $install (ConvertTo-HLGuiArguments -State (& $getState) -DryRun) { & $openLatestReport } })
    $ui.btnRollback.Add_Click({
            if ([System.Windows.MessageBox]::Show('¿Revertir todos los cambios de la última sesión?', 'Hardline', 'YesNo', 'Warning') -ne 'Yes') { return }
            & $startJob 'Revirtiendo' (Join-Path $Root 'rollback.ps1') @('-Unattended') $null
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
            $msg = "Se descarga Hardline $($script:updTag) (SHA256 verificado) encima de esta instalación. Backups, reportes, mediciones, perfiles y la guía se conservan.`n`nLa ventana se cierra y se vuelve a abrir actualizada. ¿Continuar?"
            if ([System.Windows.MessageBox]::Show($msg, 'Hardline', 'YesNo', 'Question') -ne 'Yes') { return }
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $Root 'install.ps1')), '-Update', '-Gui')
            $window.Close()
        })
    $ui.btnReport.Add_Click({ & $openLatestReport })
    $ui.btnEqPanel.Add_Click({
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (Join-Path $Root 'src\gui\eq_panel.ps1')), '-Root', ('"{0}"' -f $Root)) -WindowStyle Hidden
        })
    $ui.btnGuide.Add_Click({ Show-HLGuideWindow -Owner $window })
    $ui.btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$Root`"" })
    $ui.chkAudio.Add_Click({
            foreach ($c in @('txtHeadset', 'cmbAudioMode', 'cmbIntensity', 'chkCleanAudio')) { $ui[$c].IsEnabled = [bool]$ui.chkAudio.IsChecked }
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

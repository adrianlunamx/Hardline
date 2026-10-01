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
    $map = [ordered]@{ Windows = '-SkipWindows'; Platforms = '-SkipPlatforms'; Latency = '-SkipLatency'; Network = '-SkipNetwork'
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
    }
    return $a.ToArray()
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
    $buttons = @('btnApply', 'btnDryRun', 'btnRollback', 'btnNetDiag', 'btnBench', 'btnFootstep', 'btnControllerTest')

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
            Windows = [bool]$ui.chkWindows.IsChecked; Platforms = [bool]$ui.chkPlatforms.IsChecked
            Session = [bool]$ui.chkSession.IsChecked; Latency = [bool]$ui.chkLatency.IsChecked
            Network = [bool]$ui.chkNetwork.IsChecked; NetDiag = [bool]$ui.chkNetDiag.IsChecked
            Game = [bool]$ui.chkGame.IsChecked; Controller = [bool]$ui.chkController.IsChecked
            Audio = [bool]$ui.chkAudio.IsChecked
            Bench = [bool]$ui.chkBench.IsChecked; Experimental = [bool]$ui.chkExperimental.IsChecked
            Platform = "$($ui.cmbPlatform.SelectedItem.Tag)"; DisableOthers = [bool]$ui.chkDisableOthers.IsChecked
            Headset = $ui.txtHeadset.Text.Trim(); AudioMode = "$($ui.cmbAudioMode.SelectedItem.Tag)"
            Intensity = "$($ui.cmbIntensity.SelectedItem.Tag)"
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

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
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
            & $startJob 'Aplicando' $install (ConvertTo-HLGuiArguments -State $state) { & $openLatestReport }
        })
    $ui.btnDryRun.Add_Click({ & $startJob 'Simulando' $install (ConvertTo-HLGuiArguments -State (& $getState) -DryRun) { & $openLatestReport } })
    $ui.btnRollback.Add_Click({
            if ([System.Windows.MessageBox]::Show('¿Revertir todos los cambios de la última sesión?', 'Hardline', 'YesNo', 'Warning') -ne 'Yes') { return }
            & $startJob 'Revirtiendo' (Join-Path $Root 'rollback.ps1') @('-Unattended') $null
        })
    $ui.btnNetDiag.Add_Click({ & $startJob 'Diagnóstico de red' $install @('-NetDiagOnly') { & $openLatestReport } })
    $ui.btnBench.Add_Click({ & $startJob 'Benchmark' $install @('-BenchmarkOnly') $null })
    $ui.btnFootstep.Add_Click({ & $startJob 'Test de pasos' (Join-Path $Root 'src\audio\footstep_test.ps1') @() $null })
    $ui.btnControllerTest.Add_Click({
            [System.Windows.MessageBox]::Show("Test de mando (~15 s):`n`n1. Al empezar, suelta el mando y no lo toques (5 s).`n2. Cuando lo indique la salida, gira los dos sticks sin parar (5 s).`n`nLos resultados aparecen en el panel de salida.", 'Hardline') | Out-Null
            & $startJob 'Test de mando' (Join-Path $Root 'src\modules\input\controller_test.ps1') @() $null
        })
    $ui.btnReport.Add_Click({ & $openLatestReport })
    $ui.btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$Root`"" })
    $ui.chkAudio.Add_Click({
            foreach ($c in @('txtHeadset', 'cmbAudioMode', 'cmbIntensity')) { $ui[$c].IsEnabled = [bool]$ui.chkAudio.IsChecked }
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
    Show-HLGui
}

#Requires -Version 5.1
<#
    Hardline - panel del EQ.

    Encender/apagar el EQ de pasos, su intensidad (deslizador de 0 a 150 %) y
    el nivel del compresor (Suave, Normal, Fuerte, Rush). Todo se aplica al
    momento y sin administrador: la intensidad escribe un preset en
    config\hardline\ de Equalizer APO (la instalación da permiso de escritura
    a tu usuario) y el compresor va por la Remote API de Voicemeeter. El
    estado se relee cada segundo, así que si usas Ctrl+Alt+F10 en partida el
    panel lo refleja.

    Se abre con:  Inicio > Hardline > Hardline EQ,  o el botón de la interfaz.
#>
param([string] $Root = '')

if (-not $Root) { $Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
. (Join-Path $Root 'src\core\common.ps1')
. (Join-Path $Root 'src\audio\eq.ps1')
. (Join-Path $Root 'src\audio\eqswitch.ps1')
. (Join-Path $Root 'src\audio\voicemeeter.ps1')

# Texto del estado para la ventana (sin WPF: se prueba en tests). $Intensity: 0-1.5 o $null.
function Get-HLEqPanelView {
    param($On, $Intensity)
    if ($null -eq $On) {
        return [pscustomobject]@{ State = 'Sin configurar'; Detail = 'Ejecuta la configuración de audio de Hardline (casilla Audio).'; Button = 'Encender'; Color = '#8A93A3'; Enabled = $false }
    }
    $detail = if ($null -ne $Intensity) { 'Intensidad {0} %' -f [int][Math]::Round($Intensity * 100) } else { 'Preset de Hardline' }
    if ($On) { return [pscustomobject]@{ State = 'Encendido'; Detail = "$detail. Se aplica al momento."; Button = 'Apagar'; Color = '#3FB950'; Enabled = $true } }
    return [pscustomobject]@{ State = 'Apagado'; Detail = "$detail. Ahora suena tal cual, sin corrección."; Button = 'Encender'; Color = '#8A93A3'; Enabled = $true }
}

# Qué se oye con cada intensidad (0-150).
function Get-HLEqIntensityHint {
    param([int] $Percent)
    if ($Percent -eq 0) { return 'Solo la corrección de tu headset: sonido neutro, sin realce de pasos.' }
    if ($Percent -lt 70) { return 'Realce ligero: pasos algo más claros y sonido casi natural.' }
    if ($Percent -lt 100) { return 'Realce moderado: pasos claros sin sonido tan metálico.' }
    if ($Percent -eq 100) { return 'Preset completo: 2,2-3,6 kHz (pisadas) muy por encima del resto.' }
    return 'Más que el preset: pasos todavía más marcados, sonido más metálico y cansado. El volumen general baja para no saturar.'
}

function Show-HLEqPanel {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    [xml]$x = Get-Content (Join-Path $PSScriptRoot 'eq_panel.xaml') -Raw -Encoding UTF8
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    Set-HLWindowIcon -Window $w -Root $Root
    $c = @{}
    foreach ($n in @('eqDot', 'eqState', 'eqDetail', 'eqToggle', 'eqIntValue', 'eqIntSlider', 'eqIntHint', 'eqDynValue', 'eqDynSlider', 'eqDynHint', 'eqTest', 'eqTopmost')) { $c[$n] = $w.FindName($n) }
    $brush = { param($hex) New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
    $xml = Join-Path $Root 'src\audio\configs\voicemeeter_comp.xml'
    $sw = Get-HLEqSwitchPath
    $view = @{ Busy = $false; Last = ''; PendingInt = $false }

    # --- Compresor -------------------------------------------------------------
    $modes = $script:HLDynamicsModes
    $names = @{ suave = 'Suave'; normal = 'Normal'; pasos = 'Fuerte'; rush = 'Rush' }
    $showDyn = {
        $m = $modes[[int]$c.eqDynSlider.Value]
        $c.eqDynValue.Text = $names[$m]
        return $m
    }
    $applyDyn = {
        $mode = & $showDyn
        $st = Get-HLAudioSettings -Root $Root
        try {
            $r = Set-HLVoicemeeterDynamics -XmlPath $xml -Mode $mode -PreampDb $st.PreampDb -Overrides $st.Overrides
            Save-HLAudioSettings -Root $Root -Set @{ Dynamics = $mode }
            $desc = ($script:HLDynamicsProfiles[$mode] -split ': ', 2)[-1]
            $c.eqDynHint.Text = if ($r.Type -lt 3) { "$desc. Aplicado en parte: tu Voicemeeter no es Potato y solo acepta los mandos básicos." } else { "$desc. $($r.Values.Ratio):1 desde $($r.Values.Threshold) dB, recuperación $($r.Values.Release) ms, ganancia +$($r.Values.GainOut) dB." }
        } catch {
            Save-HLAudioSettings -Root $Root -Set @{ Dynamics = $mode }
            $c.eqDynHint.Text = "Guardado, pero no aplicado: $($_.Exception.Message) Se aplica cuando abras Voicemeeter y lo elijas de nuevo."
        }
    }
    $settings = Get-HLAudioSettings -Root $Root
    $view.Busy = $true
    $c.eqDynSlider.Value = [Math]::Max(0, [array]::IndexOf($modes, $settings.Dynamics))
    $view.Busy = $false
    [void](& $showDyn)
    $c.eqDynHint.Text = ($script:HLDynamicsProfiles[$settings.Dynamics] -split ': ', 2)[-1] + '.'
    $c.eqDynSlider.Add_ValueChanged({ if (-not $view.Busy) { & $applyDyn } })

    # --- Intensidad del EQ -------------------------------------------------------
    # Se aplica 350 ms después del último movimiento: arrastrar no reescribe el preset 30 veces.
    $debounce = New-Object System.Windows.Threading.DispatcherTimer
    $debounce.Interval = [TimeSpan]::FromMilliseconds(350)
    $applyInt = {
        $debounce.Stop()
        $view.PendingInt = $false
        $pct = [int]$c.eqIntSlider.Value
        try {
            $pre = Set-HLEqIntensity -Intensity ($pct / 100.0) -SwitchPath $sw
            Save-HLAudioSettings -Root $Root -Set @{ PreampDb = [double]$pre }
            $c.eqIntHint.Text = (Get-HLEqIntensityHint -Percent $pct) + " Preamp $pre dB."
            # Los umbrales del compresor dependen del preamp: se reajustan si Voicemeeter está abierto.
            $st = Get-HLAudioSettings -Root $Root
            try { [void](Set-HLVoicemeeterDynamics -XmlPath $xml -Mode $st.Dynamics -PreampDb $pre -Overrides $st.Overrides) } catch { Write-Verbose 'Voicemeeter cerrado' }
        } catch {
            $c.eqIntHint.Text = "No aplicado: $($_.Exception.Message)"
        }
        $view.Last = ''
    }
    $debounce.Add_Tick({ & $applyInt })
    $c.eqIntSlider.Add_ValueChanged({
            $pct = [int]$c.eqIntSlider.Value
            $c.eqIntValue.Text = "$pct %"
            if ($view.Busy) { return }
            $c.eqIntHint.Text = Get-HLEqIntensityHint -Percent $pct
            $view.PendingInt = $true
            $debounce.Stop(); $debounce.Start()
        })
    $c.eqIntSlider.IsEnabled = [bool]($sw -and (Test-Path $sw))

    # --- Estado (se relee cada segundo) ----------------------------------------------
    $refresh = {
        $on = Get-HLEqState -SwitchPath $sw
        $int = Get-HLEqIntensity -SwitchPath $sw
        $key = "$on|$int"
        if ($key -eq $view.Last) { return }
        $view.Last = $key
        $v = Get-HLEqPanelView -On $on -Intensity $int
        $c.eqState.Text = $v.State
        $c.eqDot.Fill = & $brush $v.Color
        $c.eqDetail.Text = $v.Detail
        $c.eqToggle.Content = $v.Button
        $c.eqToggle.IsEnabled = $v.Enabled
        $c.eqIntSlider.IsEnabled = $v.Enabled
        if ($null -ne $int -and -not $view.PendingInt -and -not $c.eqIntSlider.IsMouseCaptureWithin) {
            $view.Busy = $true
            $c.eqIntSlider.Value = [Math]::Round($int * 20) * 5
            $view.Busy = $false
            if (-not $c.eqIntHint.Text) { $c.eqIntHint.Text = Get-HLEqIntensityHint -Percent ([int]$c.eqIntSlider.Value) }
        }
    }

    $c.eqToggle.Add_Click({
            try { Set-HLEqState -On (-not (Get-HLEqState -SwitchPath $sw)) -SwitchPath $sw } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Hardline EQ') | Out-Null }
            & $refresh
        })
    $c.eqTest.Add_Click({
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $Root 'src\audio\footstep_test.ps1')))
        })
    $c.eqTopmost.Add_Click({ $w.Topmost = [bool]$c.eqTopmost.IsChecked })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({ & $refresh })
    $timer.Start()
    $w.Add_Closed({
            $timer.Stop()
            # Si se cierra justo después de mover el deslizador, se aplica igual.
            if ($view.PendingInt) { & $applyInt }
        })
    & $refresh
    [void]$w.ShowDialog()
}

if ($MyInvocation.InvocationName -ne '.') { Show-HLEqPanel }

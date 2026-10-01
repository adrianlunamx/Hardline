#Requires -Version 5.1
<#
    Hardline - panel del EQ.

    Encender/apagar el EQ de pasos y cambiar la intensidad sin abrir nada
    más. No necesita administrador: solo edita config\hardline\switch.txt de
    Equalizer APO (la instalación da permiso de escritura a tu usuario), igual
    que el atajo Ctrl+Alt+F10. El estado se relee cada segundo, así que si
    usas el atajo en partida el panel lo refleja.

    Se abre con:  Inicio > Hardline > Hardline EQ,  o el botón de la interfaz.
#>
param([string] $Root = '')

if (-not $Root) { $Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
. (Join-Path $Root 'src\audio\eqswitch.ps1')

# Texto del estado para la ventana (sin WPF: se prueba en tests).
function Get-HLEqPanelView {
    param($On, [string] $Preset, $Variants)
    $label = ($Variants | Where-Object { $_.Name -eq $Preset } | Select-Object -First 1).Label
    if ($null -eq $On) {
        return [pscustomobject]@{ State = 'Sin configurar'; Detail = 'Ejecuta la configuración de audio de Hardline (casilla Audio).'; Button = 'Encender'; Color = '#8A93A3'; Enabled = $false }
    }
    $detail = if ($label) { "Intensidad: $label" } else { "Preset: $Preset" }
    if ($On) { return [pscustomobject]@{ State = 'Encendido'; Detail = $detail; Button = 'Apagar'; Color = '#3FB950'; Enabled = $true } }
    return [pscustomobject]@{ State = 'Apagado'; Detail = "$detail. Suena tal cual, sin corrección."; Button = 'Encender'; Color = '#8A93A3'; Enabled = $true }
}

function Show-HLEqPanel {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    [xml]$x = Get-Content (Join-Path $PSScriptRoot 'eq_panel.xaml') -Raw -Encoding UTF8
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $c = @{}
    foreach ($n in @('eqBadge', 'eqState', 'eqDetail', 'eqToggle', 'eqIntensity', 'eqTest', 'eqTopmost')) { $c[$n] = $w.FindName($n) }

    $sw = Get-HLEqSwitchPath
    $view = @{ Busy = $false; Last = '' }
    $variants = @()
    if ($sw -and (Test-Path $sw)) {
        $names = @(Get-ChildItem (Split-Path $sw -Parent) -Filter 'warzone_footsteps_*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        $variants = @(Get-HLEqPresetVariants -Names $names -Current (Get-HLEqPreset -SwitchPath $sw))
    }
    foreach ($v in $variants) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $v.Label; $item.Tag = $v.Name
        [void]$c.eqIntensity.Items.Add($item)
    }
    $c.eqIntensity.IsEnabled = $variants.Count -gt 1

    $refresh = {
        $on = Get-HLEqState -SwitchPath $sw
        $preset = Get-HLEqPreset -SwitchPath $sw
        $key = "$on|$preset"
        if ($key -eq $view.Last) { return }
        $view.Last = $key
        $v = Get-HLEqPanelView -On $on -Preset $preset -Variants $variants
        $c.eqState.Text = $v.State
        $c.eqState.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($v.Color))
        $c.eqDetail.Text = $v.Detail
        $c.eqToggle.Content = $v.Button
        $c.eqToggle.IsEnabled = $v.Enabled
        $view.Busy = $true
        foreach ($item in $c.eqIntensity.Items) { if ($item.Tag -eq $preset) { $c.eqIntensity.SelectedItem = $item } }
        $view.Busy = $false
    }

    $c.eqToggle.Add_Click({
            try { Set-HLEqState -On (-not (Get-HLEqState -SwitchPath $sw)) -SwitchPath $sw } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Hardline EQ') | Out-Null }
            & $refresh
        })
    $c.eqIntensity.Add_SelectionChanged({
            if ($view.Busy -or -not $c.eqIntensity.SelectedItem) { return }
            try { Set-HLEqPreset -PresetName "$($c.eqIntensity.SelectedItem.Tag)" -SwitchPath $sw } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Hardline EQ') | Out-Null }
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
    $w.Add_Closed({ $timer.Stop() })
    & $refresh
    [void]$w.ShowDialog()
}

if ($MyInvocation.InvocationName -ne '.') { Show-HLEqPanel }

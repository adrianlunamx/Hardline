#Requires -Version 5.1
<#
    Hardline - panel del EQ.

    Encender/apagar el EQ de pasos y cambiar la intensidad sin abrir nada
    más. No necesita administrador: solo edita config\hardline\switch.txt de
    Equalizer APO (la instalación da permiso de escritura a tu usuario), igual
    que el atajo Ctrl+Alt+F10. El estado se relee cada segundo, así que si
    usas el atajo en partida el panel lo refleja.

    Arriba anuncia las novedades de cada versión y el resumen de la última
    vez que se aplicaron ajustes, hasta que pulsas "Entendido".

    Se abre con:  Inicio > Hardline > Hardline EQ,  o el botón de la interfaz.
#>
param([string] $Root = '')

if (-not $Root) { $Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
. (Join-Path $Root 'src\core\common.ps1')
. (Join-Path $Root 'src\core\news.ps1')
. (Join-Path $Root 'src\audio\eqswitch.ps1')
. (Join-Path $Root 'src\audio\voicemeeter.ps1')
. (Join-Path $Root 'src\gui\theme.ps1')
. (Join-Path $Root 'src\gui\news_ui.ps1')

# Texto del estado para la ventana (sin WPF: se prueba en tests).
function Get-HLEqPanelView {
    param($On, [string] $Preset, $Variants)
    $label = ($Variants | Where-Object { $_.Name -eq $Preset } | Select-Object -First 1).Label
    if ($null -eq $On) {
        return [pscustomobject]@{ State = 'Sin configurar'; Detail = 'Ejecuta la configuración de audio de Hardline (módulo Audio).'; Button = 'Encender'; Color = '#8B94A5'; Enabled = $false }
    }
    $detail = if ($label) { "Intensidad: $label" } else { "Preset: $Preset" }
    if ($On) { return [pscustomobject]@{ State = 'Encendido'; Detail = $detail; Button = 'Apagar'; Color = '#3FB950'; Enabled = $true } }
    return [pscustomobject]@{ State = 'Apagado'; Detail = "$detail. Suena tal cual, sin corrección."; Button = 'Encender'; Color = '#8B94A5'; Enabled = $true }
}

function Show-HLEqPanel {
    $r = New-HLWindow -Path (Join-Path $PSScriptRoot 'eq_panel.xaml') -Root $Root
    $w = $r.Window
    # Con la tarjeta de novedades abierta, que nunca pase del alto de la pantalla (hace scroll).
    $w.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
    $c = $r.Ui

    # Novedades y avisos sin ver, uno cada vez.
    $news = @{ Cards = @(Get-HLAnnouncements -Root $Root); I = 0 }
    $showNews = {
        if ($news.I -ge $news.Cards.Count) { $c.newsCard.Visibility = 'Collapsed'; return }
        $card = $news.Cards[$news.I]
        $c.newsBadge.Text = $card.Badge
        $c.newsTitle.Text = $card.Title
        $c.newsDate.Text = $card.Date
        $c.newsCount.Text = if ($news.Cards.Count -gt 1) { '{0} de {1}' -f ($news.I + 1), $news.Cards.Count } else { '' }
        # Tres puntos como mucho: la ventana tiene que caber en pantalla. El resto, en "Ver todas".
        $items = @($card.Items)
        Add-HLNewsItems -Panel $c.newsItems -Window $w -Items @($items | Select-Object -First 3)
        $c.newsMore.Content = if ($items.Count -gt 3) { "Ver todas (+$($items.Count - 3))" } else { 'Ver todas' }
        $c.newsOk.Content = if ($news.I -lt $news.Cards.Count - 1) { 'Siguiente' } else { 'Entendido' }
        $c.newsCard.Visibility = 'Visible'
    }
    $c.newsOk.Add_Click({
            try { Set-HLAnnouncementSeen -Root $Root -Card $news.Cards[$news.I] } catch { Write-Verbose 'Aviso no guardado' }
            $news.I++
            & $showNews
        })
    $c.newsMore.Add_Click({ Show-HLNewsWindow -Root $Root -Owner $w })
    $c.btnNewsAll.Add_Click({ Show-HLNewsWindow -Root $Root -Owner $w })
    & $showNews

    # Compresor: se aplica al momento con Voicemeeter abierto y se recuerda para la próxima instalación.
    $settings = Get-HLAudioSettings -Root $Root
    $view0 = @{ Busy = $true }
    foreach ($item in $c.eqDynamics.Items) { if ($item.Tag -eq $settings.Dynamics) { $c.eqDynamics.SelectedItem = $item } }
    $view0.Busy = $false
    $c.eqDynHint.Text = 'Bajar lo fuerte y subir lo flojo: tus disparos son lo más fuerte que suena, por eso son lo que más baja.'
    $c.eqDynamics.Add_SelectionChanged({
            if ($view0.Busy -or -not $c.eqDynamics.SelectedItem) { return }
            $mode = "$($c.eqDynamics.SelectedItem.Tag)"
            $st = Get-HLAudioSettings -Root $Root
            try {
                $r = Set-HLVoicemeeterDynamics -XmlPath (Join-Path $Root 'src\audio\configs\voicemeeter_comp.xml') -Mode $mode -PreampDb $st.PreampDb -Overrides $st.Overrides
                Save-HLAudioSettings -Root $Root -Set @{ Dynamics = $mode }
                $c.eqDynHint.Text = if ($r.Type -lt 3) { 'Aplicado en parte: tu Voicemeeter no es Potato y solo acepta los mandos básicos.' } else { "Aplicado. Umbral $($r.Values.Threshold) dB, $($r.Values.Ratio):1, ganancia +$($r.Values.GainOut) dB." }
            } catch {
                $c.eqDynHint.Text = "No aplicado: $($_.Exception.Message) Abre Voicemeeter y vuelve a elegirlo."
            }
        })

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
        # Apagado: el botón de encender destaca.
        $c.eqToggle.Style = if ($v.Enabled -and -not $on) { $w.FindResource('Primary') } else { $w.FindResource([System.Windows.Controls.Button]) }
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

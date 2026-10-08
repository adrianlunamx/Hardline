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

    Arriba anuncia las novedades de cada versión y el resumen de la última
    vez que se aplicaron ajustes, hasta que pulsas "Entendido".

    Se abre con:  Inicio > Hardline > Hardline EQ,  o el botón de la interfaz.
#>
param([string] $Root = '')

if (-not $Root) { $Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
. (Join-Path $Root 'src\core\common.ps1')
. (Join-Path $Root 'src\core\news.ps1')
. (Join-Path $Root 'src\audio\eq.ps1')
. (Join-Path $Root 'src\audio\eqswitch.ps1')
. (Join-Path $Root 'src\audio\voicemeeter.ps1')
. (Join-Path $Root 'src\gui\theme.ps1')
. (Join-Path $Root 'src\gui\news_ui.ps1')

# Texto del estado para la ventana (sin WPF: se prueba en tests). $Intensity: 0-1.5 o $null.
function Get-HLEqPanelView {
    param($On, $Intensity)
    if ($null -eq $On) {
        return [pscustomobject]@{ State = 'Sin configurar'; Detail = 'Ejecuta la configuración de audio de Hardline (módulo Audio).'; Button = 'Encender'; Color = '#8B94A5'; Enabled = $false }
    }
    $detail = if ($null -ne $Intensity) { 'Intensidad {0} %' -f [int][Math]::Round($Intensity * 100) } else { 'Preset de Hardline' }
    if ($On) { return [pscustomobject]@{ State = 'Encendido'; Detail = "$detail. Se aplica al momento."; Button = 'Apagar'; Color = '#3FB950'; Enabled = $true } }
    return [pscustomobject]@{ State = 'Apagado'; Detail = "$detail. Ahora suena tal cual, sin corrección."; Button = 'Encender'; Color = '#8B94A5'; Enabled = $true }
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

# Nombre visible de cada nivel del compresor ("pasos" se llama Fuerte en el panel).
$script:HLDynamicsNames = @{ suave = 'Suave'; normal = 'Normal'; pasos = 'Fuerte'; rush = 'Rush' }

# Qué hace un nivel del compresor, en una frase que empieza en mayúscula.
function Get-HLDynamicsHint {
    param([string] $Mode)
    $d = ("$($script:HLDynamicsProfiles[$Mode])" -split ': ', 2)[-1]
    if (-not $d) { return '' }
    return $d.Substring(0, 1).ToUpper() + $d.Substring(1)
}

function Show-HLEqPanel {
    $r = New-HLWindow -Path (Join-Path $PSScriptRoot 'eq_panel.xaml') -Root $Root
    $w = $r.Window
    # Con la tarjeta de novedades abierta, que nunca pase del alto de la pantalla (hace scroll).
    $w.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
    $c = $r.Ui
    $brush = { param($hex) New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
    $xml = Join-Path $Root 'src\audio\configs\voicemeeter_comp.xml'
    $sw = Get-HLEqSwitchPath
    $view = @{ Busy = $false; Last = ''; PendingInt = $false }

    # --- Novedades y avisos sin ver, uno cada vez ---------------------------------
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

    # --- Compresor -------------------------------------------------------------
    # Se aplica 250 ms después del último movimiento: arrastrar de Suave a Rush no
    # manda tres perfiles seguidos a Voicemeeter.
    $modes = $script:HLDynamicsModes
    $showDyn = {
        $m = $modes[[int]$c.eqDynSlider.Value]
        $c.eqDynValue.Text = $script:HLDynamicsNames[$m]
        return $m
    }
    $dynDebounce = New-Object System.Windows.Threading.DispatcherTimer
    $dynDebounce.Interval = [TimeSpan]::FromMilliseconds(250)
    $applyDyn = {
        $dynDebounce.Stop()
        $mode = & $showDyn
        $st = Get-HLAudioSettings -Root $Root
        $desc = Get-HLDynamicsHint $mode
        try {
            $res = Set-HLVoicemeeterDynamics -XmlPath $xml -Mode $mode -PreampDb $st.PreampDb -Overrides $st.Overrides
            Save-HLAudioSettings -Root $Root -Set @{ Dynamics = $mode }
            $c.eqDynHint.Text = if ($res.Type -lt 3) { "$desc. Aplicado en parte: tu Voicemeeter no es Potato y solo acepta los mandos básicos." } else { "$desc. $($res.Values.Ratio):1 desde $($res.Values.Threshold) dB, recuperación $($res.Values.Release) ms, ganancia +$($res.Values.GainOut) dB." }
        } catch {
            Save-HLAudioSettings -Root $Root -Set @{ Dynamics = $mode }
            $c.eqDynHint.Text = "$desc. Guardado, pero no aplicado: $($_.Exception.Message) Se aplica cuando abras Voicemeeter y lo elijas de nuevo."
        }
    }
    $dynDebounce.Add_Tick({ & $applyDyn })
    $settings = Get-HLAudioSettings -Root $Root
    $view.Busy = $true
    $c.eqDynSlider.Value = [Math]::Max(0, [array]::IndexOf($modes, $settings.Dynamics))
    $view.Busy = $false
    [void](& $showDyn)
    $c.eqDynHint.Text = (Get-HLDynamicsHint $settings.Dynamics) + '.'
    $c.eqDynSlider.Add_ValueChanged({
            [void](& $showDyn)
            if (-not $view.Busy) { $dynDebounce.Stop(); $dynDebounce.Start() }
        })

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

    # Restablecer: preset completo (100 %) y compresor Normal.
    $c.eqReset.Add_Click({
            $c.eqIntSlider.Value = 100
            $c.eqDynSlider.Value = [array]::IndexOf($modes, 'normal')
        })

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
        # Apagado: el botón de encender destaca.
        $c.eqToggle.Style = if ($v.Enabled -and -not $on) { $w.FindResource('Primary') } else { $w.FindResource([System.Windows.Controls.Button]) }
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
            # Si se cierra justo después de mover un deslizador, se aplica igual.
            if ($view.PendingInt) { & $applyInt }
            if ($dynDebounce.IsEnabled) { & $applyDyn }
        })
    & $refresh
    [void]$w.ShowDialog()
}

if ($MyInvocation.InvocationName -ne '.') { Show-HLEqPanel }

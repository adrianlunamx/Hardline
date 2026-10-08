#Requires -Version 5.1
<#
    Hardline - carga de ventanas con el tema compartido.

    Cada .xaml de la interfaz lleva <!--HL:THEME--> dentro de sus recursos;
    aquí se sustituye por el contenido de theme.xaml antes de construir la
    ventana, de modo que las StaticResource del tema se resuelven al cargar.
    Se usa desde app.ps1, eq_panel.ps1, los tests y el CI.
#>

function Import-HLXaml {
    param([Parameter(Mandatory)] [string] $Path)
    $text = Get-Content $Path -Raw -Encoding UTF8
    $theme = Get-Content (Join-Path (Split-Path $Path -Parent) 'theme.xaml') -Raw -Encoding UTF8
    $open = $theme.IndexOf('>', $theme.IndexOf('<ResourceDictionary')) + 1
    $close = $theme.LastIndexOf('</ResourceDictionary>')
    $text = $text.Replace('<!--HL:THEME-->', $theme.Substring($open, $close - $open))
    return [xml]$text
}

# Nombres de los controles (fuera de plantillas: FindName no ve los de dentro).
function Get-HLXamlNames {
    param([Parameter(Mandatory)] [xml] $Xaml)
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    return @($Xaml.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])][not(ancestor::*[local-name()="DataTemplate"])]') |
            ForEach-Object { $_.GetAttribute('Name', $ns) } | Where-Object { $_ })
}

<#
    Construye la ventana. Devuelve @{ Window; Ui } con Ui[nombre] = control.
    Con -Root pone el icono de Hardline y la barra de título oscura.
#>
function New-HLWindow {
    param([Parameter(Mandatory)] [string] $Path, [string] $Root = '')
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $x = Import-HLXaml -Path $Path
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
    $ui = @{}
    foreach ($n in (Get-HLXamlNames -Xaml $x)) { $ui[$n] = $w.FindName($n) }
    if ($Root) { Set-HLWindowChrome -Window $w -Root $Root }
    return @{ Window = $w; Ui = $ui }
}

function Initialize-HLDwmApi {
    if ('Hardline.Dwm' -as [type]) { return }
    Add-Type -Namespace Hardline -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@
}

# Icono de Hardline y barra de título del color del fondo (Windows 11; en 10, solo oscura).
# Las ventanas las abre powershell.exe: sin un AppUserModelID propio, la barra de
# tareas las agrupa con PowerShell y muestra su icono.
function Set-HLWindowChrome {
    param([Parameter(Mandatory)] $Window, [Parameter(Mandatory)] [string] $Root)
    try {
        if (-not ('Hardline.Shell' -as [type])) {
            Add-Type -Namespace Hardline -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);'
        }
        [void][Hardline.Shell]::SetCurrentProcessExplicitAppUserModelID('Hardline.Warzone')
    } catch { Write-Verbose 'Sin AppUserModelID' }
    $ico = Join-Path $Root 'assets\hardline.ico'
    if (Test-Path $ico) {
        try { $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $ico)) } catch { Write-Verbose 'Sin icono' }
    }
    $Window.Add_SourceInitialized({
            param($s, $e)
            try {
                Initialize-HLDwmApi
                $h = (New-Object System.Windows.Interop.WindowInteropHelper $s).Handle
                $dark = 1; $caption = 0x00120D0B; $text = 0x00F6F1EE
                [void][Hardline.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$dark, 4)     # DWMWA_USE_IMMERSIVE_DARK_MODE
                [void][Hardline.Dwm]::DwmSetWindowAttribute($h, 35, [ref]$caption, 4)  # DWMWA_CAPTION_COLOR
                [void][Hardline.Dwm]::DwmSetWindowAttribute($h, 36, [ref]$text, 4)     # DWMWA_TEXT_COLOR
            } catch { Write-Verbose 'Barra de título por defecto' }
        })
}

#Requires -Version 5.1
<#
    Hardline - novedades en la interfaz (tarjeta de Hardline EQ y ventana
    "Novedades"). Los datos vienen de src\core\news.ps1; aquí solo se pintan.
    Necesita theme.ps1 y news.ps1 cargados.
#>

# Rellena $Panel con los puntos de una novedad: título en negrita y texto debajo.
function Add-HLNewsItems {
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] $Window, $Items)
    $Panel.Children.Clear()
    foreach ($it in @($Items)) {
        if (-not $it) { continue }
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,6,0,0'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 6; $dot.Height = 6; $dot.Margin = '0,7,10,0'; $dot.VerticalAlignment = 'Top'
        $dot.Fill = $Window.FindResource('Accent')
        [System.Windows.Controls.DockPanel]::SetDock($dot, 'Left')
        [void]$row.Children.Add($dot)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.TextWrapping = 'Wrap'
        $tb.LineHeight = 19
        $title = "$($it.title)"
        if ($title) {
            $b = New-Object System.Windows.Documents.Run ($title + '. ')
            $b.FontWeight = 'SemiBold'
            [void]$tb.Inlines.Add($b)
        }
        $t = New-Object System.Windows.Documents.Run "$($it.text)"
        $t.Foreground = $Window.FindResource('Muted')
        [void]$tb.Inlines.Add($t)
        [void]$row.Children.Add($tb)
        [void]$Panel.Children.Add($row)
    }
}

# Ventana con todas las novedades, de la más nueva a la más antigua.
function Show-HLNewsWindow {
    param([Parameter(Mandatory)] [string] $Root, $Owner = $null)
    $r = New-HLWindow -Path (Join-Path $Root 'src\gui\news.xaml') -Root $Root
    $w = $r.Window
    if ($Owner) { $w.Owner = $Owner } else { $w.WindowStartupLocation = 'CenterScreen' }
    $first = $true
    foreach ($rel in (Get-HLNews -Root $Root)) {
        $card = New-Object System.Windows.Controls.Border
        $card.Style = $w.FindResource('Card')
        $card.Margin = '0,0,0,12'
        $sp = New-Object System.Windows.Controls.StackPanel
        $head = New-Object System.Windows.Controls.StackPanel
        $head.Orientation = 'Horizontal'
        $chip = New-Object System.Windows.Controls.Border
        $chip.Style = $w.FindResource('Chip')
        if ($first) { $chip.Background = $w.FindResource('Accent') }
        $ct = New-Object System.Windows.Controls.TextBlock
        $ct.Text = "v$($rel.version)"; $ct.FontSize = 11; $ct.FontWeight = 'Bold'
        $ct.Foreground = $(if ($first) { [System.Windows.Media.Brushes]::White } else { $w.FindResource('Muted') })
        $chip.Child = $ct
        [void]$head.Children.Add($chip)
        $date = New-Object System.Windows.Controls.TextBlock
        $date.Text = "$($rel.date)"; $date.Style = $w.FindResource('Caption'); $date.Margin = '10,0,0,0'; $date.VerticalAlignment = 'Center'
        [void]$head.Children.Add($date)
        [void]$sp.Children.Add($head)
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = "$($rel.title)"; $title.Style = $w.FindResource('H2'); $title.Margin = '0,10,0,2'; $title.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($title)
        $items = New-Object System.Windows.Controls.StackPanel
        Add-HLNewsItems -Panel $items -Window $w -Items $rel.items
        [void]$sp.Children.Add($items)
        $card.Child = $sp
        [void]$r.Ui.newsList.Children.Add($card)
        $first = $false
    }
    $r.Ui.newsClose.Add_Click({ $w.Close() })
    [void]$w.ShowDialog()
}

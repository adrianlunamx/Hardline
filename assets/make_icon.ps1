#Requires -Version 5.1
<#
    Genera assets\hardline.ico a partir del diseño de assets\icon.svg (mismas
    coordenadas, viewBox 128x128), dibujado con System.Drawing en cada tamaño
    que usa Windows. Cada imagen va como PNG dentro del .ico (Windows Vista+).

        powershell -File assets\make_icon.ps1

    Si cambias icon.svg, cambia también las coordenadas de aquí.
#>
param([string] $Out = (Join-Path $PSScriptRoot 'hardline.ico'))

Add-Type -AssemblyName System.Drawing

function New-HLIconBitmap {
    param([int] $Size)
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = $Size / 128.0
    $g.ScaleTransform($s, $s)
    $c = { param($hex) [System.Drawing.ColorTranslator]::FromHtml($hex) }

    # Fondo redondeado (rx 28) con borde.
    $r = 28.0; $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc(1, 1, 2 * $r, 2 * $r, 180, 90); $p.AddArc(127 - 2 * $r, 1, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc(127 - 2 * $r, 127 - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc(1, 127 - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush (& $c '#0E1116')), $p)
    # En tamaños pequeños el borde de 2 unidades desaparece: mínimo 1 px.
    $g.DrawPath((New-Object System.Drawing.Pen (& $c '#2A313C'), ([Math]::Max(2.0, 1.0 / $s))), $p)

    # Señal (gris) que se aplana y sigue como línea naranja.
    $pts = @(18, 64, 26, 64, 30, 38, 35, 86, 40, 46, 45, 78, 50, 54, 54, 70, 58, 60, 62, 66, 66, 64)
    $wave = for ($i = 0; $i -lt $pts.Count; $i += 2) { New-Object System.Drawing.PointF ([single]$pts[$i]), ([single]$pts[$i + 1]) }
    $gray = New-Object System.Drawing.Pen (& $c '#5B6472'), ([single][Math]::Max(6.0, 1.2 / $s))
    $gray.StartCap = $gray.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $gray.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawLines($gray, [System.Drawing.PointF[]]$wave)
    $orange = New-Object System.Drawing.Pen (& $c '#FF5A1F'), ([single]10)
    $orange.StartCap = $orange.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($orange, 66, 64, 104, 64)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (& $c '#FF5A1F')), 95, 55, 18, 18)
    $g.Dispose()
    return $bmp
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$pngs = foreach ($sz in $sizes) {
    $bmp = New-HLIconBitmap -Size $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , $ms.ToArray()
}

# ICONDIR + ICONDIRENTRY por imagen + datos PNG.
$fs = [System.IO.File]::Create($Out)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]; $len = $pngs[$i].Length
    $w.Write([byte]$(if ($sz -ge 256) { 0 } else { $sz })); $w.Write([byte]$(if ($sz -ge 256) { 0 } else { $sz }))
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$len); $w.Write([uint32]$offset)
    $offset += $len
}
foreach ($png in $pngs) { $w.Write($png) }
$w.Close()
Write-Host "Icono: $Out ($($sizes -join ', ') px)"

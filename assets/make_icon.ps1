#Requires -Version 5.1
<#
    Genera assets\hardline.ico a partir de assets\icon.svg (monograma H),
    renderizado con VectorCraft (ArtCraft) en cada tamaño que usa Windows.
    Cada imagen va como PNG dentro del .ico (Windows Vista+).

        powershell -File assets\make_icon.ps1 [-Cli <ruta a vectorcraft-cli.exe>]

    Si cambias el logo, cambia mark() en make_logo.py, regenera icon.svg y
    vuelve a ejecutar esto.
#>
param(
    [string] $Out = (Join-Path $PSScriptRoot 'hardline.ico'),
    [string] $Cli = 'D:\Apps\artcraft\vectorcraft\vectorcraft-0.3.1-windows-x64-portable\vectorcraft-cli.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Cli)) { throw "No se encuentra vectorcraft-cli.exe en $Cli" }
$svg = Join-Path $PSScriptRoot 'icon.svg'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('hl_ico_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
try {
    $pngs = foreach ($sz in $sizes) {
        $png = Join-Path $tmp "$sz.png"
        # icon.svg mide 128: la escala da el tamaño exacto.
        $scale = ($sz / 128.0).ToString([Globalization.CultureInfo]::InvariantCulture)
        $res = & $Cli convert $svg $png --scale $scale 2>&1
        if ($LASTEXITCODE -or -not (Test-Path $png)) { throw "VectorCraft no pudo exportar $sz px: $res" }
        , [IO.File]::ReadAllBytes($png)
    }

    # ICONDIR + ICONDIRENTRY por imagen + datos PNG.
    $fs = [IO.File]::Create($Out)
    $w = New-Object IO.BinaryWriter $fs
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
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

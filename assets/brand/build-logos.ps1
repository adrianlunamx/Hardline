#Requires -Version 5.1
<#
    Hardline - logos con VectorCraft (ArtCraft).

    Abre cada concepto de assets\brand\concepts\*.svg en VectorCraft, aplica
    un resplandor exterior (Effect > Stylize > Outer Glow) a las piezas
    naranjas y exporta a assets\brand\vectorcraft\:
      <nombre>.vectorcraft  documento editable en VectorCraft
      <nombre>.svg          vectorial con el efecto
      <nombre>.png          1024 px

        powershell -File assets\brand\build-logos.ps1 [-Cli <ruta a vectorcraft-cli.exe>]
#>
param([string] $Cli = 'D:\Apps\artcraft\vectorcraft\vectorcraft-0.3.1-windows-x64-portable\vectorcraft-cli.exe')

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Cli)) { throw "No se encuentra vectorcraft-cli.exe en $Cli" }
$src = Join-Path $PSScriptRoot 'concepts'
$out = Join-Path $PSScriptRoot 'vectorcraft'
New-Item -ItemType Directory -Path $out -Force | Out-Null

# Naranja de la marca: relleno o trazo plano, o degradado lineal (el radial es el brillo de fondo).
# El fondo del icono (cuadrado de 480) nunca brilla aunque sea un degradado.
function Test-Accent {
    param($o)
    if ([double]$o.bounds.width -ge 470) { return $false }
    return ("$($o.fill)" -match '^#ff5a1f$|^Linear gradient$' -or "$($o.stroke)" -match '^#ff5a1f$|^Linear gradient$')
}
# Windows PowerShell 5.1 quita las comillas dobles de los argumentos de un .exe: hay que escaparlas.
function ConvertTo-HLNativeArg {
    param([string] $Json)
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return ($Json -replace '"', '\"') }
    return $Json
}
function Get-Leaves {
    param($node)
    foreach ($c in @($node.children)) { if ($c.children) { Get-Leaves $c } else { $c } }
}

$glow = '{"effect":"stylize.outerGlow","params":{"color":"#FF5A1F","blur":22,"opacity":65,"mode":"screen"}}'
foreach ($f in Get-ChildItem $src -Filter '*.svg' | Sort-Object Name) {
    $inspect = (& $Cli run --in $f.FullName --cmd document.inspect | Select-Object -Last 1) | ConvertFrom-Json
    $ids = @(foreach ($l in $inspect.result.layers) { Get-Leaves $l | Where-Object { Test-Accent $_ } | ForEach-Object { [int]$_.id } })
    $base = Join-Path $out $f.BaseName
    $cliArgs = @('run', '--in', $f.FullName)
    if ($ids.Count) {
        $sel = @{ ids = $ids } | ConvertTo-Json -Compress
        $cliArgs += @('--cmd', 'select.set', '--params', (ConvertTo-HLNativeArg $sel), '--cmd', 'effect.apply', '--params', (ConvertTo-HLNativeArg $glow), '--cmd', 'select.none')
    }
    $cliArgs += @('--export', "$base.vectorcraft", '--export', "$base.svg", '--export', "$base.png", '--scale', '2')
    $res = & $Cli @cliArgs 2>&1
    $bad = @($res | Where-Object { "$_" -match '"error"|vectorcraft-cli:' })
    if ($LASTEXITCODE -or $bad) { throw "$($f.Name): $($bad -join ' ')" }
    Write-Host ("{0}: resplandor en {1} piezas -> {2}.png/.svg/.vectorcraft" -f $f.Name, $ids.Count, $f.BaseName)
}

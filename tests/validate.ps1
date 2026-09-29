#Requires -Version 5.1
<#
    Hardline - validación del repositorio.

    No toca el sistema (salvo una clave temporal en HKCU:\Software\HardlineTest
    en Windows, que se borra al terminar). Se ejecuta en CI en cada push y
    antes de publicar una release.

        powershell -File tests\validate.ps1
        pwsh -File tests/validate.ps1          (Linux/macOS: omite los tests de registro)
#>
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script:fails = 0
$script:passes = 0

function Assert-True {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) {
        $script:passes++
        if (-not $Quiet) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    } else {
        $script:fails++
        Write-Host "  FAIL  $Name $Detail" -ForegroundColor Red
    }
}

function Join-HLPath { param([string[]]$Parts) return ($Parts -join [IO.Path]::DirectorySeparatorChar) }

$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Get-Variable IsWindows -ErrorAction SilentlyContinue) -and $IsWindows)

# ---------------------------------------------------------------------------
Write-Host "`n[1] Sintaxis PowerShell" -ForegroundColor Cyan
$scripts = Get-ChildItem -Path $root -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notmatch '[\\/](backups|reports|logs)[\\/]' }
foreach ($s in $scripts) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
    $detail = if ($errors) { ($errors | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ' } else { '' }
    Assert-True (-not $errors) "parse $($s.Name)" $detail
}

# ---------------------------------------------------------------------------
Write-Host "`n[2] Codificación" -ForegroundColor Cyan
foreach ($s in $scripts) {
    $bytes = [IO.File]::ReadAllBytes($s.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = [bool]($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1)
    if ($s.Name -eq 'install.ps1' -and $s.DirectoryName -eq $root) {
        Assert-True ((-not $nonAscii) -and (-not $hasBom)) 'install.ps1 es ASCII puro (irm | iex en PS 5.1)'
    } elseif ($nonAscii) {
        Assert-True $hasBom "$($s.Name) tiene BOM UTF-8 (PS 5.1 lee sin BOM como ANSI)"
    }
}

# ---------------------------------------------------------------------------
Write-Host "`n[3] headsets.json" -ForegroundColor Cyan
$jsonPath = Join-HLPath @($root, 'src', 'audio', 'profiles', 'headsets.json')
$db = $null
try { $db = [IO.File]::ReadAllText($jsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }
Assert-True ($null -ne $db) 'JSON válido'
if ($db) {
    $all = @($db.base) + @($db.headsets)
    $ids = @($all | ForEach-Object { $_.id })
    Assert-True ($ids.Count -eq ($ids | Select-Object -Unique).Count) 'ids únicos'
    Assert-True (@($db.headsets).Count -ge 6) 'al menos 6 headsets + genérico'
    foreach ($h in $all) {
        Assert-True ([bool]$h.name) "$($h.id): nombre"
        $filters = @($h.filters)
        Assert-True ($filters.Count -ge 5) "$($h.id): filtros"
        $badF = @($filters | Where-Object {
                $_.type -notin @('PK', 'LSC', 'HSC') -or [double]$_.fc -lt 20 -or [double]$_.fc -gt 20000 -or
                [double]$_.q -le 0 -or [math]::Abs([double]$_.gain) -gt 15 })
        Assert-True ($badF.Count -eq 0) "$($h.id): tipos/rangos de filtro"
        # El primer filtro corta graves: tiene que ser un shelf BAJO. Un HSC a
        # 100 Hz recortaría todo lo que hay por encima de 100 Hz.
        Assert-True ($filters[0].type -eq 'LSC' -and [double]$filters[0].gain -lt 0) "$($h.id): corte de graves es LSC"
        foreach ($pat in @($h.match)) {
            $okRx = $true
            try { [void][regex]::new($pat) } catch { $okRx = $false }
            Assert-True $okRx "$($h.id): regex '$pat'"
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host "`n[4] EQ: preamp y ausencia de clipping" -ForegroundColor Cyan
. (Join-HLPath @($root, 'src', 'core', 'common.ps1'))
. (Join-HLPath @($root, 'src', 'audio', 'eq.ps1'))
if ($db) {
    foreach ($h in (@($db.base) + @($db.headsets))) {
        $hp = Resolve-HLHeadsetProfile -Database $db -Id $h.id
        foreach ($k in @(1.0, 0.7)) {
            $f = @(Get-HLScaledFilters -Filters $hp.filters -Intensity $k)
            $pre = Get-HLAutoPreamp -Filters $f
            $peak = (Measure-HLFilterChain -Filters $f -Points 960).PeakDb
            Assert-True (($peak + $pre) -le -0.5) ("{0} x{1}: pico {2:N1} + preamp {3} <= -0.5 dB" -f $h.id, $k, $peak, $pre)
        }
    }
    # Respuesta conocida: un peak de +6 dB a 1 kHz da +6 dB exactos en 1 kHz.
    $c = Get-HLBiquad -Filter ([pscustomobject]@{ type = 'PK'; fc = 1000; gain = 6; q = 1 })
    $g = Get-HLBiquadGainDb -C $c -Freq 1000
    Assert-True ([math]::Abs($g - 6) -lt 0.01) ("biquad PK: +6 dB @ fc (obtenido {0:N3})" -f $g)
    $c = Get-HLBiquad -Filter ([pscustomobject]@{ type = 'LSC'; fc = 100; gain = -8; q = 0.7 })
    $gLow = Get-HLBiquadGainDb -C $c -Freq 20
    $gHigh = Get-HLBiquadGainDb -C $c -Freq 5000
    Assert-True ($gLow -lt -7 -and [math]::Abs($gHigh) -lt 0.2) ("LSC: -8 dB abajo ({0:N1}), 0 dB arriba ({1:N2})" -f $gLow, $gHigh)

    # El preset publicado debe coincidir con lo que genera el código.
    $shipped = Join-HLPath @($root, 'src', 'audio', 'configs', 'warzone_footsteps.txt')
    $gen = ConvertTo-HLEqApoText -HeadsetProfile (Resolve-HLHeadsetProfile -Database $db -Id 'generic') -Title 'Warzone footsteps (preset base)'
    $norm = { param($t) ($t -replace "`r`n", "`n").Trim() }
    Assert-True ((& $norm ([IO.File]::ReadAllText($shipped))) -eq (& $norm $gen)) 'warzone_footsteps.txt sincronizado con headsets.json'
}

# ---------------------------------------------------------------------------
Write-Host "`n[4b] AutoEq y archivos propios (sin red)" -ForegroundColor Cyan
. (Join-HLPath @($root, 'src', 'audio', 'autoeq.ps1'))
$sample = @(
    'Preamp: -6.4 dB'
    'Filter 1: ON LSC Fc 105 Hz Gain 4.1 dB Q 0.70'
    'Filter 2: ON PK Fc 170 Hz Gain -7.0 dB Q 1.06'
    'Filter 3: ON HSC Fc 10000 Hz Gain -7.0 dB Q 0.70'
    'Filter: ON PK Fc 3828 Hz Gain 5.4 dB Q 3.60'
    '# comentario'
    'Filter 5: OFF PK Fc 1000 Hz Gain 9 dB Q 1'
) -join "`n"
$parsed = @(ConvertFrom-HLEqApoFile -Text $sample)
Assert-True ($parsed.Count -eq 4) "parser ParametricEQ: 4 filtros ON (obtenido $($parsed.Count))"
Assert-True ($parsed[0].type -eq 'LSC' -and $parsed[0].fc -eq 105 -and $parsed[0].gain -eq 4.1 -and $parsed[0].q -eq 0.7) 'parser: valores con punto decimal'
Assert-True ($null -eq (ConvertFrom-HLEqApoFile -Text 'Preamp: -3 dB')) 'archivo sin filtros: se rechaza'

$indexText = @(
    '# Index'
    '- [HyperX Cloud II](./oratory1990/over-ear/HyperX%20Cloud%20II) by oratory1990'
    '- [HyperX Cloud II](./Rtings/HMS%20II.3%20over-ear/HyperX%20Cloud%20II) by Rtings on HMS II.3'
    '- [HyperX Cloud II Wireless](./Rtings/HMS%20II.3%20over-ear/HyperX%20Cloud%20II%20Wireless) by Rtings on HMS II.3'
    '- [Logitech G Pro X (3.5mm jack)](./Filk/over-ear/Logitech%20G%20Pro%20X%20(3.5mm%20jack)) by Filk'
    '- [Stax SR-Gamma Pro](./Innerfidelity/over-ear/Stax%20SR-Gamma%20Pro) by Innerfidelity'
    '- [SteelSeries Arctis Nova 7](./Rtings/HMS%20II.3%20over-ear/SteelSeries%20Arctis%20Nova%207) by Rtings on HMS II.3'
    '- [SteelSeries Arctis 7 2019 Edition](./Rtings/HMS%20II.3%20over-ear/SteelSeries%20Arctis%207%202019%20Edition) by Rtings on HMS II.3'
    '- [SteelSeries Arctis 7+](./Rtings/HMS%20II.3%20over-ear/SteelSeries%20Arctis%207+) by Rtings on HMS II.3'
    '- [Some IEM](./crinacle/711%20in-ear/Some%20IEM) by crinacle on 711'
) -join "`n"
$idx = @(ConvertFrom-HLAutoEqIndex -Text $indexText)
Assert-True ($idx.Count -eq 9) "índice AutoEq: 9 entradas (obtenido $($idx.Count))"
Assert-True ($idx[3].Path -eq 'Filk/over-ear/Logitech%20G%20Pro%20X%20(3.5mm%20jack)') 'índice: rutas con paréntesis'
$top = @(Search-HLAutoEq -Index $idx -Query 'hyperx cloud ii')
Assert-True ($top[0].Source -eq 'oratory1990' -and $top[0].Name -eq 'HyperX Cloud II') 'búsqueda: coincidencia exacta y mejor fuente primero'
Assert-True (@(Search-HLAutoEq -Index $idx -Query 'G Pro X' | Where-Object { $_.Name -like 'Stax*' }).Count -eq 0) 'búsqueda: "x" no coincide dentro de "Stax"'
Assert-True ((@(Search-HLAutoEq -Index $idx -Query 'SteelSeries Arctis 7'))[0].Name -eq 'SteelSeries Arctis 7 2019 Edition') 'búsqueda: frase contigua antes que "Arctis Nova 7" y "7+"'

if ($db) {
    $corr = [pscustomobject]@{ Name = 'Test'; Filters = $parsed; Source = 'test' }
    $hpC = Resolve-HLHeadsetProfile -Database $db -Id 'hyperx-cloud-ii' -Correction $corr
    Assert-True ($hpC.vmProfileId -eq 'hyperx-cloud-ii' -and $hpC.voicemeeter.comp_makeup_db -eq 8) 'con corrección: hereda Voicemeeter del modelo'
    Assert-True (@($hpC.filters).Count -eq @($db.base.filters).Count) 'con corrección: preset de pasos base'
    $chain = @(Get-HLChainFilters -HeadsetProfile $hpC)
    $peakC = (Measure-HLFilterChain -Filters $chain -Points 960).PeakDb
    $preC = Get-HLAutoPreamp -Filters $chain
    Assert-True (($peakC + $preC) -le -0.5) ("corrección + pasos: pico {0:N1} + preamp {1} <= -0.5 dB" -f $peakC, $preC)
    $txt = ConvertTo-HLEqApoText -HeadsetProfile $hpC -Title 't'
    Assert-True ($txt -match 'Correccion del headset' -and ([regex]::Matches($txt, '(?m)^Filter:')).Count -eq ($chain.Count)) 'texto EQ APO: corrección + pasos'
}

. (Join-HLPath @($root, 'src', 'modules', 'windows', 'platforms.ps1'))
$fakeHw = { param($p) [pscustomobject]@{ Game = [pscustomobject]@{ Primary = $p } } }
Assert-True ((Get-HLGamePlatform -Hardware (& $fakeHw 'D:\SteamLibrary\steamapps\common\Call of Duty HQ\cod.exe')) -eq 'steam') 'plataforma: Steam por ruta'
Assert-True ((Get-HLGamePlatform -Hardware (& $fakeHw 'C:\XboxGames\Call of Duty\Content\cod.exe')) -eq 'xbox') 'plataforma: Xbox por ruta'
Assert-True ((Get-HLGamePlatform -Hardware (& $fakeHw 'C:\Program Files (x86)\Call of Duty\_retail_\cod.exe')) -eq 'battlenet') 'plataforma: Battle.net por ruta'
$cat = @(Get-HLPlatformCatalog)
Assert-True (($cat | Where-Object { $_.Id -eq 'xbox' }).Services -notcontains 'XboxGipSvc') 'Xbox: XboxGipSvc (mandos) no se deshabilita'

# ---------------------------------------------------------------------------
Write-Host "`n[5] voicemeeter_comp.xml" -ForegroundColor Cyan
$xmlPath = Join-HLPath @($root, 'src', 'audio', 'configs', 'voicemeeter_comp.xml')
$xml = $null
try { [xml]$xml = Get-Content $xmlPath -Raw -Encoding UTF8 } catch { }
Assert-True ($null -ne $xml) 'XML válido'
if ($xml) {
    $c = $xml.HardlineVoicemeeter.Compressor
    Assert-True ([double]$c.ratio -ge 1 -and [double]$c.ratio -le 8) 'Comp.Ratio en 1..8'
    Assert-True ([double]$c.threshold_db -ge -40 -and [double]$c.threshold_db -le -3) 'Comp.Threshold en -40..-3'
    Assert-True ([double]$xml.HardlineVoicemeeter.Gate.threshold_db -ge -60) 'Gate.Threshold >= -60'
    . (Join-HLPath @($root, 'src', 'audio', 'voicemeeter.ps1'))
    $lines = @(New-HLVoicemeeterScript -XmlPath $xmlPath -HeadsetDevice 'Headphones (Test)' -Overrides $null -VoicemeeterType 3)
    Assert-True (@($lines | Where-Object { $_ -notmatch '^(Strip|Bus)\[\d\]\.[A-Za-z0-9.]+=("[^"]*"|-?[\d.]+);$' }).Count -eq 0) 'script Remote API bien formado'
    Assert-True ([bool]($lines -match '^Strip\[0\]\.Comp\.Ratio=4;$')) 'Comp.Ratio=4 generado'
}

# ---------------------------------------------------------------------------
Write-Host "`n[6] Editor de configuración de Warzone" -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("hl_test_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Initialize-HLSession -Root $tmp
    . (Join-HLPath @($root, 'src', 'modules', 'game', 'warzone.ps1'))
    $cst = Join-Path $tmp 'options.4.cod24.cst'
    $original = @(
        '// test'
        'TextureQuality@0;1;2 = "High" // one of [Very Low, Low, Normal, High]'
        'ParticleQuality@0;3;4 = "High" // one of [Low, High]'
        'BulletImpacts@0;5;6 = true // true or false'
        'ShadowQuality@0;7;8 = 3 // 0 to 4'
        'RendererWorkerCount@0;9;9 = -1 // -1 to 16'
        'UnknownSetting@0;1;1 = 42 // 0 to 100'
    ) -join "`r`n"
    [IO.File]::WriteAllText($cst, $original)
    $r = Update-HLCstFile -Path $cst -Rules (Get-HLWarzoneRules -PhysicalCores 6)
    $after = [IO.File]::ReadAllText($cst)
    Assert-True ($after -match 'TextureQuality@0;1;2 = "Normal" // one of') 'Texture -> Normal (con comillas)'
    Assert-True ($after -match 'ParticleQuality@0;3;4 = "Low"') 'Particle -> Low'
    Assert-True ($after -match 'BulletImpacts@0;5;6 = false // true or false') 'Bullet impacts -> false'
    Assert-True ($after -match 'ShadowQuality@0;7;8 = 0 // 0 to 4') 'Shadow -> mínimo del rango'
    Assert-True ($after -match 'RendererWorkerCount@0;9;9 = 6 ') 'RendererWorkerCount -> núcleos físicos'
    Assert-True ($after -match 'UnknownSetting@0;1;1 = 42') 'claves desconocidas intactas'
    Assert-True ($after.Contains("`r`n")) 'CRLF preservado'
    Assert-True ($r.Missing.Count -gt 0) 'ajustes ausentes reportados'

    # Rollback del archivo desde el manifiesto
    $m = Get-Content (Join-Path $HL.BackupDir 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($e in @($m.Entries | Sort-Object { [int]$_.Seq } -Descending)) { [void](Undo-HLManifestEntry -Entry $e) }
    Assert-True ([IO.File]::ReadAllText($cst) -eq $original) 'rollback restaura el archivo byte a byte'

    # Rango sin valor válido: no se inventa nada
    $p = ConvertFrom-HLCstLine 'RendererWorkerCount@0;1;1 = 4 // 1 to 3'
    Assert-True ($null -eq (Resolve-HLCstValue -Parsed $p -Target '6')) 'valor fuera de rango: no se escribe'

    # ---------------------------------------------------------------------------
    if ($onWindows) {
        Write-Host "`n[7] Registro: aplicar y revertir" -ForegroundColor Cyan
        $key = 'HKCU:\Software\HardlineTest'
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
        New-Item $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Existing' -Value 5 -PropertyType DWord -Force | Out-Null
        $HL.Manifest.Clear()
        [void](Set-HLRegistryValue -Path $key -Name 'Existing' -Value 1 -Type DWord)
        [void](Set-HLRegistryValue -Path $key -Name 'NewValue' -Value 'x' -Type String)
        [void](Set-HLRegistryValue -Path "$key\Sub" -Name 'Deep' -Value 1 -Type DWord)
        Assert-True ((Get-ItemProperty $key).Existing -eq 1) 'valor aplicado'
        $m = Get-Content (Join-Path $HL.BackupDir 'manifest.json') -Raw | ConvertFrom-Json
        foreach ($e in @($m.Entries | Where-Object { $_.Type -eq 'Registry' } | Sort-Object { [int]$_.Seq } -Descending)) { [void](Undo-HLManifestEntry -Entry $e) }
        $props = Get-ItemProperty $key
        Assert-True ($props.Existing -eq 5) 'valor previo restaurado'
        Assert-True (-not ($props.PSObject.Properties.Name -contains 'NewValue')) 'valor nuevo eliminado'
        Assert-True (-not (Test-Path "$key\Sub")) 'clave creada eliminada'
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Write-Host ''
$color = if ($script:fails -eq 0) { 'Green' } else { 'Red' }
Write-Host ("Resultado: {0} OK, {1} fallos" -f $script:passes, $script:fails) -ForegroundColor $color
exit ([int]($script:fails -gt 0))

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
    # Un BOM duplicado convierte la primera línea en un comando desconocido.
    if ($bytes.Length -ge 6 -and $bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF) {
        Assert-True $false "$($s.Name) sin BOM duplicado"
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
    $rx = ConvertFrom-HLCstLine 'NvidiaReflex@0;1;1 = "Disabled" // one of [Disabled, Enabled, Enabled + Boost]'
    $ra = ConvertFrom-HLCstLine 'AMDAntiLag2@0;1;1 = false // true or false'
    $rd = ConvertFrom-HLCstLine 'DisplayMode@0;1;1 = "Windowed" // one of [Windowed, Fullscreen Borderless Window, Fullscreen Exclusive]'
    $rn = ConvertFrom-HLCstLine 'ReflexLowLatency@0;1;1 = 0 // 0 to 2'
    Assert-True ((Resolve-HLCstValue -Parsed $rx -Target 'boost') -eq 'Enabled + Boost' -and (Resolve-HLCstValue -Parsed $ra -Target 'on') -eq 'true') 'latencia: Reflex + Boost y Anti-Lag 2 activados'
    Assert-True ((Resolve-HLCstValue -Parsed $rd -Target 'exclusive') -eq 'Fullscreen Exclusive' -and $null -eq (Resolve-HLCstValue -Parsed $rn -Target 'boost')) 'pantalla completa exclusiva (no la de ventana); rango numérico sin significado claro: no se toca'
    $nvRules = @(Get-HLWarzoneRules -PhysicalCores 6 -GpuVendor 'NVIDIA'); $amdRules = @(Get-HLWarzoneRules -PhysicalCores 6 -GpuVendor 'AMD')
    Assert-True (@($nvRules | Where-Object { $_.Label -eq 'NVIDIA Reflex' }).Count -eq 1 -and @($nvRules | Where-Object { $_.Label -match 'Anti-Lag' }).Count -eq 0 -and @($amdRules | Where-Object { $_.Label -match 'Anti-Lag' }).Count -eq 1) 'opción de baja latencia según el fabricante de la GPU'

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
Write-Host "`n[8] Versiones, releases y menú" -ForegroundColor Cyan
Assert-True ((Compare-HLVersion 'v1.10.0' '1.2.0') -eq 1 -and (Compare-HLVersion 'v1.2.0' '1.2.0') -eq 0 -and (Compare-HLVersion '1.1.9' '1.2.0') -eq -1) 'Compare-HLVersion (incluye 1.10 > 1.2)'
$wf = Get-Content (Join-HLPath @($root, '.github', 'workflows', 'release.yml')) -Raw
$inst = Get-Content (Join-HLPath @($root, 'install.ps1')) -Raw
Assert-True ($wf -match 'hardline-\$\{VERSION\}\.zip' -and $wf -match '\.zip\.sha256') 'release.yml publica hardline-X.zip + .sha256'
Assert-True ($inst.Contains("'^hardline-.*\.zip$'") -and $inst.Contains("'^hardline-.*\.zip\.sha256$'")) 'install.ps1 busca esos mismos nombres de asset'
# Un solo repositorio en todas partes: si el usuario de GitHub cambia, la redirección
# del nombre antiguo puede caducar y "irm | iex" acabaría descargando código ajeno.
$owner = [regex]::Match($inst, "\`$HLRepoOwner = '([^']+)'").Groups[1].Value
$name = [regex]::Match($inst, "\`$HLRepoName = '([^']+)'").Groups[1].Value
Assert-True ("$owner/$name" -eq $HLRepo) "install.ps1 y common.ps1 apuntan al mismo repo ($owner/$name)"
$docs = @('README.md', 'README.en.md', 'install.ps1', (Join-HLPath @('.github', 'ISSUE_TEMPLATE', 'config.yml')))
$stray = @(foreach ($d in $docs) {
        $txt = Get-Content (Join-Path $root $d) -Raw
        [regex]::Matches($txt, 'github(?:usercontent)?\.com/([A-Za-z0-9-]+)/Hardline') | Where-Object { $_.Groups[1].Value -ne $owner } | ForEach-Object { "$d -> $($_.Groups[1].Value)" }
    })
Assert-True ($stray.Count -eq 0) 'enlaces de README/instalador con el usuario actual' ($stray -join '; ')
$cl = Get-Content (Join-HLPath @($root, 'CHANGELOG.md')) -Raw
Assert-True ($cl -match ('## \[' + [regex]::Escape($HLVersion) + '\]')) "CHANGELOG tiene entrada para $HLVersion"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("hl_test_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Initialize-HLSession -Root $tmp -Unattended -NoBackup
    $menu = Read-HLChecklist -Title 't' -Items @(
        [pscustomobject]@{ Key = 'a'; Label = 'A'; Default = $true }
        [pscustomobject]@{ Key = 'b'; Label = 'B'; Default = $false }
    )
    Assert-True ($menu['a'] -eq $true -and $menu['b'] -eq $false) 'menú desatendido devuelve los valores por defecto'

    # -----------------------------------------------------------------------
    Write-Host "`n[9] Interruptor del EQ y test de pasos" -ForegroundColor Cyan
    . (Join-HLPath @($root, 'src', 'audio', 'eqswitch.ps1'))
    $sw = Join-Path $tmp 'switch.txt'
    [IO.File]::WriteAllText($sw, (New-HLEqSwitchText -PresetName 'warzone_footsteps_generic.txt' -On $true))
    Assert-True ((Get-HLEqState -SwitchPath $sw) -eq $true) 'switch recién creado: encendido'
    Set-HLEqState -On $false -SwitchPath $sw
    Assert-True ((Get-HLEqState -SwitchPath $sw) -eq $false -and (Get-Content $sw -Raw) -match '# OFF Include: warzone_footsteps_generic\.txt') 'apagar comenta el Include'
    Set-HLEqState -On $true -SwitchPath $sw
    Assert-True ((Get-HLEqState -SwitchPath $sw) -eq $true -and @(Get-Content $sw | Where-Object { $_ -match '^Include:' }).Count -eq 1) 'encender lo restaura (una sola línea Include)'
    Assert-True ($null -eq (Get-HLEqState -SwitchPath (Join-Path $tmp 'no-existe.txt'))) 'sin interruptor: $null'
    $vbs = [IO.File]::ReadAllBytes((Join-HLPath @($root, 'src', 'audio', 'eq_toggle.vbs')))
    Assert-True (-not [bool]($vbs | Where-Object { $_ -gt 127 } | Select-Object -First 1)) 'eq_toggle.vbs es ASCII (WScript no lee UTF-8)'

    $wav = Join-Path $tmp 'steps.wav'
    & (Join-HLPath @($root, 'src', 'audio', 'footstep_test.ps1')) -SaveWav $wav | Out-Null
    $pcm = [Hardline.FootstepTest]::Render(48000)
    Assert-True ($pcm.Length -eq [int](5.2 * 48000) * 2) 'test de pasos: 5.2 s estéreo a 48 kHz'
    $sumL = 0.0; $sumR = 0.0
    for ($i = [int](0.3 * 48000); $i -lt [int](0.45 * 48000); $i++) { $sumL += [math]::Abs($pcm[2 * $i]); $sumR += [math]::Abs($pcm[2 * $i + 1]) }
    Assert-True ($sumL -gt 2 * $sumR) 'test de pasos: los pasos suenan a la izquierda'
    $peak = ($pcm | ForEach-Object { [math]::Abs([int]$_) } | Measure-Object -Maximum).Maximum
    Assert-True ($peak -le 16500 -and $peak -gt 8000) "test de pasos: pico ~-6 dBFS (margen para el EQ) ($peak)"
    Assert-True ((Test-Path $wav) -and (Get-Item $wav).Length -gt 900000) 'test de pasos: exporta WAV'

    # -----------------------------------------------------------------------
    Write-Host "`n[10] Modo partida" -ForegroundColor Cyan
    $gsDefault = Join-HLPath @($root, 'src', 'modules', 'windows', 'configs', 'gamesession.default.json')
    $gs = Get-Content $gsDefault -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ((@($gs.process) -contains 'cod') -and $gs.poll_seconds -ge 2 -and @($gs.close_processes).Count -eq 0) 'config por defecto: cod, sondeo >= 2 s, no cierra nada'
    Assert-True (@($gs.lower_priority | Where-Object { $_ -match '^(cod|Discord)$' }).Count -eq 0) 'no baja la prioridad del juego ni de Discord'
    # Recuperación de una sesión interrumpida: el estado pendiente se aplica y se borra.
    $gsRoot = Join-Path $tmp 'gs'
    New-Item -ItemType Directory -Path (Join-Path $gsRoot 'config'), (Join-Path $gsRoot 'logs') -Force | Out-Null
    '{ "process": ["hardline-no-existe"], "poll_seconds": 2, "pause_services": [], "lower_priority": [], "close_processes": [], "power_plan": false }' |
        Set-Content (Join-Path $gsRoot 'config\gamesession.json')
    '{ "Started": "2026-01-01T00:00:00", "Game": "cod", "Services": [], "Priorities": [ { "Id": "999999", "Name": "x", "Start": "2026-01-01T00:00:00.0000000", "Original": "Normal" } ], "PrevScheme": null }' |
        Set-Content (Join-Path $gsRoot 'config\gamesession.state.json')
    & (Join-HLPath @($root, 'src', 'modules', 'windows', 'gamesession_watcher.ps1')) -Root $gsRoot -RestoreOnly
    Assert-True (-not (Test-Path (Join-Path $gsRoot 'config\gamesession.state.json'))) 'sesión interrumpida: restaurada y estado borrado'
    Assert-True ((Get-Content (Join-Path $gsRoot 'logs\gamesession.log') -Raw) -match 'interrumpida') 'sesión interrumpida: queda en el log'

    # -----------------------------------------------------------------------
    Write-Host "`n[11] GPU y reporte HTML" -ForegroundColor Cyan
    . (Join-HLPath @($root, 'src', 'modules', 'gpu', 'shared.ps1'))
    Assert-True ((ConvertTo-HLNvidiaDriverVersion '32.0.15.6094') -eq '560.94' -and (ConvertTo-HLNvidiaDriverVersion '27.21.14.5671') -eq '456.71') 'versión de driver NVIDIA desde la de Windows'
    Assert-True ($null -eq (ConvertTo-HLNvidiaDriverVersion 'raro')) 'versión NVIDIA no reconocible: $null'

    . (Join-HLPath @($root, 'src', 'core', 'benchmarker.ps1'))
    . (Join-HLPath @($root, 'src', 'core', 'report.ps1'))
    Initialize-HLSession -Root $tmp -Unattended
    Add-HLResult -Module 'Audio' -Item 'x' -Status Failed -Detail '<script>alert(1)</script> & co'
    Add-HLManualStep 'BIOS' 'Paso de prueba' 'https://example.com/?a=1&b=2'
    $mk = { param($t) [pscustomobject]@{ Timer = [pscustomobject]@{ TimerResMs = $t; Sleep1AvgMs = $t; Sleep1P99Ms = $t }; PingCf = $null; DnsMs = 10; Capture = $null } }
    $HL.BenchPre = & $mk 15.6; $HL.BenchPost = & $mk 0.5
    $fakeHw2 = [pscustomobject]@{
        CPU = [pscustomobject]@{ Name = 'CPU X'; Cores = 6; Threads = 12; Family = 'Zen4' }
        GPU = [pscustomobject]@{ Primary = [pscustomobject]@{ Name = 'GPU Y'; VRAMGB = 8; DriverVersion = '1' } }
        RAM = [pscustomobject]@{ TotalGB = 32; Type = 'DDR5'; SpeedMTs = 6000; Profile = 'Activo' }
        Storage = [pscustomobject]@{ SystemBus = 'NVMe'; SystemModel = 'Z' }
        Board = [pscustomobject]@{ Vendor = 'MSI'; Product = 'B650'; BiosVersion = '1' }
        OS = [pscustomobject]@{ Caption = 'Windows 11'; Build = 26100 }
        Game = [pscustomobject]@{ Primary = $null }
    }
    $html = Get-Content (Write-HLReportHtml -Hardware $fakeHw2) -Raw
    Assert-True ($html -match '<th>CPU</th><td>CPU X \(6C/12T, Zen4\)</td>') 'reporte HTML: fila de hardware completa'
    Assert-True ($html -notmatch '<script>alert' -and $html -match '&lt;script&gt;') 'reporte HTML: texto escapado'
    Assert-True ($html -match 'class="better">-97%') 'reporte HTML: mejora marcada en verde'

    # -----------------------------------------------------------------------
    Write-Host "`n[12] Interfaz gráfica" -ForegroundColor Cyan
    [xml]$gx = Get-Content (Join-HLPath @($root, 'src', 'gui', 'main.xaml')) -Raw -Encoding UTF8
    Assert-True ($null -ne $gx.Window) 'main.xaml es XML válido con <Window>'
    $xns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $xamlNames = @($gx.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])]') | ForEach-Object { $_.GetAttribute('Name', $xns) } | Where-Object { $_ })
    $appSrc = Get-Content (Join-HLPath @($root, 'src', 'gui', 'app.ps1')) -Raw
    $used = @(([regex]::Matches($appSrc, '\$ui\.(\w+)') | ForEach-Object { $_.Groups[1].Value }) +
        ([regex]::Matches($appSrc, "'((?:btn|txt|cmb|chk|prg)\w+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique)
    $missing = @($used | Where-Object { $_ -notin $xamlNames })
    Assert-True ($missing.Count -eq 0) 'todo control usado en app.ps1 existe en main.xaml' ($missing -join ', ')

    . (Join-HLPath @($root, 'src', 'gui', 'app.ps1')) -Root $root
    $state = @{ Windows = $true; Platforms = $false; Session = $true; Latency = $true; Network = $true; NetDiag = $false; Game = $true; Controller = $false; Display = $false
        Audio = $true; Bench = $false; Experimental = $true; Platform = 'steam'; DisableOthers = $true; Headset = "Kraken V3 o'brien"
        AudioMode = 'EqOnly'; Intensity = '0.7' }
    $guiArgs = @(ConvertTo-HLGuiArguments -State $state -DryRun)
    $instAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-HLPath @($root, 'install.ps1')), [ref]$null, [ref]$null)
    $instParams = @($instAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $unknown = @($guiArgs | Where-Object { $_ -match '^-[A-Za-z]+$' } | ForEach-Object { $_.Substring(1) } | Where-Object { $_ -notin $instParams })
    Assert-True ($unknown.Count -eq 0) 'la GUI solo pasa parámetros que install.ps1 acepta' ($unknown -join ', ')
    Assert-True (($guiArgs -contains '-SkipPlatforms') -and ($guiArgs -contains '-SkipNetDiag') -and ($guiArgs -contains '-SkipBenchmark') -and ($guiArgs -contains '-SkipController') -and ($guiArgs -contains '-SkipDisplay') -and -not ($guiArgs -contains '-SkipWindows')) 'casillas desmarcadas -> -Skip* correctos'
    Assert-True (($guiArgs -join ' ') -match '-Unattended' -and ($guiArgs -join ' ') -match '-DryRun' -and ($guiArgs -join ' ') -match '-GameSession Yes') 'GUI: desatendido, DryRun y modo partida'
    $cmdLine = ConvertTo-HLCommandLine -Script 'C:\Users\a b\Hardline\install.ps1' -Arguments $guiArgs
    $cmdErr = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($cmdLine, [ref]$null, [ref]$cmdErr)
    Assert-True (-not $cmdErr -and $cmdLine -match "'Kraken V3 o''brien'") 'línea de comandos de la GUI: comillas y espacios bien escapados'
    $state.Audio = $false
    Assert-True (-not ((ConvertTo-HLGuiArguments -State $state) -contains '-Headset')) 'sin audio no se pasan opciones de audio'

    # -----------------------------------------------------------------------
    Write-Host "`n[13] Diagnóstico de red y latencia" -ForegroundColor Cyan
    . (Join-HLPath @($root, 'src', 'modules', 'network', 'diagnose.ps1'))
    $st = Get-HLPingStats -Rtts @(10, 12, 11, 30, 10) -Lost 1 -Target 'x'
    Assert-True ($st.LossPct -eq 16.7 -and $st.MedianMs -eq 11 -and $st.P95Ms -eq 30 -and $st.JitterMs -eq 10.5) 'estadísticas de ping (pérdida, mediana, p95, jitter)'
    Assert-True ((Get-HLPingStats -Rtts @() -Lost 5).LossPct -eq 100) 'sin respuestas: 100% de pérdida'
    Assert-True (((0, 4.9, 20, 45, 150, 300, 500 | ForEach-Object { Get-HLBufferbloatGrade $_ }) -join ',') -eq 'A+,A+,A,B,C,D,F') 'notas de bufferbloat (escala waveform)'
    $diagBad = [pscustomobject]@{ Wireless = $true; Gateway = [pscustomobject]@{ LossPct = 0 }; Internet = [pscustomobject]@{ LossPct = 2; JitterMs = 9 }
        Bufferbloat = [pscustomobject]@{ Grade = 'C'; AddedMs = 120 }; Mtu = 1420 }
    $fb = @(Get-HLNetFindings -Diag $diagBad)
    Assert-True ((@($fb | Where-Object { $_.Title -eq 'Pérdida en Internet' -and $_.Severity -eq 'bad' }).Count -eq 1)) 'pérdida solo hacia Internet: culpa del proveedor'
    $diagLocal = [pscustomobject]@{ Wireless = $false; Gateway = [pscustomobject]@{ LossPct = 3 }; Internet = [pscustomobject]@{ LossPct = 3; JitterMs = 2 }; Bufferbloat = $null; Mtu = 1500 }
    $fl = @(Get-HLNetFindings -Diag $diagLocal)
    Assert-True ((@($fl | Where-Object { $_.Title -eq 'Pérdida en tu red local' }).Count -eq 1) -and (@($fl | Where-Object { $_.Title -eq 'Pérdida en Internet' }).Count -eq 0)) 'pérdida ya en el router: red local, no proveedor'
    Assert-True ((@($fb | Where-Object { $_.Title -eq 'Wi-Fi' }).Count -eq 1) -and (@($fb | Where-Object { $_.Title -eq 'Bufferbloat' -and $_.Severity -eq 'bad' }).Count -eq 1)) 'Wi-Fi y bufferbloat C marcados'

    $latSrc = Get-Content (Join-HLPath @($root, 'src', 'modules', 'windows', 'latency.ps1')) -Raw
    Assert-True ($latSrc -match "DEVPKEY_PciDevice_InterruptSupport" -and $latSrc -match '-band 6') 'modo MSI solo si el hardware declara soporte MSI/MSI-X'
    $expSrc = Get-Content (Join-HLPath @($root, 'src', 'modules', 'windows', 'experimental.ps1')) -Raw
    Assert-True ($expSrc -match 'Test-HLBitLocker' -and $expSrc -match "Type 'Bcd'") 'disabledynamictick: comprueba BitLocker y queda en el manifiesto'
    Assert-True ($inst -match "Key = 'exp';\s+Label = '[^']*';\s+Default = \`$false") 'experimental desmarcado por defecto en el menú'

    # -----------------------------------------------------------------------
    Write-Host "`n[14] Mando" -ForegroundColor Cyan
    . (Join-HLPath @($root, 'src', 'modules', 'input', 'controller.ps1'))
    $fakePnp = @(
        [pscustomobject]@{ FriendlyName = 'Xbox Controller'; InstanceId = 'USB\VID_045E&PID_0B12\3033363030'; Class = 'XnaComposite' }
        [pscustomobject]@{ FriendlyName = 'HID-compliant game controller'; InstanceId = 'HID\VID_045E&PID_0B12&IG_00\8&2A1B&0&0000'; Class = 'HIDClass' }
        [pscustomobject]@{ FriendlyName = 'HID-compliant game controller'; InstanceId = 'HID\{00001124-0000-1000-8000-00805f9b34fb}_VID&0002054c_PID&0ce6&Col01\9&1&0'; Class = 'HIDClass' }
        [pscustomobject]@{ FriendlyName = 'HID-compliant mouse'; InstanceId = 'HID\VID_045E&PID_0823&MI_00\7&1&0'; Class = 'HIDClass' }
        [pscustomobject]@{ FriendlyName = 'Xbox Wireless Adapter for Windows'; InstanceId = 'USB\VID_045E&PID_02FE\1'; Class = 'USB' }
        [pscustomobject]@{ FriendlyName = 'USB Input Device'; InstanceId = 'USB\VID_1234&PID_5678\1'; Class = 'HIDClass' }
    )
    $pads = @(Get-HLControllerFromPnp -Devices $fakePnp)
    $xbox = @($pads | Where-Object { $_.Vid -eq '045E' })
    $ds = @($pads | Where-Object { $_.Vid -eq '054C' })
    Assert-True ($pads.Count -eq 2) 'mandos: 2 físicos de 6 nodos (ratón, adaptador y otros fuera)' ("$($pads.Count): " + (($pads | ForEach-Object { $_.Name }) -join '; '))
    Assert-True ($xbox.Count -eq 1 -and $xbox[0].Connection -eq 'USB' -and $xbox[0].InstanceId -like 'USB\*') 'Xbox por USB: nodos USB/HID unidos, se queda el nodo USB'
    Assert-True ($ds.Count -eq 1 -and $ds[0].Connection -eq 'Bluetooth' -and $ds[0].PlayStation -and $ds[0].Brand -eq 'Sony (PlayStation)') 'DualSense por Bluetooth: VID desde VID&0002054c'
    $czRules = @(Get-HLWarzoneControllerRules)
    Assert-True ($czRules.Count -ge 3 -and @($czRules | Where-Object { $_.Target -eq '0' -and $_.Label -match 'gatillos' }).Count -eq 1) 'reglas de Warzone: zona muerta de gatillos 0'
    $ctlSrc = Get-Content (Join-HLPath @($root, 'src', 'modules', 'input', 'controller.ps1')) -Raw
    Assert-True ($ctlSrc -match 'Set-HLRegistryValue' -and $ctlSrc -notmatch 'pnputil|devcon|bcdedit') 'energía USB por Set-HLRegistryValue (revertible), sin instalar drivers ni modo de prueba'

    . (Join-HLPath @($root, 'src', 'modules', 'input', 'controller_test.ps1'))
    Assert-True ((ConvertFrom-HLXInputAxis 32767) -eq 1 -and (ConvertFrom-HLXInputAxis -32768) -eq -1 -and (ConvertFrom-HLXInputAxis 0) -eq 0) 'eje XInput normalizado a -1..1'
    Assert-True ((ConvertFrom-HLRawAxis 0.5) -eq 0 -and (ConvertFrom-HLRawAxis 1) -eq 1 -and (ConvertFrom-HLRawAxis 0.25) -eq -0.5) 'eje Windows.Gaming.Input normalizado a -1..1'
    $rest = Measure-HLStickRest -X @(0.03, 0.04, 0.03) -Y @(0.0, 0.03, 0.0)
    Assert-True ($rest.Samples -eq 3 -and $rest.MaxRadius -eq 0.05 -and $rest.Offset -gt 0.03 -and $rest.Offset -lt 0.04) 'drift en reposo: radio máximo y descentrado'
    $dz5 = Get-HLRecommendedDeadzone -MaxRadius 0.05
    $dz0 = Get-HLRecommendedDeadzone -MaxRadius 0
    $dzW = Get-HLRecommendedDeadzone -MaxRadius 0.4
    Assert-True ($dz5.Percent -eq 7 -and -not $dz5.Worn -and $dz0.Percent -eq 2 -and $dzW.Percent -eq 30 -and $dzW.Worn) 'zona muerta: drift + 2, mínimo 2, tope 30 y aviso de desgaste'
    $ts = @(0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 40.0)
    $rs = Get-HLRateStats -TimestampsMs $ts
    Assert-True ($rs.Hz -eq 250 -and $rs.MedianMs -eq 4 -and $rs.MaxMs -eq 16 -and $rs.Updates -eq 8) 'tasa de actualización: mediana de intervalos (un hueco no la falsea)'
    Assert-True ((Get-HLRateStats -TimestampsMs @(1.0)).Hz -eq 0 -and (Get-HLRateVerdict -Stats (Get-HLRateStats -TimestampsMs @())) -match 'Sin datos') 'sin estados nuevos: sin datos, sin división por cero'
    Assert-True ((Get-HLRateVerdict -Stats $rs) -match '^Buena') 'veredicto de 250 Hz'

    $optSrc = Get-Content (Join-HLPath @($root, 'src', 'core', 'optimizer.ps1')) -Raw
    Assert-True ($optSrc -match "modules\\input\\controller\.ps1" -and $optSrc -match 'Invoke-HLController' -and $optSrc -match 'SkipController') 'el orquestador carga y ejecuta el módulo de mando'
    Assert-True ($inst -match "Key = 'controller'" -and $inst -match 'controller_test\.ps1' -and 'SkipController' -in $instParams -and 'ControllerTestOnly' -in $instParams) 'install.ps1: menú, -SkipController y -ControllerTestOnly'
    Assert-True ($appSrc -match 'controller_test\.ps1' -and 'chkController' -in $xamlNames -and 'btnControllerTest' -in $xamlNames) 'interfaz: casilla de mando y botón de test'

    # -----------------------------------------------------------------------
    Write-Host "`n[15] Pantalla y medición de partida" -ForegroundColor Cyan
    . (Join-HLPath @($root, 'src', 'modules', 'windows', 'display.ps1'))
    $modes = @(
        [pscustomobject]@{ Width = 2560; Height = 1440; Hz = 60;  Bpp = 32; Flags = 0 }
        [pscustomobject]@{ Width = 2560; Height = 1440; Hz = 144; Bpp = 32; Flags = 0 }
        [pscustomobject]@{ Width = 2560; Height = 1440; Hz = 165; Bpp = 32; Flags = 0 }
        [pscustomobject]@{ Width = 2560; Height = 1440; Hz = 200; Bpp = 32; Flags = 2 }
        [pscustomobject]@{ Width = 2560; Height = 1440; Hz = 180; Bpp = 16; Flags = 0 }
        [pscustomobject]@{ Width = 1920; Height = 1080; Hz = 240; Bpp = 32; Flags = 0 }
    )
    Assert-True ((Get-HLBestRefresh -Modes $modes -Width 2560 -Height 1440) -eq 165) 'refresco máximo a la resolución actual (sin entrelazados ni 16 bits)'
    Assert-True ((Test-HLRefreshUpgrade -CurrentHz 60 -BestHz 165) -and -not (Test-HLRefreshUpgrade -CurrentHz 59 -BestHz 60) -and -not (Test-HLRefreshUpgrade -CurrentHz 165 -BestHz 165)) 'solo se sube el refresco si la diferencia es real (59 -> 60 no)'
    Assert-True ((Get-HLFpsCap -Hz 165) -eq 162 -and (Get-HLFpsCap -Hz 0) -eq 0) 'límite de FPS VRR: refresco - 3'
    $dx = Merge-HLDxSettings -Current 'AutoHDREnable=1;SwapEffectUpgradeEnable=0;' -Set @{ SwapEffectUpgradeEnable = '1'; VRROptimizeEnable = '1' }
    Assert-True ($dx -match '^AutoHDREnable=1;' -and $dx -match 'SwapEffectUpgradeEnable=1;' -and $dx -match 'VRROptimizeEnable=1;' -and $dx -notmatch 'SwapEffectUpgradeEnable=0') 'DirectXUserGlobalSettings: cambia solo lo pedido y conserva Auto HDR'
    Assert-True ((Merge-HLDxSettings -Current $null -Set @{ VRROptimizeEnable = '1' }) -eq 'VRROptimizeEnable=1;') 'DirectXUserGlobalSettings vacío'
    $ov = @(Get-HLOverlayMatches -ProcessNames @('explorer', 'Discord', 'discord', 'RTSS', 'wallpaper64', 'Wallpaper32'))
    Assert-True ($ov.Count -eq 3 -and @($ov | Where-Object { $_.Name -eq 'Wallpaper Engine' }).Count -eq 1) 'overlays detectados por proceso, sin duplicados'
    $comSrc = Get-Content (Join-HLPath @($root, 'src', 'core', 'common.ps1')) -Raw
    $dispSrc = Get-Content (Join-HLPath @($root, 'src', 'modules', 'windows', 'display.ps1')) -Raw
    Assert-True ($dispSrc -match "Type 'DisplayMode'" -and $comSrc -match "'DisplayMode' \{" -and $dispSrc -match 'CDS_TEST') 'cambio de refresco: probado antes de aplicar y revertible'

    . (Join-HLPath @($root, 'src', 'modules', 'game', 'gameplay_bench.ps1')) -Root $root
    $ft = [double[]]@(@(1..980 | ForEach-Object { 6.0 }) + @(1..20 | ForEach-Object { 20.0 }))
    $gs = Get-HLFrameStats -FrameTimesMs $ft
    Assert-True ($gs.Frames -eq 1000 -and $gs.AvgFps -eq 159.2 -and $gs.Low1Fps -eq 50 -and $gs.MedianMs -eq 6 -and $gs.StutterPct -eq 2) 'estadística de frames: FPS medios por tiempo, 1% lows, tirones'
    Assert-True ($null -eq (Get-HLFrameStats -FrameTimesMs @(5, 6, 7))) 'muy pocos frames: sin resultado'
    $gs2 = Get-HLFrameStats -FrameTimesMs ([double[]]@(1..1000 | ForEach-Object { 6.0 }))
    $cmp = @(Compare-HLFrameStats -Before $gs -After $gs2)
    $c1 = $cmp | Where-Object { $_.Label -eq '1% lows' }; $cAvg = $cmp | Where-Object { $_.Label -eq 'FPS medios' }; $cSt = $cmp | Where-Object { $_.Label -eq 'Tirones (%)' }
    Assert-True ($c1.Better -eq 1 -and $cAvg.Better -eq 1 -and $cSt.Better -eq 1 -and $cmp.Count -eq 4) 'comparación: mejoras marcadas; sin latencia no hay fila de latencia'
    Assert-True ((Get-HLGameplayVerdict -Rows $cmp) -match '^Mejora real' -and (Get-HLGameplayVerdict -Rows @(Compare-HLFrameStats -Before $gs2 -After $gs)) -match '^Peor') 'veredicto antes/después'
    $same = @(Compare-HLFrameStats -Before $gs2 -After $gs2)
    Assert-True ((Get-HLGameplayVerdict -Rows $same) -match '^Sin diferencia' -and @($same | Where-Object { $_.Better -ne 0 }).Count -eq 0) 'misma partida: dentro del ruido'
    $pmRows = @(
        [pscustomobject]@{ Application = 'cod.exe'; FrameTime = '6.5'; DisplayLatency = '18.2' }
        [pscustomobject]@{ Application = 'Discord.exe'; FrameTime = '16.6'; DisplayLatency = '30' }
        [pscustomobject]@{ Application = 'cod.exe'; FrameTime = 'NA'; DisplayLatency = '17.8' }
    )
    $pm = ConvertFrom-HLPresentMonRows -Rows $pmRows
    $pm1 = ConvertFrom-HLPresentMonRows -Rows @([pscustomobject]@{ Application = 'cod.exe'; MsBetweenPresents = '7.25' })
    Assert-True ($pm.FrameTimes.Count -eq 1 -and $pm.FrameTimes[0] -eq 6.5 -and $pm.Latency.Count -eq 2 -and $pm1.FrameTimes[0] -eq 7.25) 'CSV de PresentMon 2.x y 1.x, solo cod.exe, valores no numéricos fuera'
    $assets = @([pscustomobject]@{ name = 'PresentMon-2.3.0-x64-DLSS4.exe' }, [pscustomobject]@{ name = 'PresentMon-2.3.0.msi' }, [pscustomobject]@{ name = 'PresentMon-2.3.0-x64.exe' })
    Assert-True ((Select-HLPresentMonAsset -Assets $assets)[0].name -eq 'PresentMon-2.3.0-x64.exe') 'PresentMon: se elige el ejecutable de consola x64'
    $a2 = Get-HLPresentMonArgs -Csv 'C:\t\a b.csv' -Seconds 60 -Syntax 2; $a1 = Get-HLPresentMonArgs -Csv 'x.csv' -Seconds 60 -Syntax 1
    Assert-True (($a2 -contains '--terminate_after_timed') -and ($a2 -contains '"C:\t\a b.csv"') -and ($a1 -contains '-process_name') -and ($a1 -contains '-no_top')) 'argumentos de PresentMon 2.x y 1.x'
    $gbSrc = Get-Content (Join-HLPath @($root, 'src', 'modules', 'game', 'gameplay_bench.ps1')) -Raw
    Assert-True ($gbSrc -match 'Get-AuthenticodeSignature' -and $gbSrc -match "'Intel'" -and $gbSrc -match 'sha256:') 'PresentMon: SHA256 de GitHub y firma de Intel antes de ejecutar'
    Assert-True ($optSrc -match "modules\\windows\\display\.ps1" -and $optSrc -match 'Invoke-HLDisplay' -and 'SkipDisplay' -in $instParams -and 'GameplayBenchOnly' -in $instParams -and $inst -match "Key = 'display'") 'pantalla y medición integradas en orquestador e instalador'
    Assert-True ('chkDisplay' -in $xamlNames -and 'btnGameplay' -in $xamlNames -and $appSrc -match 'gameplay_bench\.ps1') 'interfaz: casilla de pantalla y botón Medir partida'
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Write-Host ''
$color = if ($script:fails -eq 0) { 'Green' } else { 'Red' }
Write-Host ("Resultado: {0} OK, {1} fallos" -f $script:passes, $script:fails) -ForegroundColor $color
exit ([int]($script:fails -gt 0))

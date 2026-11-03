#Requires -Version 5.1
<#
    Hardline - configuración de Warzone.

    Dónde guarda COD la configuración (Get-HLWarzoneConfigFiles, detector.ps1):
      %LOCALAPPDATA%\Activision\Call of Duty\players\s.1.0.cod<NN>.txt          (actual)
      %LOCALAPPDATA%\Activision\Call of Duty\players\<cuenta>\g.cod<NN>.*.txt
      Documents\Call of Duty\players\options.<n>.cod<año>.cst   (temporadas anteriores)
      Documents\Call of Duty\players\adv_options.ini            (Warzone 1 / MW2019)

    Todos usan una línea por ajuste:
      Nombre@<ids> = valor // one of [Low, Normal, High]
      Nombre@<ids> = Low Quality // one of Off, Low Quality, High Quality
      Nombre@<ids> = 3     // 0 to 6
    Los nombres cambian entre temporadas. Por eso Hardline:
      1. Busca cada ajuste por una lista de nombres candidatos.
      2. Solo modifica claves que YA existen en tu archivo.
      3. Elige el valor a partir del comentario del propio archivo (lista de
         opciones o rango), nunca inventa un valor que el juego no acepte.
      4. Informa qué ajustes no encontró, para que los pongas a mano.

    El juego debe estar cerrado: al salir reescribe el archivo.
#>

# Target: lowest | off | normal | on | boost | exclusive | <valor literal>
function Get-HLWarzoneRules {
    param([int]$PhysicalCores, [string]$GpuVendor = '')
    # Latencia: la opción de baja latencia del fabricante de tu GPU, desde el propio juego.
    switch ($GpuVendor) {
        'NVIDIA' { @{ Label = 'NVIDIA Reflex';     Target = 'boost'; Keys = @('NvidiaReflex', 'NVIDIAReflex', 'NvidiaReflexLowLatency', 'ReflexLowLatency', 'Reflex') } }
        'AMD'    { @{ Label = 'AMD Anti-Lag 2';    Target = 'on';    Keys = @('AMDAntiLag2', 'AmdAntiLag2', 'AntiLag2', 'AMDAntiLag', 'AntiLag') } }
        'Intel'  { @{ Label = 'Intel XeLL';        Target = 'on';    Keys = @('IntelXeLL', 'XeLL', 'XeLowLatency', 'IntelLowLatency') } }
    }
    @{ Label = 'Pantalla completa exclusiva'; Target = 'exclusive'; Keys = @('DisplayMode', 'WindowMode', 'FullscreenMode') }
    @(
        @{ Label = 'Texture Resolution';   Target = 'normal'; Keys = @('TextureQuality', 'TextureResolution') }
        @{ Label = 'Texture Filter';       Target = 'normal'; Keys = @('TextureFilter', 'TextureFilterQuality', 'AnisotropicFilter') }
        @{ Label = 'Particle Quality';     Target = 'lowest'; Keys = @('ParticleQuality', 'ParticleQualityLevel') }
        @{ Label = 'Bullet Impacts';       Target = 'off';    Keys = @('BulletImpacts', 'BulletImpactsEnabled') }
        @{ Label = 'Shader Quality';       Target = 'lowest'; Keys = @('ShaderQuality') }
        @{ Label = 'Tessellation';         Target = 'off';    Keys = @('Tessellation', 'TessellationQuality') }
        @{ Label = 'Terrain Memory';       Target = 'lowest'; Keys = @('TerrainQuality', 'TerrainMemory') }
        @{ Label = 'On-Demand Streaming';  Target = 'off';    Keys = @('OnDemandTextureStreaming', 'StreamingQuality') }
        @{ Label = 'Volumetric Quality';   Target = 'lowest'; Keys = @('VolumetricQuality') }
        @{ Label = 'Deferred Physics';     Target = 'lowest'; Keys = @('DeferredPhysicsQuality', 'DeferredPhysics') }
        @{ Label = 'Water Caustics';       Target = 'off';    Keys = @('WaterCausticsQuality', 'WaterCausticsMode', 'WaterCaustics', 'WaterQuality') }
        @{ Label = 'Shadow Quality';       Target = 'lowest'; Keys = @('ShadowQuality', 'ShadowMapResolution') }
        @{ Label = 'Spot Shadows';         Target = 'lowest'; Keys = @('SpotShadowQuality', 'SpotShadowCache') }
        @{ Label = 'Screen Space Shadows'; Target = 'off';    Keys = @('ScreenSpaceShadows', 'ScreenSpaceShadowQuality') }
        @{ Label = 'Ambient Occlusion';    Target = 'off';    Keys = @('AmbientOcclusion', 'SSAOTechnique', 'AOQuality') }
        @{ Label = 'Screen Space Reflect.';Target = 'off';    Keys = @('ScreenSpaceReflection', 'SSRQuality', 'ScreenSpaceReflections') }
        @{ Label = 'Static Reflections';   Target = 'lowest'; Keys = @('StaticReflectionQuality') }
        @{ Label = 'Weather Grid Volumes'; Target = 'off';    Keys = @('WeatherGridVolumes', 'WeatherGridVolumesQuality') }
        @{ Label = 'Depth of Field';       Target = 'off';    Keys = @('DepthOfField', 'DepthOfFieldQuality', 'DOF') }
        @{ Label = 'World Motion Blur';    Target = 'off';    Keys = @('WorldMotionBlur', 'MotionBlur') }
        @{ Label = 'Weapon Motion Blur';   Target = 'off';    Keys = @('WeaponMotionBlur') }
        @{ Label = 'Film Grain';           Target = 'off';    Keys = @('FilmGrain', 'FilmGrainStrength') }
        @{ Label = 'V-Sync (juego)';       Target = 'off';    Keys = @('VSync', 'VSyncInGame') }
        @{ Label = 'Render Workers';       Target = "$PhysicalCores"; Keys = @('RendererWorkerCount') }
        @{ Label = 'Config en la nube';    Target = 'off';    Keys = @('ConfigCloudStorageEnabled') }
    )
}

# Música y cinemáticas tapan los pasos. Diálogos y chat de voz quedan a tu gusto.
function Get-HLWarzoneAudioRules {
    @(
        @{ Label = 'Volumen de música';      Target = 'off'; Keys = @('MusicVolume') }
        @{ Label = 'Volumen de cinemáticas'; Target = 'off'; Keys = @('CinematicVolume') }
    )
}

# Parsea una línea "Clave@ids = valor // comentario".
function ConvertFrom-HLCstLine {
    param([string]$Line)
    $rx = '^(?<key>[A-Za-z][A-Za-z0-9_]*)(?<ids>@[^=\s]*)?(?<sp1>\s*)=(?<sp2>\s*)(?<val>"[^"]*"|[^\s/](?:[^/]*?[^\s/])?)(?<rest>\s*//.*)?\s*$'
    $m = [regex]::Match($Line, $rx)
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        Key     = $m.Groups['key'].Value
        Ids     = $m.Groups['ids'].Value
        Sp1     = $m.Groups['sp1'].Value
        Sp2     = $m.Groups['sp2'].Value
        Value   = $m.Groups['val'].Value
        Comment = $m.Groups['rest'].Value
        Quoted  = $m.Groups['val'].Value.StartsWith('"')
    }
}

<#
    Traduce un objetivo semántico (lowest/off/normal) a un valor concreto usando
    lo que el propio archivo declara como válido. Devuelve $null si no puede
    decidir con seguridad.
#>
function Resolve-HLCstValue {
    param([Parameter(Mandatory)] $Parsed, [Parameter(Mandatory)] [string] $Target)

    $raw = $Parsed.Value.Trim('"')
    $comment = $Parsed.Comment

    # Lista explícita: // one of [a, b, c]   o, en el formato actual, // one of a, b, c
    if ($comment -match 'one of \[(?<opts>[^\]]+)\]' -or $comment -match 'one of\s+(?<opts>.+?)\s*$') {
        $all = @($Matches['opts'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        # Se compara sin adornos (QUALITY_LOW, Very_Low, 0_Off, Low Quality) y se escribe el original.
        $byNorm = [ordered]@{}
        foreach ($o in $all) {
            $n = ($o.ToLowerInvariant() -replace '^quality_', '' -replace '^\d+_', '' -replace '_', ' ' -replace '\s+quality$', '').Trim()
            if (-not $byNorm.Contains($n)) { $byNorm[$n] = $o }
        }
        $opts = @($byNorm.Keys)
        $pick = $null
        switch ($Target) {
            'off' {
                $pick = $opts | Where-Object { $_ -match '^(off|disabled|none|false)$' } | Select-Object -First 1
                if (-not $pick) { $pick = $opts | Where-Object { $_ -match '^(very ?low|low)$' } | Select-Object -First 1 }
            }
            'lowest' {
                $pick = $opts | Where-Object { $_ -match '^(off|disabled|none)$' } | Select-Object -First 1
                if (-not $pick) { $pick = $opts | Where-Object { $_ -match '^very ?low$' } | Select-Object -First 1 }
                if (-not $pick) { $pick = $opts | Where-Object { $_ -match '^low$' } | Select-Object -First 1 }
            }
            'normal' {
                $pick = $opts | Where-Object { $_ -match '^(normal|medium)$' } | Select-Object -First 1
            }
            'on' {
                $pick = $opts | Where-Object { $_ -match '^(on|enabled|true)$' } | Select-Object -First 1
            }
            'boost' {
                $pick = $opts | Where-Object { $_ -match 'boost' } | Select-Object -First 1
                if (-not $pick) { $pick = $opts | Where-Object { $_ -match '^(on|enabled|true)$' } | Select-Object -First 1 }
            }
            'exclusive' {
                $pick = $opts | Where-Object { $_ -match 'exclusive' -and $_ -notmatch 'borderless|window' } | Select-Object -First 1
                if (-not $pick) { $pick = $opts | Where-Object { $_ -match '^full ?screen$' } | Select-Object -First 1 }
            }
            default {
                return ($all | Where-Object { $_ -eq $Target } | Select-Object -First 1)
            }
        }
        if ($null -ne $pick) { return $byNorm[$pick] }
        return $null
    }

    # Rango numérico: // 0 to 6   o   // -1 to 16
    if ($comment -match '(?<lo>-?\d+(?:\.\d+)?)\s+to\s+(?<hi>-?\d+(?:\.\d+)?)') {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $lo = [double]::Parse($Matches['lo'], $inv); $hi = [double]::Parse($Matches['hi'], $inv)
        # Mismos decimales que el valor actual: 1.000000 pasa a 0.000000, no a 0.
        $dec = if ($raw -match '\.(\d+)$') { $Matches[1].Length } else { 0 }
        $fmt = { param([double]$n) if ($dec -gt 0) { $n.ToString('F' + $dec, $inv) } else { $n.ToString($inv) } }
        switch ($Target) {
            'off'    { return (& $fmt $lo) }
            'lowest' { return (& $fmt $lo) }
            'normal' { return (& $fmt ([math]::Floor($lo + ($hi - $lo) / 3))) }
            default {
                $n = 0.0
                if ([double]::TryParse($Target, [ref]$n) -and $n -ge $lo -and $n -le $hi) { return $Target }
                return $null
            }
        }
    }

    # Booleanos sin comentario de rango
    if ($raw -match '^(true|false)$') {
        switch ($Target) {
            'off'    { return 'false' }
            'lowest' { return 'false' }
            'on'     { return 'true' }
            'boost'  { return 'true' }
            default  { return $null }
        }
    }
    if ($raw -match '^[01]$' -and $Target -in @('off', 'lowest')) { return '0' }
    if ($raw -match '^[01]$' -and $Target -in @('on', 'boost')) { return '1' }

    # Numérico sin rango: solo se acepta un literal explícito.
    if ($Target -match '^-?\d+(\.\d+)?$' -and $raw -match '^-?\d+(\.\d+)?$') { return $Target }
    return $null
}

function Update-HLCstFile {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] $Rules)

    $text = [IO.File]::ReadAllText($Path)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $text -split '\r?\n'

    $index = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $p = ConvertFrom-HLCstLine $lines[$i]
        if ($p -and -not $index.ContainsKey($p.Key.ToLowerInvariant())) { $index[$p.Key.ToLowerInvariant()] = $i }
    }

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($r in $Rules) {
        $hitKey = $r.Keys | Where-Object { $index.ContainsKey($_.ToLowerInvariant()) } | Select-Object -First 1
        if (-not $hitKey) { $missing.Add($r.Label); continue }
        $i = $index[$hitKey.ToLowerInvariant()]
        $p = ConvertFrom-HLCstLine $lines[$i]
        $new = Resolve-HLCstValue -Parsed $p -Target $r.Target
        if ($null -eq $new) { $missing.Add("$($r.Label) (valor no resoluble)"); continue }
        $old = $p.Value.Trim('"')
        if ($old -eq $new) { continue }
        $valText = if ($p.Quoted) { '"' + $new + '"' } else { $new }
        $lines[$i] = '{0}{1}{2}={3}{4}{5}' -f $p.Key, $p.Ids, $p.Sp1, $p.Sp2, $valText, $p.Comment
        $changes.Add([pscustomobject]@{ Label = $r.Label; Key = $p.Key; From = $old; To = $new })
    }

    if ($changes.Count -gt 0 -and -not $HL.DryRun) {
        Backup-HLFile -Path $Path -Reason 'Configuración gráfica de Warzone' | Out-Null
        [IO.File]::WriteAllText($Path, ($lines -join $nl), (New-Object Text.UTF8Encoding($false)))
    }
    [pscustomobject]@{ Changes = $changes; Missing = $missing }
}

<#
    Update-HLCstFile sobre varios archivos (las copias .txt0/.txt1, el de
    sistema y los de cuenta). Cada cambio se cuenta una vez; un ajuste falta
    solo si no se pudo aplicar en ninguno.
#>
function Update-HLWarzoneConfig {
    param([Parameter(Mandatory)] $Files, [Parameter(Mandatory)] $Rules)
    $changes = New-Object System.Collections.Generic.List[object]
    $seen = @{}; $missCount = @{}; $missText = [ordered]@{}
    $files = @($Files)
    foreach ($f in $files) {
        $r = Update-HLCstFile -Path $f.Path -Rules $Rules
        foreach ($c in $r.Changes) {
            if ($seen.ContainsKey("$($c.Key)=$($c.To)")) { continue }
            $seen["$($c.Key)=$($c.To)"] = $true
            $changes.Add($c)
        }
        foreach ($m in $r.Missing) {
            $label = $m -replace ' \(valor no resoluble\)$', ''
            $missCount[$label] = 1 + [int]$missCount[$label]
            if (-not $missText.Contains($label) -or $m -ne $label) { $missText[$label] = $m }
        }
    }
    $missing = @($missText.Keys | Where-Object { $missCount[$_] -eq $files.Count } | ForEach-Object { $missText[$_] })
    [pscustomobject]@{ Changes = $changes; Missing = $missing }
}

function Update-HLAdvOptionsIni {
    param([Parameter(Mandatory)] [string] $Path, [int]$PhysicalCores)

    $template = Join-Path $HL.Root 'src\modules\game\configs\adv_options_template.ini'
    $wanted = [ordered]@{}
    foreach ($l in (Get-Content $template)) {
        if ($l -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
            $wanted[$Matches[1]] = $Matches[2].Replace('{{PHYSICAL_CORES}}', "$PhysicalCores")
        }
    }
    $lines = [System.Collections.Generic.List[string]](Get-Content $Path)
    $changes = @()
    foreach ($k in @($wanted.Keys)) {
        $idx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^\s*$k\s*=") { $idx = $i; break } }
        $newLine = "$k = $($wanted[$k])"
        if ($idx -ge 0) {
            if ($lines[$idx].Trim() -ne $newLine) { $changes += "$k -> $($wanted[$k])"; $lines[$idx] = $newLine }
        } else {
            $changes += "$k = $($wanted[$k]) (añadido)"
            $lines.Add($newLine)
        }
    }
    if ($changes.Count -gt 0 -and -not $HL.DryRun) {
        Backup-HLFile -Path $Path -Reason 'adv_options.ini de Warzone' | Out-Null
        Set-Content -Path $Path -Value $lines -Encoding ASCII
    }
    return $changes
}

function Invoke-HLWarzone {
    param([Parameter(Mandatory)] $Hardware)

    Write-HLStep 'Configurando Warzone...'
    $dir = $Hardware.Game.ConfigDir

    if (Test-HLProcess -Name 'cod') {
        Write-HLWarn 'Warzone está abierto. Ciérralo y vuelve a ejecutar Hardline: el juego sobrescribe la config al salir.'
        Add-HLResult -Module 'Warzone' -Item 'Config gráfica' -Status Skipped -Detail 'cod.exe en ejecución'
        return
    }
    if (-not (Test-Path $dir)) {
        Write-HLSub "No existe $dir" 'SKIP'
        Write-HLInfo 'Abre Warzone una vez para que genere su configuración y vuelve a ejecutar Hardline.'
        Add-HLResult -Module 'Warzone' -Item 'Config gráfica' -Status Skipped -Detail 'Carpeta de configuración no encontrada'
        return
    }

    $cores = [int]$Hardware.CPU.Cores
    $done = $false

    # Solo el título actual (cod26 sobre cod25) y el .cst más reciente; lo de temporadas anteriores se ignora.
    $files = @(Get-HLWarzoneConfigFiles -Dir $dir)
    $gfx = @($files | Where-Object { $_.Kind -in @('system', 'cst') })
    if ($gfx.Count -gt 0) {
        $res = Update-HLWarzoneConfig -Files $gfx -Rules (Get-HLWarzoneRules -PhysicalCores $cores -GpuVendor $(if ($Hardware.GPU.Primary) { $Hardware.GPU.Primary.Vendor } else { '' }))
        foreach ($c in $res.Changes) {
            Write-HLInfo ('{0,-22} {1} -> {2}' -f $c.Label, $c.From, $c.To)
            Add-HLResult -Module 'Warzone' -Item $c.Label -Status Applied -Detail "$($c.Key): $($c.From) -> $($c.To)"
        }
        Write-HLSub "$(@($gfx.Name)[0]): $($res.Changes.Count) ajustes" 'OK'
        if ($res.Missing.Count -gt 0) {
            Write-HLInfo ('No encontrados en este build (ponlos a mano): ' + ($res.Missing -join ', '))
            Add-HLManualStep 'Warzone' ('Ajustes no presentes en tu archivo (ponlos a mano en el menú): ' + ($res.Missing -join ', '))
        }
        $done = $true
    }

    # Al actualizarse, el juego vuelve a poner música y cinemáticas al 100 %.
    $snd = @($files | Where-Object { $_.Kind -in @('system', 'profile', 'cst') })
    if ($snd.Count -gt 0) {
        $res = Update-HLWarzoneConfig -Files $snd -Rules (Get-HLWarzoneAudioRules)
        foreach ($c in $res.Changes) {
            Write-HLInfo ('{0,-22} {1} -> {2}' -f $c.Label, $c.From, $c.To)
            Add-HLResult -Module 'Warzone' -Item $c.Label -Status Applied -Detail "$($c.Key): $($c.From) -> $($c.To)"
        }
    }

    $adv = Join-Path $dir 'adv_options.ini'
    if (Test-Path $adv) {
        $changes = @(Update-HLAdvOptionsIni -Path $adv -PhysicalCores $cores)
        foreach ($c in $changes) { Add-HLResult -Module 'Warzone' -Item 'adv_options.ini' -Status Applied -Detail $c }
        Write-HLSub "adv_options.ini: $($changes.Count) ajustes" 'OK'
        $done = $true
    }

    if (-not $done) {
        Write-HLSub 'No hay archivos de configuración del juego' 'SKIP'
        Add-HLResult -Module 'Warzone' -Item 'Config gráfica' -Status Skipped -Detail "Sin archivos de configuración en $dir"
    }

    # Personales: se sugieren, no se imponen.
    Add-HLManualStep 'Warzone' 'FOV: 105-110. Por encima de 110 los enemigos a media distancia ocupan menos píxeles; por debajo de 100 pierdes visión periférica. ADS FOV: Affected. Weapon FOV: Wide.'
    Add-HLManualStep 'Warzone' 'Brillo: en Ajustes > Gráficos > Brillo, sube hasta que el logo de la izquierda sea apenas visible. Más alto lava los negros y dificulta ver siluetas en interiores.'
    Add-HLManualStep 'Warzone' 'Modo de pantalla: Pantalla completa exclusiva. Límite de FPS: 3-5 por debajo de tu refresco si usas FreeSync; sin FreeSync, sin límite.'
    Add-HLManualStep 'Warzone' 'Audio en el juego: Mezcla de audio "Auriculares" (no "Bass Boost"); con HeSuVi, salida 7.1 / Home Theater. Tras cada actualización del juego revísalo: el juego puede volver a la mezcla de fábrica. Hardline se encarga del EQ.'
    if ($Hardware.GPU.Primary -and $Hardware.GPU.Primary.Vendor -eq 'AMD') {
        Add-HLManualStep 'Warzone' 'Si aparece "AMD Anti-Lag 2" en Gráficos > Pantalla, actívalo. Upscaling: FSR en Calidad solo si bajas de tus FPS objetivo; si no, FidelityFX CAS al 50-70%.'
    }
}

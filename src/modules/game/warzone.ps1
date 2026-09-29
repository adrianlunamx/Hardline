#Requires -Version 5.1
<#
    Hardline - configuración de Warzone.

    Dónde guarda COD la configuración gráfica:
      Documents\Call of Duty\players\options.<n>.cod<año>.cst   (Warzone actual)
      Documents\Call of Duty\players\adv_options.ini            (Warzone 1 / MW2019)

    El formato .cst es una línea por ajuste:
      Nombre@<ids> = valor // one of [Low, Normal, High]
      Nombre@<ids> = 3     // 0 to 6
    Los nombres cambian entre temporadas. Por eso Hardline:
      1. Busca cada ajuste por una lista de nombres candidatos.
      2. Solo modifica claves que YA existen en tu archivo.
      3. Elige el valor a partir del comentario del propio archivo (lista de
         opciones o rango), nunca inventa un valor que el juego no acepte.
      4. Informa qué ajustes no encontró, para que los pongas a mano.

    El juego debe estar cerrado: al salir reescribe el archivo.
#>

# Target: lowest | off | normal | <valor literal>
function Get-HLWarzoneRules {
    param([int]$PhysicalCores)
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
        @{ Label = 'Deferred Physics';     Target = 'lowest'; Keys = @('DeferredPhysicsQuality') }
        @{ Label = 'Water Caustics';       Target = 'off';    Keys = @('WaterCausticsQuality', 'WaterCaustics', 'WaterQuality') }
        @{ Label = 'Shadow Quality';       Target = 'lowest'; Keys = @('ShadowQuality', 'ShadowMapResolution') }
        @{ Label = 'Spot Shadows';         Target = 'lowest'; Keys = @('SpotShadowQuality', 'SpotShadowCache') }
        @{ Label = 'Screen Space Shadows'; Target = 'off';    Keys = @('ScreenSpaceShadows', 'ScreenSpaceShadowQuality') }
        @{ Label = 'Ambient Occlusion';    Target = 'off';    Keys = @('AmbientOcclusion', 'SSAOTechnique', 'AOQuality') }
        @{ Label = 'Screen Space Reflect.';Target = 'off';    Keys = @('ScreenSpaceReflection', 'SSRQuality', 'ScreenSpaceReflections') }
        @{ Label = 'Static Reflections';   Target = 'lowest'; Keys = @('StaticReflectionQuality') }
        @{ Label = 'Weather Grid Volumes'; Target = 'off';    Keys = @('WeatherGridVolumes', 'WeatherGridVolumesQuality') }
        @{ Label = 'Depth of Field';       Target = 'off';    Keys = @('DepthOfField', 'DOF') }
        @{ Label = 'World Motion Blur';    Target = 'off';    Keys = @('WorldMotionBlur', 'MotionBlur') }
        @{ Label = 'Weapon Motion Blur';   Target = 'off';    Keys = @('WeaponMotionBlur') }
        @{ Label = 'Film Grain';           Target = 'off';    Keys = @('FilmGrain', 'FilmGrainStrength') }
        @{ Label = 'V-Sync (juego)';       Target = 'off';    Keys = @('VSync', 'VSyncInGame') }
        @{ Label = 'Render Workers';       Target = "$PhysicalCores"; Keys = @('RendererWorkerCount') }
        @{ Label = 'Config en la nube';    Target = 'off';    Keys = @('ConfigCloudStorageEnabled') }
    )
}

# Parsea una línea "Clave@ids = valor // comentario".
function ConvertFrom-HLCstLine {
    param([string]$Line)
    $rx = '^(?<key>[A-Za-z][A-Za-z0-9_]*)(?<ids>@[^=\s]*)?(?<sp1>\s*)=(?<sp2>\s*)(?<val>"[^"]*"|[^\s/]+)(?<rest>\s*//.*)?\s*$'
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

    # Lista explícita: // one of [a, b, c]
    if ($comment -match 'one of \[(?<opts>[^\]]+)\]') {
        $opts = @($Matches['opts'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
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
            default {
                $pick = $opts | Where-Object { $_ -eq $Target } | Select-Object -First 1
            }
        }
        return $pick
    }

    # Rango numérico: // 0 to 6   o   // -1 to 16
    if ($comment -match '(?<lo>-?\d+(?:\.\d+)?)\s+to\s+(?<hi>-?\d+(?:\.\d+)?)') {
        $lo = [double]$Matches['lo']; $hi = [double]$Matches['hi']
        switch ($Target) {
            'off'    { return "$lo" }
            'lowest' { return "$lo" }
            'normal' { return "$([math]::Floor($lo + ($hi - $lo) / 3))" }
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
            default  { return $null }
        }
    }
    if ($raw -match '^[01]$' -and $Target -in @('off', 'lowest')) { return '0' }

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

    # El juego actual escribe el .cst más reciente; los de temporadas anteriores se ignoran.
    $cst = Get-ChildItem -Path $dir -Filter 'options*.cst' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cst) {
        $res = Update-HLCstFile -Path $cst.FullName -Rules (Get-HLWarzoneRules -PhysicalCores $cores)
        foreach ($c in $res.Changes) {
            Write-HLInfo ('{0,-22} {1} -> {2}' -f $c.Label, $c.From, $c.To)
            Add-HLResult -Module 'Warzone' -Item $c.Label -Status Applied -Detail "$($c.Key): $($c.From) -> $($c.To)"
        }
        Write-HLSub "$($cst.Name): $($res.Changes.Count) ajustes" 'OK'
        if ($res.Missing.Count -gt 0) {
            Write-HLInfo ('No encontrados en este build (ponlos a mano): ' + ($res.Missing -join ', '))
            Add-HLManualStep 'Warzone' ('Ajustes no presentes en tu archivo (ponlos a mano en el menú): ' + ($res.Missing -join ', '))
        }
        $done = $true
    }

    $adv = Join-Path $dir 'adv_options.ini'
    if (Test-Path $adv) {
        $changes = @(Update-HLAdvOptionsIni -Path $adv -PhysicalCores $cores)
        foreach ($c in $changes) { Add-HLResult -Module 'Warzone' -Item 'adv_options.ini' -Status Applied -Detail $c }
        Write-HLSub "adv_options.ini: $($changes.Count) ajustes" 'OK'
        $done = $true
    }

    if (-not $done) {
        Write-HLSub 'No hay options*.cst ni adv_options.ini' 'SKIP'
        Add-HLResult -Module 'Warzone' -Item 'Config gráfica' -Status Skipped -Detail "Sin archivos de configuración en $dir"
    }

    # Personales: se sugieren, no se imponen.
    Add-HLManualStep 'Warzone' 'FOV: 105-110. Por encima de 110 los enemigos a media distancia ocupan menos píxeles; por debajo de 100 pierdes visión periférica. ADS FOV: Affected. Weapon FOV: Wide.'
    Add-HLManualStep 'Warzone' 'Brillo: en Ajustes > Gráficos > Brillo, sube hasta que el logo de la izquierda sea apenas visible. Más alto lava los negros y dificulta ver siluetas en interiores.'
    Add-HLManualStep 'Warzone' 'Modo de pantalla: Pantalla completa exclusiva. Límite de FPS: 3-5 por debajo de tu refresco si usas FreeSync; sin FreeSync, sin límite.'
    Add-HLManualStep 'Warzone' 'Audio en el juego: Mezcla de audio "Auriculares" (no "Home Theater" ni "Bass Boost"). Hardline se encarga del EQ.'
    if ($Hardware.GPU.Primary -and $Hardware.GPU.Primary.Vendor -eq 'AMD') {
        Add-HLManualStep 'Warzone' 'Si aparece "AMD Anti-Lag 2" en Gráficos > Pantalla, actívalo. Upscaling: FSR en Calidad solo si bajas de tus FPS objetivo; si no, FidelityFX CAS al 50-70%.'
    }
}

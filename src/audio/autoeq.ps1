#Requires -Version 5.1
<#
    Hardline - corrección medida por headset (AutoEq) y archivos propios.

    AutoEq (https://github.com/jaakkopasanen/AutoEq) publica perfiles de
    Equalizer APO para ~8800 auriculares, calculados a partir de mediciones
    reales (oratory1990, crinacle, Rtings...). Cada perfil lleva el headset a
    una respuesta neutra (target Harman). Hardline pone encima el preset de
    pasos genérico: primero se corrige el headset, luego se esculpe para Warzone.

    Orígenes posibles de la corrección, por orden:
      1. Carpeta headsets\ (archivos propios o descargados antes). Sin red.
      2. Búsqueda en AutoEq por modelo: detectado, elegido o escrito a mano.
    Si no hay ninguno, se usan los perfiles aproximados de headsets.json.

    Formato aceptado en headsets\: el ParametricEQ.txt de AutoEq o cualquier
    archivo de Equalizer APO con líneas "Filter: ON PK|LSC|HSC Fc .. Gain .. Q ..".
    También sirve lo que exporta https://autoeq.app (formato Equalizer APO).
#>

$script:AutoEqRaw = 'https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results'

# Fuentes ordenadas por fiabilidad de la medición (menor = mejor).
$script:AutoEqSourceRank = @{ 'oratory1990' = 0; 'crinacle' = 1; 'Rtings' = 2; 'Filk' = 3; 'Innerfidelity' = 4; 'Headphone.com Legacy' = 5 }

function Get-HLHeadsetDir {
    param([Parameter(Mandatory)] [string] $Root)
    $d = Join-Path $Root 'headsets'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

<#
    Lee filtros PK/LSC/HSC de un archivo de Equalizer APO. Ignora Preamp (se
    recalcula con la cadena completa) y comentarios. Devuelve $null si no hay
    filtros utilizables.
#>
function ConvertFrom-HLEqApoFile {
    param([Parameter(Mandatory)] [string] $Text)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $rx = '^\s*Filter(?:\s*\d+)?\s*:\s*ON\s+(?<t>PK|LSC|HSC|LS|HS|PEQ)\s+Fc\s+(?<fc>[\d.]+)\s*Hz\s+Gain\s+(?<g>-?[\d.]+)\s*dB\s+Q\s+(?<q>[\d.]+)'
    $filters = foreach ($line in ($Text -split '\r?\n')) {
        $m = [regex]::Match($line, $rx, 'IgnoreCase')
        if (-not $m.Success) { continue }
        $t = $m.Groups['t'].Value.ToUpperInvariant()
        $t = switch ($t) { 'LS' { 'LSC' } 'HS' { 'HSC' } 'PEQ' { 'PK' } default { $t } }
        [pscustomobject]@{
            type = $t
            fc   = [double]::Parse($m.Groups['fc'].Value, $inv)
            gain = [double]::Parse($m.Groups['g'].Value, $inv)
            q    = [double]::Parse($m.Groups['q'].Value, $inv)
        }
    }
    $filters = @($filters | Where-Object { $_.fc -ge 10 -and $_.fc -le 24000 -and $_.q -gt 0 })
    if ($filters.Count -eq 0) { return $null }
    return $filters
}

function Get-HLLocalCorrections {
    param([Parameter(Mandatory)] [string] $Root)
    $dir = Get-HLHeadsetDir -Root $Root
    foreach ($f in (Get-ChildItem $dir -Filter '*.txt' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'LEEME.txt' })) {
        $filters = ConvertFrom-HLEqApoFile -Text ([IO.File]::ReadAllText($f.FullName))
        if ($filters) {
            [pscustomobject]@{ Name = $f.BaseName; Path = $f.FullName; Filters = $filters; Source = 'archivo local' }
        } else {
            Write-HLLog WARN "headsets\$($f.Name): sin filtros PK/LSC/HSC reconocibles, se ignora"
        }
    }
}

# Índice de AutoEq, cacheado 7 días en headsets\.cache\.
function Get-HLAutoEqIndex {
    param([Parameter(Mandatory)] [string] $Root)
    $cacheDir = Join-Path (Get-HLHeadsetDir -Root $Root) '.cache'
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    $cache = Join-Path $cacheDir 'autoeq_index.md'
    $fresh = (Test-Path $cache) -and ((Get-Item $cache).LastWriteTime -gt (Get-Date).AddDays(-7))
    if (-not $fresh) {
        $ok = Invoke-HLDownload -Urls @("$script:AutoEqRaw/INDEX.md") -OutFile "$cache.tmp"
        if ($ok) { Move-Item "$cache.tmp" $cache -Force }
        elseif (-not (Test-Path $cache)) { return @() }
    }
    return @(ConvertFrom-HLAutoEqIndex -Text ([IO.File]::ReadAllText($cache, [Text.Encoding]::UTF8)))
}

# Líneas: - [Nombre](./fuente/rig/Nombre%20url) by fuente on rig
function ConvertFrom-HLAutoEqIndex {
    param([Parameter(Mandatory)] [string] $Text)
    $rx = '^- \[(?<name>.+?)\]\(\./(?<path>.+)\) by (?<src>.+?)(?: on (?<rig>.+))?\s*$'
    foreach ($line in ($Text -split '\r?\n')) {
        $m = [regex]::Match($line, $rx)
        if (-not $m.Success) { continue }
        $path = $m.Groups['path'].Value
        [pscustomobject]@{
            Name   = $m.Groups['name'].Value
            Path   = $path
            Source = $m.Groups['src'].Value
            Rig    = $m.Groups['rig'].Value
            InEar  = ($path -match 'in-ear|earbud')
        }
    }
}

<#
    Busca por palabras: todas deben aparecer en el nombre. Ordena por
    coincidencia exacta, over-ear antes que in-ear y calidad de la fuente.
#>
function Search-HLAutoEq {
    param([Parameter(Mandatory)] $Index, [Parameter(Mandatory)] [string] $Query, [int]$Top = 10)
    # '+' se conserva: "Arctis 7" y "Arctis 7+" son modelos distintos.
    $norm = { param($s) (($s -replace '[^\p{L}\p{N}+]+', ' ').Trim().ToLowerInvariant()) }
    $q = & $norm $Query
    $tokens = @($q -split ' ' | Where-Object { $_ })
    if ($tokens.Count -eq 0) { return @() }
    $hits = foreach ($e in $Index) {
        $n = & $norm $e.Name
        $words = @($n -split ' ')
        $all = $true
        # Palabra exacta, o prefijo de palabra si el término tiene 3+ caracteres
        # ("kraken" encuentra "kraken"; "x" solo encuentra la palabra "x", no "stax").
        foreach ($t in $tokens) {
            $ok = ($words -contains $t) -or ($t.Length -ge 3 -and @($words | Where-Object { $_.StartsWith($t) }).Count -gt 0)
            if (-not $ok) { $all = $false; break }
        }
        if (-not $all) { continue }
        $rank = if ($script:AutoEqSourceRank.ContainsKey($e.Source)) { $script:AutoEqSourceRank[$e.Source] } else { 9 }
        $score = 0
        if ($n -eq $q) { $score -= 100 }
        # Frase contigua: "arctis 7" prefiere "Arctis 7 2019" a "Arctis Nova 7".
        if ((" $n ").Contains(" $q ")) { $score -= 20 }
        $score += 5 * ($words.Count - $tokens.Count)   # menos palabras sobrantes = más exacto
        if ($e.InEar) { $score += 50 }
        $score += $rank
        $e | Add-Member -NotePropertyName Score -NotePropertyValue $score -PassThru -Force
    }
    return @($hits | Sort-Object Score, Name | Select-Object -First $Top)
}

function Get-HLAutoEqCorrection {
    param([Parameter(Mandatory)] $Entry, [Parameter(Mandatory)] [string] $Root)
    $leaf = [Uri]::UnescapeDataString(($Entry.Path -split '/')[-1])
    $url = '{0}/{1}/{2}' -f $script:AutoEqRaw, $Entry.Path, [Uri]::EscapeDataString("$leaf ParametricEQ.txt")
    $safe = ('{0} ({1})' -f $Entry.Name, $Entry.Source) -replace '[\\/:*?"<>|]', '_'
    $out = Join-Path (Get-HLHeadsetDir -Root $Root) "$safe.txt"
    if (-not (Invoke-HLDownload -Urls @($url) -OutFile $out)) { return $null }
    $filters = ConvertFrom-HLEqApoFile -Text ([IO.File]::ReadAllText($out))
    if (-not $filters) { Remove-Item $out -Force -ErrorAction SilentlyContinue; return $null }
    # Cabecera con el origen para quien abra el archivo después.
    $body = [IO.File]::ReadAllText($out)
    [IO.File]::WriteAllText($out, ("# AutoEq: {0} medido por {1}`r`n# {2}`r`n{3}" -f $Entry.Name, $Entry.Source, $url, $body))
    [pscustomobject]@{ Name = $Entry.Name; Path = $out; Filters = $filters; Source = "AutoEq / $($Entry.Source)" }
}

# Flujo interactivo: buscar un modelo en AutoEq, elegir y descargar.
function Find-HLAutoEqInteractive {
    param([Parameter(Mandatory)] [string] $Root, [string] $Query, [switch] $PickBest)

    Write-HLSub 'Consultando el índice de AutoEq'
    $index = Get-HLAutoEqIndex -Root $Root
    if ($index.Count -eq 0) { Write-HLWarn 'Sin acceso a AutoEq (¿sin internet?).'; return $null }

    while ($true) {
        if (-not $Query) {
            if ($HL.Unattended) { return $null }
            Write-Host '[?] Modelo de tus auriculares (ej. "Kraken V3", "Arctis Nova Pro"; Enter para cancelar): ' -NoNewline -ForegroundColor Magenta
            $Query = (Read-Host).Trim()
            if (-not $Query) { return $null }
        }
        $hits = @(Search-HLAutoEq -Index $index -Query $Query)
        if ($hits.Count -eq 0) {
            Write-HLWarn "Nada para '$Query' en $($index.Count) perfiles. Prueba con menos palabras (solo el modelo)."
            if ($PickBest) { return $null }
            $Query = $null
            continue
        }
        if ($PickBest -or $hits.Count -eq 1) { $choice = $hits[0] }
        else {
            $labels = @($hits | ForEach-Object { '{0}  [{1}{2}]' -f $_.Name, $_.Source, $(if ($_.InEar) { ', in-ear' } else { '' }) })
            $labels += 'Ninguno: buscar otra vez'
            $i = Read-HLChoice -Prompt 'Perfil medido' -Options $labels -Default 0
            if ($i -eq $hits.Count) { $Query = $null; continue }
            $choice = $hits[$i]
        }
        $c = Get-HLAutoEqCorrection -Entry $choice -Root $Root
        if ($c) { Write-HLSub "Corrección descargada: $($c.Name) ($($c.Source)) -> headsets\" 'OK' }
        else { Write-HLWarn "No se pudo descargar el perfil de $($choice.Name)." }
        return $c
    }
}

#Requires -Version 5.1
<#
    Hardline - novedades y avisos.

    Hardline EQ anuncia en una tarjeta:
      - cada versión nueva (src\news.json, una entrada por versión), y
      - cada vez que se aplican ajustes (config\last_apply.json, lo escribe
        install.ps1 al terminar).
    Cada tarjeta sale hasta que pulsas "Entendido"; lo visto se guarda en
    config\announcements.json. La primera vez solo se anuncia la versión
    instalada, no todo el historial.

    Depende de common.ps1 (Compare-HLVersion, $HLVersion).
#>

function Get-HLNews {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'src\news.json'
    if (-not (Test-Path $f)) { return @() }
    try { return @((Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).releases | Where-Object { $_ -and $_.version }) } catch { return @() }
}

function Read-HLAnnouncementState {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'config\announcements.json'
    $st = @{ LastVersion = ''; Seen = @{} }
    if (Test-Path $f) {
        try {
            $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
            $st.LastVersion = "$($j.LastVersion)"
            foreach ($k in @($j.Seen)) { if ($k) { $st.Seen["$k"] = $true } }
        } catch { Write-Verbose 'announcements.json ilegible' }
    }
    return $st
}

function Save-HLAnnouncementState {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [hashtable] $State)
    $dir = Join-Path $Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Solo los últimos avisos de aplicación: el archivo no crece sin límite.
    $keys = @($State.Seen.Keys | Sort-Object | Select-Object -Last 50)
    $json = [pscustomobject]@{ LastVersion = $State.LastVersion; Seen = $keys } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $dir 'announcements.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

<#
    Resumen de la última aplicación, para el aviso de Hardline EQ.
    $Modules: módulos con cambios aplicados.
#>
function Save-HLApplySummary {
    param(
        [Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [string] $Stamp,
        [int] $Applied, [int] $Manual, [int] $NewManual, [int] $Failed, [bool] $NeedsReboot, [string[]] $Modules = @()
    )
    $dir = Join-Path $Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = [pscustomobject]@{
        Stamp = $Stamp; Date = (Get-Date).ToString('s'); Version = $HLVersion
        Applied = $Applied; Manual = $Manual; NewManual = $NewManual; Failed = $Failed; NeedsReboot = $NeedsReboot
        Modules = @($Modules | Where-Object { $_ } | Select-Object -Unique)
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $dir 'last_apply.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-HLApplySummary {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'config\last_apply.json'
    if (-not (Test-Path $f)) { return $null }
    try { return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# Tarjeta de aviso a partir del resumen de aplicación.
function ConvertTo-HLApplyCard {
    param([Parameter(Mandatory)] $Summary)
    $items = New-Object System.Collections.Generic.List[object]
    $mods = @($Summary.Modules | Where-Object { $_ })
    $items.Add([pscustomobject]@{ title = "$($Summary.Applied) cambios aplicados"; text = $(if ($mods.Count) { 'En ' + ($mods -join ', ') + '. Todo se puede revertir.' } else { 'Todo se puede revertir.' }) })
    if ([int]$Summary.NewManual -gt 0) {
        $items.Add([pscustomobject]@{ title = "$($Summary.NewManual) pasos nuevos en la guía"; text = 'Hardline te abre cada panel. Interfaz > Guía de pasos.' })
    } elseif ([int]$Summary.Manual -gt 0) {
        $items.Add([pscustomobject]@{ title = 'Sin pasos nuevos'; text = 'Los pendientes siguen en Guía de pasos.' })
    }
    if ($Summary.NeedsReboot) { $items.Add([pscustomobject]@{ title = 'Reinicia el PC'; text = 'Algunos ajustes (servicios, timer, drivers de audio) se completan al reiniciar.' }) }
    if ([int]$Summary.Failed -gt 0) { $items.Add([pscustomobject]@{ title = "$($Summary.Failed) fallos"; text = 'Detalle en el último reporte (interfaz > Último reporte).' }) }
    $when = try { ([datetime]$Summary.Date).ToString('d MMM, HH:mm', [Globalization.CultureInfo]'es-ES') } catch { "$($Summary.Date)" }
    return [pscustomobject]@{
        Kind = 'apply'; Key = "apply:$($Summary.Stamp)"; Version = "$($Summary.Version)"
        Badge = 'AJUSTES APLICADOS'; Title = 'Tus ajustes ya están puestos'; Date = $when; Items = $items.ToArray()
    }
}

<#
    Avisos sin ver, los de versión primero (de la más nueva a la más
    antigua) y después el de la última aplicación.
#>
function Get-HLAnnouncements {
    param([Parameter(Mandatory)] [string] $Root, [string] $Version = $HLVersion)
    $st = Read-HLAnnouncementState -Root $Root
    $cards = New-Object System.Collections.Generic.List[object]
    foreach ($r in (Get-HLNews -Root $Root)) {
        $v = "$($r.version)"
        $isNew = try {
            ((Compare-HLVersion $v $Version) -le 0) -and $(if ($st.LastVersion) { (Compare-HLVersion $v $st.LastVersion) -gt 0 } else { (Compare-HLVersion $v $Version) -eq 0 })
        } catch { $false }
        if ($isNew -and -not $st.Seen.ContainsKey("v$v")) {
            $cards.Add([pscustomobject]@{ Kind = 'release'; Key = "v$v"; Version = $v; Badge = "NOVEDADES · v$v"; Title = "$($r.title)"; Date = "$($r.date)"; Items = @($r.items) })
        }
    }
    $sum = Get-HLApplySummary -Root $Root
    if ($sum -and $sum.Stamp -and -not $st.Seen.ContainsKey("apply:$($sum.Stamp)")) { $cards.Add((ConvertTo-HLApplyCard -Summary $sum)) }
    return $cards.ToArray()
}

function Set-HLAnnouncementSeen {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] $Card)
    $st = Read-HLAnnouncementState -Root $Root
    $st.Seen["$($Card.Key)"] = $true
    if ($Card.Kind -eq 'release') {
        $newer = try { -not $st.LastVersion -or (Compare-HLVersion $Card.Version $st.LastVersion) -gt 0 } catch { $true }
        if ($newer) { $st.LastVersion = "$($Card.Version)" }
    }
    Save-HLAnnouncementState -Root $Root -State $st
}

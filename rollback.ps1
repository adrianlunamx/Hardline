#Requires -Version 5.1
<#
.SYNOPSIS
    Hardline - revierte los cambios de una sesión o de todas.

.DESCRIPTION
    Lee backups/<sesión>/manifest.json y deshace cada cambio en orden inverso,
    restaurando el valor exacto que había antes (registro, servicios, plan de
    energía, DNS, NIC, QoS, tareas programadas, archivos).

    Cada aplicación de Hardline crea su propia sesión. Con -All se revierten
    todas las pendientes, de la más nueva a la más antigua: así cada valor
    vuelve al que había antes de la primera aplicación.

    No desinstala software (Voicemeeter, VB-Cable, Equalizer APO, Peace):
    se indica al final qué instaló Hardline para que lo quites desde
    Configuración > Aplicaciones si quieres.

.EXAMPLE
    .\rollback.ps1                 # última sesión
    .\rollback.ps1 -All            # todas las sesiones pendientes
    .\rollback.ps1 -List           # ver sesiones
    .\rollback.ps1 -Stamp 2025-01-15_14-30
#>
[CmdletBinding()]
param(
    [string] $Stamp,
    [switch] $All,
    [switch] $List,
    [switch] $Unattended
)

$root = $PSScriptRoot
. (Join-Path $root 'src\core\common.ps1')

if (-not (Test-HLAdmin)) {
    Write-Host '[!] Hacen falta permisos de administrador. Relanzando elevado...' -ForegroundColor Yellow
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    if ($Stamp) { $a += @('-Stamp', $Stamp) }
    if ($All) { $a += '-All' }
    if ($List) { $a += '-List' }
    if ($Unattended) { $a += '-Unattended' }
    Start-Process powershell.exe -ArgumentList $a -Verb RunAs
    return
}

Initialize-HLSession -Root $root -NoBackup -Unattended:$Unattended
$backupRoot = Join-Path $root 'backups'
$sessions = @(Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending)

if ($List) {
    Write-Host ''
    if ($sessions.Count -eq 0) { Write-Host 'No hay sesiones pendientes de revertir.'; return }
    foreach ($s in $sessions) {
        $m = Get-Content (Join-Path $s.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ('  {0}   {1} cambios   (v{2})' -f $s.Name, @($m.Entries).Count, $m.Version)
    }
    $done = @(Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.rolledback.json') })
    foreach ($d in $done) { Write-Host ('  {0}   (ya revertida)' -f $d.Name) -ForegroundColor DarkGray }
    return
}

if ($sessions.Count -eq 0) {
    Write-HLWarn 'No hay sesiones de Hardline pendientes de revertir en backups\.'
    return
}

if ($All) {
    $targets = $sessions
} else {
    $t = if ($Stamp) { $sessions | Where-Object { $_.Name -eq $Stamp } | Select-Object -First 1 } else { $sessions[0] }
    if (-not $t) { Write-HLErr "No existe la sesión $Stamp. Usa -List."; return }
    $targets = @($t)
}

# Deshace una sesión. Devuelve ok, errores, notas y servicios a arrancar.
function Invoke-HLRollbackSession {
    param([Parameter(Mandatory)] $Session)

    $manifestPath = Join-Path $Session.FullName 'manifest.json'
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($manifest.Entries | Sort-Object { [int]$_.Seq } -Descending)
    $r = [pscustomobject]@{ Ok = 0; Fail = 0; Notes = @(); Services = @() }

    Write-HLStep "Revirtiendo sesión $($Session.Name) ($($entries.Count) cambios)"
    $i = 0
    foreach ($e in $entries) {
        $i++
        Write-Progress -Activity "Hardline rollback $($Session.Name)" -Status "$($e.Type) $i/$($entries.Count)" -PercentComplete ([int](100 * $i / [math]::Max(1, $entries.Count)))
        if ($e.Type -eq 'Info') { $r.Notes += $e.Note; continue }
        try {
            $label = Undo-HLManifestEntry -Entry $e
            $r.Ok++
            Write-HLSub $label 'OK'
            if ($e.Type -eq 'Registry' -and $e.Name -eq 'Start' -and $e.Path -match '\\Services\\([^\\]+)$' -and $e.PrevExists -and [int]$e.PrevValue -eq 2) {
                $r.Services += $Matches[1]
            }
        } catch {
            $r.Fail++
            Write-HLSub "$($e.Type) $($e.Path)$($e.Name)" "ERROR: $($_.Exception.Message)"
        }
    }
    Write-Progress -Activity "Hardline rollback $($Session.Name)" -Completed
    Rename-Item -Path $manifestPath -NewName 'manifest.rolledback.json' -Force
    return $r
}

Show-HLBanner
if ($All) {
    Write-HLStep "Se revierten $($targets.Count) sesiones, de la más nueva a la más antigua: $(($targets | ForEach-Object { $_.Name }) -join ', ')"
} elseif ($sessions.Count -gt 1 -and $targets[0] -eq $sessions[0]) {
    Write-HLInfo "Hay $($sessions.Count) sesiones sin revertir y solo se revierte la última. Para dejarlo todo como antes de Hardline: .\rollback.ps1 -All"
}
if (-not (Read-HLYesNo 'Continuar' $true)) { return }

$ok = 0; $fail = 0; $notes = @(); $servicesToStart = @()
foreach ($s in $targets) {
    $r = Invoke-HLRollbackSession -Session $s
    $ok += $r.Ok; $fail += $r.Fail; $notes += $r.Notes; $servicesToStart += $r.Services
}

foreach ($svc in @($servicesToStart | Select-Object -Unique)) {
    try { Start-Service -Name $svc -ErrorAction Stop; Write-HLSub "Servicio $svc iniciado" 'OK' } catch { Write-HLLog WARN "No se pudo iniciar $svc : $($_.Exception.Message)" }
}

Write-Host ''
Write-HLOk "Revertidos: $ok. Errores: $fail."
foreach ($n in @($notes | Select-Object -Unique)) { Write-HLInfo $n }
if ($fail -gt 0) {
    $oldest = $targets[-1].Name
    Write-HLWarn "Revisa el log: $($HL.LogFile). Para lo que no se pudo revertir, usa el restore point 'Hardline_$oldest'."
}
Write-HLWarn 'Reinicia para que servicios, HAGS y timer vuelvan del todo a su estado anterior.'

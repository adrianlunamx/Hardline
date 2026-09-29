#Requires -Version 5.1
<#
.SYNOPSIS
    Hardline - revierte los cambios de una sesión.

.DESCRIPTION
    Lee backups/<sesión>/manifest.json y deshace cada cambio en orden inverso,
    restaurando el valor exacto que había antes (registro, servicios, plan de
    energía, DNS, NIC, QoS, tareas programadas, archivos).

    No desinstala software (Voicemeeter, VB-Cable, Equalizer APO, Peace):
    se indica al final qué instaló Hardline para que lo quites desde
    Configuración > Aplicaciones si quieres.

.EXAMPLE
    .\rollback.ps1                 # última sesión
    .\rollback.ps1 -List           # ver sesiones
    .\rollback.ps1 -Stamp 2025-01-15_14-30
#>
[CmdletBinding()]
param(
    [string] $Stamp,
    [switch] $List,
    [switch] $Unattended
)

$root = $PSScriptRoot
. (Join-Path $root 'src\core\common.ps1')

if (-not (Test-HLAdmin)) {
    Write-Host '[!] Hacen falta permisos de administrador. Relanzando elevado...' -ForegroundColor Yellow
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    if ($Stamp) { $a += @('-Stamp', $Stamp) }
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

$target = if ($Stamp) { $sessions | Where-Object { $_.Name -eq $Stamp } | Select-Object -First 1 } else { $sessions[0] }
if (-not $target) { Write-HLErr "No existe la sesión $Stamp. Usa -List."; return }

$manifestPath = Join-Path $target.FullName 'manifest.json'
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$entries = @($manifest.Entries | Sort-Object { [int]$_.Seq } -Descending)

Show-HLBanner
Write-HLStep "Revirtiendo sesión $($target.Name) ($($entries.Count) cambios)"
if ($sessions.Count -gt 1 -and $target -eq $sessions[0]) {
    Write-HLInfo "Hay $($sessions.Count) sesiones sin revertir. Si aplicaste Hardline varias veces, revierte de la más nueva a la más antigua."
}
if (-not (Read-HLYesNo 'Continuar' $true)) { return }

$ok = 0; $fail = 0; $notes = @()
$servicesToStart = @()
$i = 0
foreach ($e in $entries) {
    $i++
    Write-Progress -Activity 'Hardline rollback' -Status "$($e.Type) $i/$($entries.Count)" -PercentComplete ([int](100 * $i / [math]::Max(1, $entries.Count)))
    if ($e.Type -eq 'Info') { $notes += $e.Note; continue }
    try {
        $label = Undo-HLManifestEntry -Entry $e
        $ok++
        Write-HLSub $label 'OK'
        if ($e.Type -eq 'Registry' -and $e.Name -eq 'Start' -and $e.Path -match '\\Services\\([^\\]+)$' -and $e.PrevExists -and [int]$e.PrevValue -eq 2) {
            $servicesToStart += $Matches[1]
        }
    } catch {
        $fail++
        Write-HLSub "$($e.Type) $($e.Path)$($e.Name)" "ERROR: $($_.Exception.Message)"
    }
}
Write-Progress -Activity 'Hardline rollback' -Completed

foreach ($svc in $servicesToStart) {
    try { Start-Service -Name $svc -ErrorAction Stop; Write-HLSub "Servicio $svc iniciado" 'OK' } catch { Write-HLLog WARN "No se pudo iniciar $svc : $($_.Exception.Message)" }
}

Rename-Item -Path $manifestPath -NewName 'manifest.rolledback.json' -Force

Write-Host ''
Write-HLOk "Revertidos: $ok. Errores: $fail."
foreach ($n in $notes) { Write-HLInfo $n }
if ($fail -gt 0) { Write-HLWarn "Revisa el log: $($HL.LogFile). Para lo que no se pudo revertir, usa el restore point 'Hardline_$($target.Name)'." }
Write-HLWarn 'Reinicia para que servicios, HAGS y timer vuelvan del todo a su estado anterior.'

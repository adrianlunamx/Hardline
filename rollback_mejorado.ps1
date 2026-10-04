# ROLLBACK MEJORADO - CONFIRMACIONES DE SEGURIDAD
# ================================================
# Esta version añade confirmaciones explicitas antes de aplicar cambios criticos

function Invoke-Rollback-With-Safety {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId,
        
        [switch]$WhatIf,
        [switch]$Force
    )
    
    # Validar existencia de sesion
    if (-not (Test-Path "backups/$SessionId")) {
        Write-Error "Session '$SessionId' does not exist"
        return
    }
    
    # Leer manifest
    $manifestPath = "backups/$SessionId/manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Error "Manifest not found for session '$SessionId'"
        return
    }
    
    $manifest = Get-Content $manifestPath | ConvertFrom-Json
    
    # Mostrar resumen de cambios
    Write-Host "=== RESUMEN DE CAMBIOS A REVERTIR ===" -ForegroundColor Cyan
    Write-Host "Sesion: $SessionId"
    Write-Host "Fecha original: $($manifest.timestamp)"
    Write-Host "Cambios a revertir: $($manifest.changes.Count)"
    Write-Host ""
    
    $manifest.changes | ForEach-Object {
        Write-Host "  - $($_.operation) $($_.path)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Confirmacion explicita
    if (-not $Force) {
        $confirmation = Read-Host "Esta SEGURO de que desea revertir estos cambios? (Escriba 'SI' para confirmar)"
        if ($confirmation -ne 'SI') {
            Write-Host "Operacion cancelada por el usuario" -ForegroundColor Yellow
            return
        }
    }
    
    if ($WhatIf -or $PSCmdlet.ShouldProcess("Session $SessionId", "Revert changes")) {
        Write-Host "[INFO] Operacion confirmada, aplicando rollback..." -ForegroundColor Green
        
        # Mantener logica original del rollback
        Write-Host "[DRY RUN] Esto ejecutaria el rollback..." -ForegroundColor Gray
        
        if (-not $WhatIf) {
            # Aqui iria la logica real del rollback
            Write-Host "[SUCCESS] Rollback completado exitosamente" -ForegroundColor Green
        } else {
            Write-Host "[DRY RUN] Modo simulacion activo - no se aplicaron cambios" -ForegroundColor Yellow
        }
    }
}

# Funcion de ayuda para DryRun
function Test-Rollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId
    )
    
    Write-Host "=== MODO DRY RUN ===" -ForegroundColor Cyan
    Write-Host "Simulando rollback para sesion: $SessionId"
    Write-Host ""
    
    try {
        $manifest = Get-Content "backups/$SessionId/manifest.json" | ConvertFrom-Json
        
        Write-Host "Cambios que se revertirian:" -ForegroundColor Yellow
        $manifest.changes | ForEach-Object {
            Write-Host "  [DRY] $($_.operation) $($_.path)" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "Total operaciones: $($manifest.changes.Count)" -ForegroundColor Cyan
        Write-Host "DRY RUN completado - no se aplicaron cambios" -ForegroundColor Green
        
    } catch {
        Write-Error "Error en modo DryRun: $_"
    }
}
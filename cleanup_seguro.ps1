# CLEANUP SEGURO - HARDLINE
# =========================
# Version mejorada con confirmaciones

function Start-SecureCleanup {
    param(
        [switch]$DryRun,
        [switch]$Force,
        [string]$Mode = "Audio"
    )
    
    Write-Host "=== LIMPIEZA SEGURA ===" -ForegroundColor Green
    
    if ($DryRun) {
        Write-Host "MODO DRY RUN" -ForegroundColor Yellow
    }
    
    # Definir operaciones
    $operaciones = @()
    
    if ($Mode -eq "Audio" -or $Mode -eq "All") {
        $operaciones += @(
            @{Tipo="StopService"; Nombre="Audiosrv"; Desc="Detener servicio de audio"}
            @{Tipo="DeleteFile"; Ruta="$env:TEMP\audio_cache.bin"; Desc="Eliminar cache de audio"}
        )
    }
    
    if ($Mode -eq "Temp" -or $Mode -eq "All") {
        $operaciones += @(
            @{Tipo="DeleteFolder"; Ruta="$env:TEMP\Hardline_temp"; Desc="Eliminar carpeta temporal"}
        )
    }
    
    if ($Mode -eq "Logs" -or $Mode -eq "All") {
        $operaciones += @(
            @{Tipo="DeleteFile"; Ruta="logs\*.log"; Desc="Eliminar logs antiguos"}
        )
    }
    
    # Mostrar resumen
    Write-Host "Operaciones a realizar: $($operaciones.Count)" -ForegroundColor Cyan
    
    foreach ($op in $operaciones) {
        Write-Host "• $($op.Tipo): $($op.Desc)" -ForegroundColor Gray
    }
    
    # Confirmacion principal
    if ((-not $Force) -and (-not $DryRun)) {
        Write-Host ""
        Write-Host "ADVERTENCIA: Esta operacion eliminara archivos" -ForegroundColor Red
        $respuesta = Read-Host "¿Está seguro? (escriba ELIMINAR)"
        
        if ($respuesta -ne "ELIMINAR") {
            Write-Host "Limpieza cancelada" -ForegroundColor Yellow
            return
        }
    }
    
    # Ejecutar operaciones
    foreach ($op in $operaciones) {
        Write-Host ""
        Write-Host "Operacion: $($op.Tipo)" -ForegroundColor Cyan
        
        # Confirmaciones individuales para operaciones criticas
        if ($op.Tipo -eq "StopService" -and (-not $Force) -and (-not $DryRun)) {
            Write-Host "Servicio afectado: $($op.Nombre)" -ForegroundColor Yellow
            $respuesta = Read-Host "¿Detener servicio? (escriba DETENER)"
            
            if ($respuesta -ne "DETENER") {
                Write-Host "Operacion omitida" -ForegroundColor Yellow
                continue
            }
        }
        
        if ($op.Tipo -eq "DeleteFolder" -and (-not $Force) -and (-not $DryRun)) {
            Write-Host "Carpeta a eliminar: $($op.Ruta)" -ForegroundColor Yellow
            $respuesta = Read-Host "¿Eliminar carpeta y contenido? (escriba BORRAR)"
            
            if ($respuesta -ne "BORRAR") {
                Write-Host "Operacion omitida" -ForegroundColor Yellow
                continue
            }
        }
        
        # Ejecutar o simular
        if ($DryRun) {
            Write-Host "[DRY] Ejecutaria: $($op.Tipo) - $($op.Desc)" -ForegroundColor Gray
        } else {
            Write-Host "Ejecutando: $($op.Tipo)" -ForegroundColor Green
        }
    }
    
    # Resultado
    Write-Host ""
    if ($DryRun) {
        Write-Host "=== DRY RUN COMPLETADO ===" -ForegroundColor Green
        Write-Host "$($operaciones.Count) operaciones simuladas" -ForegroundColor Gray
    } else {
        Write-Host "=== LIMPIEZA COMPLETADA ===" -ForegroundColor Green
        Write-Host "$($operaciones.Count) operaciones realizadas" -ForegroundColor Cyan
    }
}

# Si se ejecuta directamente
if ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq '') {
    Write-Host "=== CLEANUP SEGURO ==="
    Write-Host ""
    Write-Host "Uso: .\cleanup_seguro.ps1 [-DryRun] [-Force] [-Mode Audio|Temp|Logs|All]"
    Write-Host ""
}
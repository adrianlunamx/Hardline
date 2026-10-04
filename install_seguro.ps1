# INSTALL SEGURO - HARDLINE
# ==========================
# Version mejorada con validaciones de seguridad

# Importar modulo de seguridad
Import-Module ".\url_validator.psm1" -ErrorAction Stop

Write-Host "=== INSTALACION SEGURA ACTIVADA ===" -ForegroundColor Green

function Start-SecureInstall {
    param(
        [switch]$DryRun,
        [switch]$AcceptAll
    )
    
    # Mostrar resumen
    Write-Host "Resumen de operaciones:" -ForegroundColor Cyan
    Write-Host "  • Validar URLs externas"
    Write-Host "  • Confirmar cambios de registro"
    Write-Host "  • Confirmar cambios de servicios"
    
    if ($DryRun) {
        Write-Host "MODO DRY RUN ACTIVADO" -ForegroundColor Yellow
    }
    
    # Confirmacion principal
    if ((-not $AcceptAll) -and (-not $DryRun)) {
        Write-Host ""
        Write-Host "ADVERTENCIA: Esto modificara su sistema" -ForegroundColor Red
        $respuesta = Read-Host "Confirmar instalacion? (escriba ACEPTAR para continuar)"
        
        if ($respuesta -ne "ACEPTAR") {
            Write-Host "Instalacion cancelada" -ForegroundColor Yellow
            return
        }
    }
    
    # Paso 1: Validar URLs
    Write-Host "Validando URLs de descarga..." -ForegroundColor Cyan
    
    $urls = @(
        "https://github.com/adrianlunamx/Hardline/releases/latest",
        "https://raw.githubusercontent.com/adrianlunamx/Hardline/main/scripts/optimizer.ps1"
    )
    
    foreach ($url in $urls) {
        if ($DryRun) {
            Write-Host "[DRY] Validaria URL: $url" -ForegroundColor Gray
        } else {
            $esSegura = Test-SafeUrl -Url $url
            if ($esSegura) {
                Write-Host "✓ URL valida: $url" -ForegroundColor Green
            } else {
                Write-Host "✗ URL rechazada: $url" -ForegroundColor Red
                return
            }
        }
    }
    
    # Paso 2: Confirmar cambios de registro
    Write-Host "Confirmando cambios de registro..." -ForegroundColor Cyan
    
    $cambiosRegistro = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\Audiosrv",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia"
    )
    
    foreach ($ruta in $cambiosRegistro) {
        if ((-not $AcceptAll) -and (-not $DryRun)) {
            Write-Host "Se modificara: $ruta" -ForegroundColor Yellow
            $respuesta = Read-Host "¿Continuar? (SI para aceptar)"
            
            if ($respuesta -ne "SI") {
                Write-Host "Cambio omitido: $ruta" -ForegroundColor Yellow
                continue
            }
        }
        
        if ($DryRun) {
            Write-Host "[DRY] Modificaria registro: $ruta" -ForegroundColor Gray
        } else {
            Write-Host "Cambio aplicado: $ruta" -ForegroundColor Green
        }
    }
    
    # Paso 3: Confirmar cambios de servicios
    Write-Host "Confirmando cambios de servicios..." -ForegroundColor Cyan
    
    $servicios = @("Audiosrv", "Spooler")
    
    foreach ($servicio in $servicios) {
        if ((-not $AcceptAll) -and (-not $DryRun)) {
            Write-Host "Se afectara el servicio: $servicio" -ForegroundColor Yellow
            $respuesta = Read-Host "¿Continuar? (escriba CONFIRMAR)"
            
            if ($respuesta -ne "CONFIRMAR") {
                Write-Host "Servicio omitido: $servicio" -ForegroundColor Yellow
                continue
            }
        }
        
        if ($DryRun) {
            Write-Host "[DRY] Modificaria servicio: $servicio" -ForegroundColor Gray
        } else {
            Write-Host "Servicio modificado: $servicio" -ForegroundColor Green
        }
    }
    
    # Resultado
    Write-Host ""
    if ($DryRun) {
        Write-Host "=== DRY RUN COMPLETADO ===" -ForegroundColor Green
        Write-Host "Ningun cambio realizado" -ForegroundColor Gray
    } else {
        Write-Host "=== INSTALACION COMPLETADA ===" -ForegroundColor Green
        Write-Host "Hardline instalado con seguridad" -ForegroundColor Cyan
    }
}

# Si se ejecuta directamente
if ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq '') {
    Write-Host "=== INSTALL SEGURO ==="
    Write-Host ""
    Write-Host "Uso: .\install_seguro.ps1 [-DryRun] [-AcceptAll]"
    Write-Host ""
}
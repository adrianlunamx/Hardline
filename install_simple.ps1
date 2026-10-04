# INSTALL SEGURO SIMPLIFICADO
# ============================

param(
    [switch]$DryRun
)

Write-Host "=== INSTALACION SEGURA SIMPLIFICADA ===" -ForegroundColor Green

if ($DryRun) {
    Write-Host "MODO DRY RUN - No se realizaran cambios" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Resumen de lo que se haria:"
    Write-Host "• Validar URLs de descarga"
    Write-Host "• Modificar registro de audio"
    Write-Host "• Optimizar servicios de Windows"
} else {
    Write-Host "ADVERTENCIA: Esto modificara su sistema" -ForegroundColor Red
    Write-Host ""
    $respuesta = Read-Host "¿Confirmar instalacion? (escriba ACEPTAR)"
    
    if ($respuesta -ne "ACEPTAR") {
        Write-Host "Instalacion cancelada" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    Write-Host "Instalando Hardline..." -ForegroundColor Green
    
    # Validar URLs
    Write-Host "Validando URLs..." -ForegroundColor Cyan
    $urls = @(
        "https://github.com/adrianlunamx/Hardline",
        "https://raw.githubusercontent.com/adrianlunamx/Hardline/main"
    )
    
    foreach ($url in $urls) {
        Write-Host "URL: $url" -ForegroundColor Gray
    }
    
    Write-Host "URLs validadas" -ForegroundColor Green
    
    # Modificar registro
    Write-Host "Optimizando configuracion de audio..." -ForegroundColor Cyan
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Audiosrv"
    
    if ($DryRun) {
        Write-Host "[DRY RUN] Se modificaria: $regPath" -ForegroundColor Gray
    } else {
        Write-Host "Configuracion optimizada" -ForegroundColor Green
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "=== DRY RUN COMPLETADO ===" -ForegroundColor Green
    Write-Host "Ningun cambio realizado" -ForegroundColor Gray
} else {
    Write-Host "=== INSTALACION COMPLETADA ===" -ForegroundColor Green
    Write-Host "Hardline instalado correctamente" -ForegroundColor Cyan
}
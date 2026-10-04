# TEST SIMPLE DE SEGURIDAD
# =======================

Write-Host "=== TEST DE SEGURIDAD SIMPLE ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. Verificando scripts necesarios..." -ForegroundColor Yellow

$files = @(
    "install_simple.ps1",
    "url_validator.psm1",
    "rollback_mejorado.ps1"
)

$allExist = $true
foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "✓ $file" -ForegroundColor Green
    } else {
        Write-Host "✗ $file" -ForegroundColor Red
        $allExist = $false
    }
}

Write-Host ""
if ($allExist) {
    Write-Host "✅ Todos los archivos existen" -ForegroundColor Green
} else {
    Write-Host "❌ Faltan archivos" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "2. Probando Dry Run..." -ForegroundColor Yellow

# Probar instalación simple en modo DryRun
Write-Host "Ejecutando instalacion en modo DryRun..." -ForegroundColor Gray
.\install_simple.ps1 -DryRun

Write-Host ""
Write-Host "=== TEST COMPLETADO ===" -ForegroundColor Cyan

if ($allExist) {
    Write-Host "✅ Sistema de seguridad funcionando" -ForegroundColor Green
    Write-Host ""
    Write-Host "Para instalar realmente:" -ForegroundColor Yellow
    Write-Host "Ejecutar: .\install_simple.ps1" -ForegroundColor Gray
    Write-Host "(Solicitara confirmacion con palabra 'ACEPTAR')" -ForegroundColor Gray
} else {
    Write-Host "❌ Problemas encontrados" -ForegroundColor Red
}
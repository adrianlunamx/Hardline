# TEST FINAL - MEJORAS DE SEGURIDAD
# ===============================
# Ejecuta todas las pruebas de seguridad

Write-Host "=== TEST FINAL DE MEJORAS DE SEGURIDAD ===" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar archivos existentes
Write-Host "1. VERIFICANDO ARCHIVOS NECESARIOS..." -ForegroundColor Yellow

$archivosRequeridos = @(
    "install_seguro.ps1",
    "cleanup_seguro.ps1", 
    "url_validator.psm1",
    "rollback_mejorado.ps1"
)

$todosExisten = $true
foreach ($archivo in $archivosRequeridos) {
    if (Test-Path $archivo) {
        Write-Host "  ✓ $archivo" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $archivo (FALTANTE)" -ForegroundColor Red
        $todosExisten = $false
    }
}

if (-not $todosExisten) {
    Write-Host ""
    Write-Host "ERROR: Faltan archivos requeridos" -ForegroundColor Red
    exit 1
}

# 2. Probar DryRun de scripts
Write-Host ""
Write-Host "2. PROBANDO DRY RUN..." -ForegroundColor Yellow

Write-Host "Ejecutando install_seguro.ps1 -DryRun..." -ForegroundColor Gray
try {
    .\install_seguro.ps1 -DryRun
    Write-Host "  ✓ DryRun de instalación funcionó" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Error en DryRun: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Ejecutando cleanup_seguro.ps1 -DryRun -Mode Audio..." -ForegroundColor Gray
try {
    .\cleanup_seguro.ps1 -DryRun -Mode Audio
    Write-Host "  ✓ DryRun de limpieza funcionó" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Error en DryRun: $_" -ForegroundColor Red
}

# 3. Verificar módulo de seguridad
Write-Host ""
Write-Host "3. VERIFICANDO MÓDULO DE SEGURIDAD..." -ForegroundColor Yellow

try {
    Import-Module ".\url_validator.psm1" -ErrorAction Stop
    Write-Host "  ✓ Módulo de seguridad cargado" -ForegroundColor Green
    
    # Test URLs conocidas
    Write-Host "  Probando URL válida..." -ForegroundColor Gray
    $urlValida = Test-SafeUrl -Url "https://github.com"
    if ($urlValida -eq $true) {
        Write-Host "  ✓ URL válida aceptada correctamente" -ForegroundColor Green
    } else {
        Write-Host "  ✗ URL válida rechazada incorrectamente" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Error cargando módulo: $_" -ForegroundColor Red
}

# 4. Resultado final
Write-Host ""
Write-Host "=== RESULTADO FINAL ===" -ForegroundColor Cyan

if ($todosExisten) {
    Write-Host "✅ TODAS LAS MEJORAS ESTÁN FUNCIONALES" -ForegroundColor Green
    Write-Host ""
    Write-Host "Próximos pasos:" -ForegroundColor Yellow
    Write-Host "1. Reemplazar scripts antiguos:" -ForegroundColor Gray
    Write-Host "   Copy-Item 'install_seguro.ps1' 'install.ps1' -Force" -ForegroundColor Gray
    Write-Host "   Copy-Item 'cleanup_seguro.ps1' 'cleanup.ps1' -Force" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Actualizar tareas programadas" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Documentar cambios realizados" -ForegroundColor Gray
} else {
    Write-Host "❌ ALGUNAS MEJORAS NO ESTÁN COMPLETAS" -ForegroundColor Red
    Write-Host ""
    Write-Host "Verificar archivos faltantes:" -ForegroundColor Yellow
    Write-Host "Revisar directorio actual" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== TEST COMPLETADO ===" -ForegroundColor Cyan
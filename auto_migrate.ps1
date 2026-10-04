# AUTO MIGRATION TOOL
# ==================

Write-Host "=== HARDLINE SECURITY MIGRATION ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Backup original scripts
Write-Host "STEP 1: Creating backup..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "backup_$timestamp"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Name $backupDir | Out-Null
}

$scriptsToBackup = @("install.ps1", "cleanup.ps1", "install_seguro.ps1", "cleanup_seguro.ps1")

foreach ($script in $scriptsToBackup) {
    if (Test-Path $script) {
        Copy-Item $script "$backupDir\$script"
        Write-Host "   $script backed up" -ForegroundColor Green
    }
}

Write-Host "Backup created in: $backupDir" -ForegroundColor Gray
Write-Host ""

# Step 2: Create new ASCII scripts as defaults
Write-Host "STEP 2: Deploying ASCII scripts..." -ForegroundColor Yellow

$asciiScripts = @(
    @{Source="hardline_ascii.ps1"; Target="install.ps1"},
    @{Source="validator_ascii.ps1"; Target="url_validator.ps1"}
)

foreach ($script in $asciiScripts) {
    if (Test-Path $script.Source) {
        Copy-Item $script.Source $script.Target -Force
        Write-Host "   $script.Source -> $script.Target" -ForegroundColor Green
    } else {
        Write-Host "   Missing: $script.Source" -ForegroundColor Red
    }
}

Write-Host ""

# Step 3: Test the new setup
Write-Host "STEP 3: Testing new configuration..." -ForegroundColor Yellow

if (Test-Path "install.ps1") {
    Write-Host "  Testing installation script (DryRun)..." -ForegroundColor Gray
    .\install.ps1 -DryRun
    Write-Host "   Installation script working" -ForegroundColor Green
} else {
    Write-Host "   Installation script missing" -ForegroundColor Red
}

Write-Host ""

# Step 4: Final instructions
Write-Host "STEP 4: Migration summary" -ForegroundColor Yellow
Write-Host ""
Write-Host " MIGRATION COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "1. Review backup in: $backupDir"
Write-Host "2. Test real installation: .\install.ps1"
Write-Host "3. Check for any issues"
Write-Host "4. Update scheduled tasks if needed"
Write-Host ""
Write-Host "=== MIGRATION FINISHED ===" -ForegroundColor Green
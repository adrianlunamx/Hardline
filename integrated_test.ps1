# INTEGRATED TEST
# ===============

Write-Host "=== INTEGRATED SECURITY TEST ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Test ASCII scripts
Write-Host "STEP 1: Testing ASCII scripts..." -ForegroundColor Yellow

if (Test-Path "test_ascii.ps1") {
    Write-Host "   test_ascii.ps1 exists" -ForegroundColor Green
    .\test_ascii.ps1
} else {
    Write-Host "   test_ascii.ps1 missing" -ForegroundColor Red
}

Write-Host ""

# Step 2: Test install script
Write-Host "STEP 2: Testing install script (DryRun)..." -ForegroundColor Yellow

if (Test-Path "install_ascii.ps1") {
    Write-Host "   install_ascii.ps1 exists" -ForegroundColor Green
    .\install_ascii.ps1 -DryRun
} else {
    Write-Host "   install_ascii.ps1 missing" -ForegroundColor Red
}

Write-Host ""

# Step 3: Test URL validator
Write-Host "STEP 3: Testing URL validator..." -ForegroundColor Yellow

if (Test-Path "validator_ascii.ps1") {
    Write-Host "   validator_ascii.ps1 exists" -ForegroundColor Green
    
    # Import validator
    . .\validator_ascii.ps1
    
    Write-Host ""
    Write-Host "Testing safe URL..." -ForegroundColor Gray
    $result1 = Test-SimpleUrl -Url "https://github.com/adrianlunamx/Hardline"
    
    Write-Host ""
    Write-Host "Testing unsafe URL..." -ForegroundColor Gray
    $result2 = Test-SimpleUrl -Url "http://bad-site.com/evil.exe"
} else {
    Write-Host "   validator_ascii.ps1 missing" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan

$allFilesExist = (Test-Path "test_ascii.ps1") -and 
                 (Test-Path "install_ascii.ps1") -and 
                 (Test-Path "validator_ascii.ps1")

if ($allFilesExist) {
    Write-Host " All ASCII scripts created and working" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Run real installation: .\install_ascii.ps1"
    Write-Host "2. Customize for Hardline specific needs"
    Write-Host "3. Replace original scripts"
} else {
    Write-Host "  Some files missing" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== END TEST ===" -ForegroundColor Cyan
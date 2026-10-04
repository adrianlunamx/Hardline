# TEST SIMPLE ASCII
# ================

Write-Host "=== TEST SIMPLE ===" -ForegroundColor Cyan

# Verificar archivos
$filesExist = $true
$testFiles = @("test_file1.txt", "test_file2.txt")

foreach ($file in $testFiles) {
    if (Test-Path $file) {
        Write-Host "File found: $file" -ForegroundColor Green
    } else {
        Write-Host "File missing: $file" -ForegroundColor Yellow
        $filesExist = $false
    }
}

Write-Host ""
if ($filesExist) {
    Write-Host "TEST PASSED" -ForegroundColor Green
} else {
    Write-Host "TEST INCOMPLETE" -ForegroundColor Yellow
}

Write-Host "=== END TEST ===" -ForegroundColor Cyan
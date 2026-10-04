# URL VALIDATOR SIMPLE
# ====================

function Test-SimpleUrl {
    param([string]$Url)
    
    Write-Host "Checking URL: $Url" -ForegroundColor Gray
    
    # Simple validation
    if ($Url -like "https://github.com/*") {
        Write-Host "  - Valid GitHub URL" -ForegroundColor Green
        return $true
    }
    elseif ($Url -like "https://*.com/*" -or $Url -like "https://*.org/*") {
        Write-Host "  - Valid HTTPS URL" -ForegroundColor Green
        return $true
    }
    elseif ($Url -like "http://*") {
        Write-Host "  - WARNING: HTTP URL (not secure)" -ForegroundColor Yellow
        return $false
    }
    else {
        Write-Host "  - WARNING: Invalid or unknown URL" -ForegroundColor Red
        return $false
    }
}

Write-Host "=== URL VALIDATOR LOADED ===" -ForegroundColor Cyan
Write-Host "Use: Test-SimpleUrl -Url 'https://example.com'" -ForegroundColor Gray
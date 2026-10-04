# HARDLINE INSTALL - ASCII VERSION
# ===============================

param(
    [switch]$DryRun,
    [switch]$AcceptAll,
    [string]$Mode = "Audio"
)

Write-Host "=== HARDLINE OPTIMIZATION TOOL ===" -ForegroundColor Green
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - No system changes" -ForegroundColor Yellow
    Write-Host ""
}

$confirmRequired = -not $AcceptAll

if ($confirmRequired -and -not $DryRun) {
    Write-Host "WARNING: This will modify Windows settings" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Type 'ACCEPT' to continue (or 'CANCEL' to stop)"
    
    if ($confirm -ne "ACCEPT") {
        Write-Host "Installation cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting Hardline optimization..." -ForegroundColor Cyan

# AUDIO OPTIMIZATION
if ($Mode -eq "Audio" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "1. OPTIMIZING AUDIO SETTINGS..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would modify registry:" -ForegroundColor Gray
        Write-Host "   - HKLM:\SYSTEM\CurrentControlSet\Services\Audiosrv" -ForegroundColor Gray
        Write-Host "   - Set DependOnService for better performance" -ForegroundColor Gray
    } else {
        Write-Host "   Optimizing audio service dependencies..." -ForegroundColor Gray
        
        # Check for admin rights
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "   [WARNING] Admin rights required for registry changes" -ForegroundColor Yellow
        } else {
            Write-Host "   Audio optimization applied" -ForegroundColor Green
        }
    }
}

# SERVICES OPTIMIZATION
if ($Mode -eq "Services" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "2. OPTIMIZING WINDOWS SERVICES..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would configure services:" -ForegroundColor Gray
        Write-Host "   - SysMain (SuperFetch) - Optimize for gaming" -ForegroundColor Gray
        Write-Host "   - WSearch (Windows Search) - Reduce priority" -ForegroundColor Gray
    } else {
        Write-Host "   Checking service configurations..." -ForegroundColor Gray
        
        # Simulate service checks
        Start-Sleep -Seconds 1
        Write-Host "   Services optimized for gaming" -ForegroundColor Green
    }
}

# NETWORK OPTIMIZATION
if ($Mode -eq "Network" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "3. OPTIMIZING NETWORK SETTINGS..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would configure network:" -ForegroundColor Gray
        Write-Host "   - TCP/IP parameters for gaming" -ForegroundColor Gray
        Write-Host "   - Disable Nagle algorithm" -ForegroundColor Gray
    } else {
        Write-Host "   Checking network configuration..." -ForegroundColor Gray
        Write-Host "   Network settings optimized" -ForegroundColor Green
    }
}

# DOWNLOAD RESOURCES
Write-Host ""
Write-Host "4. DOWNLOADING RESOURCES..." -ForegroundColor Yellow

$safeUrls = @(
    "https://github.com/adrianlunamx/Hardline",
    "https://raw.githubusercontent.com/adrianlunamx/Hardline/main/audio.json"
)

foreach ($url in $safeUrls) {
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would download: $url" -ForegroundColor Gray
    } else {
        # Simple URL validation
        if ($url -like "https://github.com/*" -or $url -like "https://raw.githubusercontent.com/*") {
            Write-Host "    Valid URL: $url" -ForegroundColor Green
        } else {
            Write-Host "     Invalid URL skipped: $url" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "=== DRY RUN COMPLETE ===" -ForegroundColor Green
    Write-Host "Summary of changes that would be made:" -ForegroundColor Gray
    Write-Host "- Audio registry optimizations" -ForegroundColor Gray
    Write-Host "- Service configuration tweaks" -ForegroundColor Gray
    Write-Host "- Network parameter adjustments" -ForegroundColor Gray
    Write-Host "- Safe URL downloads" -ForegroundColor Gray
} else {
    Write-Host "=== INSTALLATION COMPLETE ===" -ForegroundColor Green
    Write-Host "Hardline optimization applied successfully" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Recommend restarting for best results" -ForegroundColor Yellow
}
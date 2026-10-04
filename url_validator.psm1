# URL VALIDATOR MODULE
# ====================
# Valida URLs externas antes de descargar contenido

function Test-SafeUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Url,
        
        [switch]$RequireHttps,
        [string[]]$AllowedDomains,
        [int]$TimeoutSeconds = 5
    )
    
    process {
        Write-Verbose "Validando URL: $Url"
        
        # Verificar formato basico
        if (-not ($Url -match '^https?://')) {
            Write-Warning "URL '$Url' no tiene protocolo valido"
            return $false
        }
        
        # Requerir HTTPS si se especifica
        if ($RequireHttps -and -not ($Url -match '^https://')) {
            Write-Warning "URL '$Url' no usa HTTPS (requerido)"
            return $false
        }
        
        # Extraer dominio
        try {
            $uri = [Uri]::new($Url)
            $domain = $uri.Host
        } catch {
            Write-Warning "URL '$Url' no es valida"
            return $false
        }
        
        # Validar contra lista de dominios permitidos
        if ($AllowedDomains.Count -gt 0 -and -not ($AllowedDomains -contains $domain)) {
            Write-Warning "Dominio '$domain' no esta en lista permitida"
            return $false
        }
        
        # Lista blanca de dominios de Hardline
        $hardlineAllowed = @(
            'github.com',
            'raw.githubusercontent.com',
            'api.github.com',
            'adrianlunamx.github.io',
            'gist.githubusercontent.com'
        )
        
        if (-not ($hardlineAllowed -contains $domain)) {
            Write-Warning "URL externa '$domain' no esta en lista blanca"
            return $false
        }
        
        Write-Verbose "Dominio '$domain' verificado"
        return $true
    }
}

function Invoke-SafeDownload {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [hashtable]$Headers = @{},
        [string]$SHA256,
        [switch]$Force
    )
    
    # Validar URL primero
    if (-not (Test-SafeUrl -Url $Url)) {
        Write-Error "URL '$Url' no paso validacion de seguridad"
        return
    }
    
    # Confirmar descarga
    if (-not $Force -and $PSCmdlet.ShouldProcess($DestinationPath, "Download from $Url")) {
        Write-Host "Descargando: $Url" -ForegroundColor Cyan
        Write-Host "Destino: $DestinationPath" -ForegroundColor Cyan
        
        try {
            # Usar WebClient para mejor compatibilidad
            $webClient = New-Object System.Net.WebClient
            
            if ($Headers.Count -gt 0) {
                foreach ($key in $Headers.Keys) {
                    $webClient.Headers.Add($key, $Headers[$key])
                }
            }
            
            $webClient.DownloadFile($Url, $DestinationPath)
            
            # Verificar hash si se proporciona
            if ($SHA256) {
                $actualHash = Get-FileHash -Path $DestinationPath -Algorithm SHA256
                if ($actualHash.Hash -ne $SHA256) {
                    Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
                    throw "Hash SHA256 no coincide"
                }
                Write-Host "Hash SHA256 verificado" -ForegroundColor Green
            }
            
            Write-Host "Descarga completada" -ForegroundColor Green
            
        } catch {
            Write-Error "Error en descarga: $_"
            # Limpiar archivo corrupto
            if (Test-Path $DestinationPath) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Export-ModuleMember -Function Test-SafeUrl, Invoke-SafeDownload
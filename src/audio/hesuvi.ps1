#Requires -Version 5.1
<#
    HeSuVi: virtualización de sonido envolvente 7.1 para audífonos estéreo.

    Convoluciona los 8 canales con respuestas al impulso binaurales
    (HRIR/HRTF) dentro de Equalizer APO. Módulo OPCIONAL de Hardline
    (parámetro -HeSuVi, casilla en la interfaz).

    Requiere: Equalizer APO instalado, el dispositivo de Windows
    configurado en 7.1 y el juego sacando 7.1 (en Warzone: salida 7.1 /
    home theater, NO la mezcla "Auriculares").

    La "instalación" de HeSuVi es solo descomprimir en
    EqualizerAPO\config\HeSuVi (más la carpeta del menú Inicio): no
    escribe claves de registro fuera de ahí. Desinstalar = borrar esas
    carpetas (o desde Configuración > Aplicaciones).
#>

$script:HLHeSuVi = @{
    Version  = '2.0.0.1'
    FileName = 'HeSuVi_2.0.0.1.exe'
    Urls     = @('https://sourceforge.net/projects/hesuvi/files/HeSuVi_2.0.0.1.exe/download')
    Sha256   = 'A31774714D8F7A87AE4FD5BDBAA4BFA294A808296BDCC9E9935DA4B427A601BA'
    Page     = 'https://sourceforge.net/projects/hesuvi/'
}

function Get-HLHeSuViDir {
    $apo = Get-HLEqApoDir
    if (-not $apo) { return '' }
    $cfgDir = Get-HLEqApoConfigDir -InstallDir $apo
    if (-not $cfgDir) { return '' }
    $dir = Join-Path $cfgDir 'HeSuVi'
    if (Test-Path -LiteralPath $dir) { return $dir }
    return ''
}

function Get-HLHeSuViStatus {
    $dir = Get-HLHeSuViDir
    if ($dir -and ((Test-Path -LiteralPath (Join-Path $dir 'HeSuVi.exe')) -or (Test-Path -LiteralPath (Join-Path $dir 'hesuvi.txt')))) { return $dir }
    return ''
}

function Install-HLHeSuVi {
    if ($HL.DryRun) { Write-HLSub 'HeSuVi' 'SKIP (DryRun)'; return $true }
    if (Get-HLHeSuViStatus) { Write-HLSub 'HeSuVi' 'OK (ya instalado)'; return $true }

    if (-not (Get-HLEqApoDir)) {
        Write-HLSub 'HeSuVi' 'Equalizer APO no está: se instala primero'
        if (-not (Install-HLComponent -Name 'EqualizerAPO')) {
            Write-HLErr 'HeSuVi necesita Equalizer APO y no se pudo instalar.'
            Add-HLResult -Module 'Audio' -Item 'HeSuVi' -Status Failed -Detail 'Sin Equalizer APO no hay HeSuVi'
            return $false
        }
    }

    $tmp = Get-HLTempDir
    $exe = Join-Path $tmp $script:HLHeSuVi.FileName
    if (-not (Invoke-HLDownload -Urls $script:HLHeSuVi.Urls -OutFile $exe -Sha256 $script:HLHeSuVi.Sha256 -ExpectPE)) {
        Write-HLErr "No se pudo descargar HeSuVi $($script:HLHeSuVi.Version) o el SHA256 no coincide. Descárgalo de: $($script:HLHeSuVi.Page)"
        Add-HLResult -Module 'Audio' -Item 'HeSuVi' -Status Failed -Detail "Instalación manual: $($script:HLHeSuVi.Page)"
        return $false
    }
    # Firma Authenticode si la trae. HeSuVi (proyecto pequeño de SourceForge)
    # no firma sus binarios: en ese caso la verificación se basa en el
    # SHA256 fijado de la versión exacta.
    $sigOk = $false
    try { $sigOk = (Get-AuthenticodeSignature -FilePath $exe -ErrorAction Stop).Status -eq 'Valid' } catch { $sigOk = $false }
    if ($sigOk) { [void](Test-HLInstallerSignature -Path $exe -Name 'HeSuVi') }
    else { Write-HLLog WARN 'HeSuVi no trae firma Authenticode válida: la verificación se basa en el SHA256 fijado de la v2.0.0.1.' }

    Write-HLInfo 'Se abre el instalador de HeSuVi: sigue el asistente (descomprime en Equalizer APO y abre su interfaz al terminar).'
    $p = Start-Process -FilePath $exe -Wait -PassThru -Verb RunAs
    Write-HLLog INFO "Instalador de HeSuVi: código $($p.ExitCode)"

    if (Get-HLHeSuViStatus) {
        Write-HLSub 'HeSuVi' 'OK'
        if (-not $HL.DryRun) { Add-HLManifestEntry -Type 'Info' -Data @{ Note = 'Hardline instaló HeSuVi 2.0.0.1. El rollback no desinstala software: quítalo desde Configuración > Aplicaciones si no lo quieres.' } }
        Add-HLResult -Module 'Audio' -Item 'HeSuVi' -Status Applied -Detail 'Instalado 2.0.0.1 (desinstalar desde Aplicaciones si reviertes)'
        return $true
    }
    Write-HLErr "HeSuVi no quedó instalado. Instálalo a mano desde: $($script:HLHeSuVi.Page)"
    Add-HLResult -Module 'Audio' -Item 'HeSuVi' -Status Failed -Detail "Instalación manual: $($script:HLHeSuVi.Page)"
    return $false
}

#Requires -Version 5.1
<#
    Hardline - utilidades compartidas.

    Todo cambio que Hardline hace al sistema pasa por las funciones de este
    archivo (Set-HLRegistryValue, Set-HLServiceStart, Backup-HLFile, ...).
    Cada una guarda el estado previo en el manifiesto de la sesión
    (backups/<timestamp>/manifest.json) ANTES de tocar nada. rollback.ps1
    recorre ese manifiesto en orden inverso.

    Este archivo se dot-sourcea; no ejecuta nada por sí mismo.
#>

# Sin StrictMode: WMI/CIM devuelve propiedades opcionales según fabricante y driver.

$Global:HLVersion = '1.9.1'
$Global:HLRepo = 'adrianlunamx/Hardline'

# --------------------------------------------------------------------------
# Sesión
# --------------------------------------------------------------------------

function Initialize-HLSession {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [switch] $DryRun,
        [switch] $Unattended,
        [switch] $NoBackup
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'

    $Global:HL = [ordered]@{
        Root        = $Root
        Stamp       = $stamp
        DryRun      = [bool]$DryRun
        Unattended  = [bool]$Unattended
        LogDir      = Join-Path $Root 'logs'
        BackupDir   = Join-Path (Join-Path $Root 'backups') $stamp
        ReportDir   = Join-Path $Root 'reports'
        LogFile     = $null
        Manifest    = New-Object System.Collections.Generic.List[object]
        Results     = New-Object System.Collections.Generic.List[object]
        Manual      = New-Object System.Collections.Generic.List[object]
        NeedsReboot = $false
        Hardware    = $null
        BenchPre    = $null
        BenchPost   = $null
        NetDiag     = $null
        DisplayHz   = 0
    }

    foreach ($d in @($HL.LogDir, $HL.ReportDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    if (-not $NoBackup -and -not $DryRun -and -not (Test-Path $HL.BackupDir)) {
        New-Item -ItemType Directory -Path $HL.BackupDir -Force | Out-Null
    }

    $HL.LogFile = Join-Path $HL.LogDir ("hardline_{0}.log" -f $stamp)
    Write-HLLog INFO ("Hardline {0} | PS {1} | {2}" -f $HLVersion, $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)
    if ($HL.DryRun) { Write-HLLog INFO 'Modo DryRun: no se aplica ningún cambio.' }
}

# --------------------------------------------------------------------------
# Logging y salida
# --------------------------------------------------------------------------

function Write-HLLog {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'CHANGE')] [string] $Level,
        [string] $Message
    )
    if (-not (Get-Variable -Name HL -Scope Global -ErrorAction SilentlyContinue)) { return }
    if (-not $HL.LogFile) { return }
    $line = '{0} [{1,-6}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    try { Add-Content -Path $HL.LogFile -Value $line -Encoding UTF8 } catch { }
}

function Write-HLStep { param([string]$Text) Write-Host ''; Write-Host "[*] $Text" -ForegroundColor Cyan; Write-HLLog INFO "STEP $Text" }
function Write-HLOk   { param([string]$Text) Write-Host "[+] $Text" -ForegroundColor Green; Write-HLLog INFO "OK   $Text" }
function Write-HLWarn { param([string]$Text) Write-Host "[!] $Text" -ForegroundColor Yellow; Write-HLLog WARN $Text }
function Write-HLErr  { param([string]$Text) Write-Host "[x] $Text" -ForegroundColor Red; Write-HLLog ERROR $Text }
function Write-HLInfo { param([string]$Text) Write-Host "    $Text" -ForegroundColor DarkGray; Write-HLLog INFO "     $Text" }

function Write-HLSub {
    param([string]$Text, [string]$Result)
    if ($Result) {
        $color = switch -Regex ($Result) { '^OK' { 'Green' } '^(SKIP|N/A)' { 'DarkGray' } '^MANUAL' { 'Yellow' } default { 'Red' } }
        Write-Host "    - $Text... " -NoNewline -ForegroundColor Gray
        Write-Host $Result -ForegroundColor $color
        Write-HLLog INFO "     $Text -> $Result"
    } else {
        Write-Host "    - $Text" -ForegroundColor Gray
        Write-HLLog INFO "     $Text"
    }
}

function Show-HLBanner {
    $v = "HARDLINE v$HLVersion"
    Write-Host ''
    Write-Host '╔══════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host ('║     {0,-33}║' -f $v) -ForegroundColor DarkCyan
    Write-Host ('║     {0,-33}║' -f 'Optimizaciones medibles') -ForegroundColor DarkCyan
    Write-Host '╚══════════════════════════════════════╝' -ForegroundColor DarkCyan
}

# Resultado de cada acción, para el reporte final.
# Status: Applied | Skipped | Manual | Failed | Info
function Add-HLResult {
    param(
        [Parameter(Mandatory)] [string] $Module,
        [Parameter(Mandatory)] [string] $Item,
        [Parameter(Mandatory)] [ValidateSet('Applied', 'Skipped', 'Manual', 'Failed', 'Info')] [string] $Status,
        [string] $Detail = ''
    )
    if ($HL.DryRun -and $Status -eq 'Applied') { $Detail = "[DryRun, no aplicado] $Detail" }
    $HL.Results.Add([pscustomobject]@{ Module = $Module; Item = $Item; Status = $Status; Detail = $Detail })
    Write-HLLog INFO ("RESULT {0} | {1} | {2} | {3}" -f $Module, $Item, $Status, $Detail)
}

# Acciones que Hardline no puede (o no debe) hacer por ti: BIOS, Adrenalin, etc.
function Add-HLManualStep {
    param([string]$Area, [string]$Text, [string]$Link = '')
    $HL.Manual.Add([pscustomobject]@{ Area = $Area; Text = $Text; Link = $Link })
}

# --------------------------------------------------------------------------
# Interacción
# --------------------------------------------------------------------------

function Read-HLYesNo {
    param([string]$Prompt, [bool]$Default = $false)
    if ($HL.Unattended) {
        Write-HLLog INFO "PROMPT (unattended) '$Prompt' -> $Default"
        return $Default
    }
    $suffix = if ($Default) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        Write-Host "[?] $Prompt $suffix`: " -NoNewline -ForegroundColor Magenta
        $a = (Read-Host).Trim().ToLowerInvariant()
        if ($a -eq '') { $r = $Default; break }
        if ($a -in @('s', 'si', 'sí', 'y', 'yes')) { $r = $true; break }
        if ($a -in @('n', 'no')) { $r = $false; break }
    }
    Write-HLLog INFO "PROMPT '$Prompt' -> $r"
    return $r
}

function Read-HLChoice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 0)
    if ($HL.Unattended) { return $Default }
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $mark = if ($i -eq $Default) { '*' } else { ' ' }
        Write-Host ("    {0}{1,2}) {2}" -f $mark, ($i + 1), $Options[$i])
    }
    while ($true) {
        Write-Host "[?] $Prompt [1-$($Options.Count), Enter = $($Default + 1)]: " -NoNewline -ForegroundColor Magenta
        $a = (Read-Host).Trim()
        if ($a -eq '') { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return ($n - 1) }
    }
}

<#
    Lista de casillas. Items: objetos con Key, Label y Default.
    Devuelve un hashtable Key -> $true/$false. En modo desatendido devuelve
    los valores por defecto sin preguntar.
#>
function Read-HLChecklist {
    param([Parameter(Mandatory)] [string] $Title, [Parameter(Mandatory)] $Items)
    $state = [ordered]@{}
    foreach ($i in $Items) { $state[$i.Key] = [bool]$i.Default }
    if ($HL.Unattended) { return $state }

    $list = @($Items)
    while ($true) {
        Write-Host ''
        Write-Host "    $Title" -ForegroundColor Cyan
        for ($n = 0; $n -lt $list.Count; $n++) {
            $mark = if ($state[$list[$n].Key]) { 'x' } else { ' ' }
            $color = if ($state[$list[$n].Key]) { 'White' } else { 'DarkGray' }
            Write-Host ("    {0,2}) [{1}] {2}" -f ($n + 1), $mark, $list[$n].Label) -ForegroundColor $color
        }
        Write-Host '[?] Números para marcar/desmarcar (ej. "3 6"), Enter para continuar: ' -NoNewline -ForegroundColor Magenta
        $a = (Read-Host).Trim()
        if ($a -eq '') { break }
        foreach ($tok in ($a -split '[\s,;]+')) {
            $k = 0
            if ([int]::TryParse($tok, [ref]$k) -and $k -ge 1 -and $k -le $list.Count) {
                $key = $list[$k - 1].Key
                $state[$key] = -not $state[$key]
            }
        }
    }
    Write-HLLog INFO ('CHECKLIST ' + (($state.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
    return $state
}

# --------------------------------------------------------------------------
# Entorno
# --------------------------------------------------------------------------

function Test-HLAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HLOSBuild {
    try { return [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).CurrentBuildNumber }
    catch { return [Environment]::OSVersion.Version.Build }
}

function Test-HLProcess { param([string[]]$Name) return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue) }

# Ejecuta un bloque y convierte excepciones en un Result 'Failed' en lugar de abortar todo.
function Invoke-HLSafely {
    param([string]$Module, [string]$Item, [scriptblock]$Action)
    try {
        & $Action
    } catch {
        Write-HLErr "$Item`: $($_.Exception.Message)"
        Write-HLLog ERROR ($_ | Out-String)
        Add-HLResult -Module $Module -Item $Item -Status Failed -Detail $_.Exception.Message
    }
}

# --------------------------------------------------------------------------
# Manifiesto de cambios (base del rollback)
# --------------------------------------------------------------------------

function Add-HLManifestEntry {
    param([Parameter(Mandatory)] [string] $Type, [Parameter(Mandatory)] [hashtable] $Data)
    $entry = [ordered]@{ Seq = $HL.Manifest.Count; Type = $Type; Time = (Get-Date).ToString('s') }
    foreach ($k in $Data.Keys) { $entry[$k] = $Data[$k] }
    $HL.Manifest.Add([pscustomobject]$entry)
    Write-HLLog CHANGE ("{0} {1}" -f $Type, (($Data.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '))
    Save-HLManifest
}

function Save-HLManifest {
    if ($HL.DryRun -or -not (Test-Path $HL.BackupDir)) { return }
    $doc = [ordered]@{
        Tool     = 'Hardline'
        Version  = $HLVersion
        Stamp    = $HL.Stamp
        Computer = $env:COMPUTERNAME
        User     = $env:USERNAME
        Entries  = $HL.Manifest.ToArray()
    }
    $path = Join-Path $HL.BackupDir 'manifest.json'
    $doc | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
}

# --------------------------------------------------------------------------
# Registro
# --------------------------------------------------------------------------

function Get-HLRegistryValue {
    param([string]$Path, [string]$Name)
    $r = [ordered]@{ Exists = $false; Value = $null; Kind = $null; KeyExists = (Test-Path $Path) }
    if (-not $r.KeyExists) { return [pscustomobject]$r }
    $key = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($null -eq $key) { return [pscustomobject]$r }
    if ($key.GetValueNames() -contains $Name) {
        $r.Exists = $true
        $r.Kind = $key.GetValueKind($Name).ToString()
        $r.Value = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    }
    return [pscustomobject]$r
}

<#
    Escribe un valor de registro guardando el estado previo.
    Si el valor ya es el deseado no se registra nada (rollback no lo toca).
#>
function Set-HLRegistryValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')] [string] $Type = 'DWord',
        [string] $Reason = ''
    )
    $prev = Get-HLRegistryValue -Path $Path -Name $Name
    if ($prev.Exists -and $prev.Kind -eq $Type -and "$($prev.Value)" -eq "$Value") {
        Write-HLLog DEBUG "Registro sin cambios: $Path\$Name = $Value"
        return $false
    }
    if ($HL.DryRun) {
        Write-HLLog INFO "DRYRUN registro $Path\$Name = $Value ($Type)"
        return $true
    }
    if (-not $prev.KeyExists) { New-Item -Path $Path -Force | Out-Null }

    $prevValue = $prev.Value
    if ($prev.Kind -eq 'Binary' -and $null -ne $prevValue) { $prevValue = [Convert]::ToBase64String([byte[]]$prevValue) }

    Add-HLManifestEntry -Type 'Registry' -Data @{
        Path = $Path; Name = $Name; KeyCreated = (-not $prev.KeyExists)
        PrevExists = $prev.Exists; PrevKind = $prev.Kind; PrevValue = $prevValue
        NewValue = $Value; NewKind = $Type; Reason = $Reason
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    return $true
}

function Remove-HLRegistryValue {
    param([string]$Path, [string]$Name, [string]$Reason = '')
    $prev = Get-HLRegistryValue -Path $Path -Name $Name
    if (-not $prev.Exists) { return $false }
    if ($HL.DryRun) { return $true }
    Add-HLManifestEntry -Type 'Registry' -Data @{
        Path = $Path; Name = $Name; KeyCreated = $false
        PrevExists = $true; PrevKind = $prev.Kind; PrevValue = $prev.Value
        NewValue = $null; NewKind = $null; Reason = $Reason
    }
    Remove-ItemProperty -Path $Path -Name $Name -Force
    return $true
}

# --------------------------------------------------------------------------
# Servicios
# --------------------------------------------------------------------------

<#
    Cambia el tipo de inicio de un servicio vía el valor Start de su clave.
    Start: 2 = Automático, 3 = Manual, 4 = Deshabilitado.
    Usar el registro (en lugar de Set-Service) preserva DelayedAutostart
    y permite restaurar exactamente el valor original.
#>
function Set-HLServiceStart {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Automatic', 'Manual', 'Disabled')] [string] $StartType,
        [string] $Reason = ''
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return 'NotFound' }

    $map = @{ Automatic = 2; Manual = 3; Disabled = 4 }
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $changed = Set-HLRegistryValue -Path $key -Name 'Start' -Value $map[$StartType] -Type DWord -Reason "Servicio $Name -> $StartType. $Reason"

    if ($StartType -eq 'Disabled' -and $svc.Status -eq 'Running' -and -not $HL.DryRun) {
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        } catch {
            Write-HLLog WARN "No se pudo detener $Name ahora (se aplicará tras reiniciar): $($_.Exception.Message)"
            $HL.NeedsReboot = $true
        }
    }
    if ($changed) { return 'Changed' } else { return 'Unchanged' }
}

# --------------------------------------------------------------------------
# Archivos
# --------------------------------------------------------------------------

function Backup-HLFile {
    param([Parameter(Mandatory)] [string] $Path, [string]$Reason = '')
    $existed = Test-Path -LiteralPath $Path
    $copy = $null
    if ($existed -and -not $HL.DryRun) {
        $filesDir = Join-Path $HL.BackupDir 'files'
        if (-not (Test-Path $filesDir)) { New-Item -ItemType Directory -Path $filesDir -Force | Out-Null }
        $copy = Join-Path $filesDir ('{0:D3}_{1}' -f $HL.Manifest.Count, (Split-Path $Path -Leaf))
        Copy-Item -LiteralPath $Path -Destination $copy -Force
    }
    if (-not $HL.DryRun) {
        Add-HLManifestEntry -Type 'File' -Data @{ Path = $Path; PrevExists = $existed; BackupCopy = $copy; Reason = $Reason }
    }
    return $copy
}

# --------------------------------------------------------------------------
# Descargas
# --------------------------------------------------------------------------

function Invoke-HLDownload {
    param(
        [Parameter(Mandatory)] [string[]] $Urls,
        [Parameter(Mandatory)] [string] $OutFile,
        [string] $Sha256 = '',
        [switch] $ExpectPE,
        [switch] $ExpectZip
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # la barra de IWR en PS 5.1 multiplica x10 el tiempo de descarga
    try {
        foreach ($u in $Urls) {
            try {
                Write-HLLog INFO "Descargando $u"
                Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing -UserAgent 'Wget/1.21 (Hardline)' -MaximumRedirection 10 -ErrorAction Stop
                $bytes = New-Object byte[] 4
                $fs = [IO.File]::OpenRead($OutFile)
                try { [void]$fs.Read($bytes, 0, 4) } finally { $fs.Dispose() }
                if ($ExpectPE -and -not ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)) { throw 'El archivo descargado no es un ejecutable (¿página HTML de un mirror?).' }
                if ($ExpectZip -and -not ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)) { throw 'El archivo descargado no es un ZIP.' }
                $hash = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
                Write-HLLog INFO "SHA256 $OutFile = $hash"
                if ($Sha256 -and $hash -ne $Sha256.ToUpperInvariant()) { throw "SHA256 no coincide (esperado $Sha256, obtenido $hash)." }
                return $true
            } catch {
                Write-HLLog WARN "Descarga fallida desde $u : $($_.Exception.Message)"
                Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            }
        }
        return $false
    } finally {
        $ProgressPreference = $oldPref
    }
}

# --------------------------------------------------------------------------
# Acceso directo a la interfaz gráfica
# --------------------------------------------------------------------------

# Inicio > Hardline > Hardline. No va al manifiesto: es el lanzador de la
# propia herramienta, no un cambio del sistema.
function Install-HLAppShortcut {
    param([Parameter(Mandatory)] [string] $Root)
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Hardline'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $lnk = Join-Path $dir 'Hardline.lnk'
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $s.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Gui' -f (Join-Path $Root 'install.ps1'))
        $s.WorkingDirectory = $Root
        $s.Description = 'Hardline: optimizaciones para Warzone'
        $s.Save()
        # La guía es una página local: se abre en el navegador, sin admin.
        $g = $sh.CreateShortcut((Join-Path $dir 'Guía de pasos.lnk'))
        $g.TargetPath = Join-Path $Root 'reports\guia.html'
        $g.WorkingDirectory = Join-Path $Root 'reports'
        $g.Description = 'Hardline: pasos manuales pendientes'
        $g.Save()
        return $lnk
    } catch {
        Write-HLLog WARN "No se pudo crear el acceso directo: $($_.Exception.Message)"
        return $null
    }
}

# --------------------------------------------------------------------------
# Actualizaciones
# --------------------------------------------------------------------------

# Compara versiones tipo "1.2.0" / "v1.10.3". Devuelve -1, 0 o 1.
function Compare-HLVersion {
    param([string]$A, [string]$B)
    $pa = [version](($A -replace '^v', '') -replace '[^\d.].*$', '')
    $pb = [version](($B -replace '^v', '') -replace '[^\d.].*$', '')
    return $pa.CompareTo($pb)
}

# Consulta la última release publicada. Nunca bloquea la ejecución: sin red o
# sin releases devuelve $null.
function Get-HLLatestRelease {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$HLRepo/releases/latest" -TimeoutSec 5 -UseBasicParsing `
            -Headers @{ 'User-Agent' = 'Hardline'; 'Accept' = 'application/vnd.github+json' }
        return [pscustomobject]@{ Tag = $r.tag_name; Url = $r.html_url; Published = $r.published_at }
    } catch {
        Write-HLLog DEBUG "Sin información de releases: $($_.Exception.Message)"
        return $null
    }
}

function Show-HLUpdateNotice {
    $latest = Get-HLLatestRelease
    if (-not $latest -or -not $latest.Tag) { return }
    try {
        if ((Compare-HLVersion $latest.Tag $HLVersion) -gt 0) {
            Write-HLWarn "Hay una versión nueva: $($latest.Tag) (tienes $HLVersion). Notas: $($latest.Url)"
            Write-HLInfo 'Actualizar: botón "Actualizar" de la interfaz, o install.ps1 -Update. Tus backups y perfiles se conservan.'
        }
    } catch { Write-HLLog DEBUG "Versión no comparable: $($latest.Tag)" }
}

# --------------------------------------------------------------------------
# Rollback
# --------------------------------------------------------------------------

function Undo-HLManifestEntry {
    param([Parameter(Mandatory)] $Entry)

    switch ($Entry.Type) {
        'Registry' {
            if ($Entry.PrevExists) {
                $val = $Entry.PrevValue
                if ($Entry.PrevKind -eq 'Binary' -and $val -is [string]) { $val = [Convert]::FromBase64String($val) }
                if ($Entry.PrevKind -eq 'MultiString' -and $val -isnot [array]) { $val = @($val) }
                if (-not (Test-Path $Entry.Path)) { New-Item -Path $Entry.Path -Force | Out-Null }
                New-ItemProperty -Path $Entry.Path -Name $Entry.Name -Value $val -PropertyType $Entry.PrevKind -Force | Out-Null
            } else {
                Remove-ItemProperty -Path $Entry.Path -Name $Entry.Name -Force -ErrorAction SilentlyContinue
                if ($Entry.KeyCreated -and (Test-Path $Entry.Path)) {
                    $k = Get-Item $Entry.Path
                    if ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item $Entry.Path -Force -ErrorAction SilentlyContinue }
                }
            }
            return "Registro $($Entry.Path)\$($Entry.Name)"
        }
        'File' {
            if ($Entry.PrevExists -and $Entry.BackupCopy -and (Test-Path -LiteralPath $Entry.BackupCopy)) {
                $attr = Get-Item -LiteralPath $Entry.Path -ErrorAction SilentlyContinue
                if ($attr -and $attr.IsReadOnly) { $attr.IsReadOnly = $false }
                Copy-Item -LiteralPath $Entry.BackupCopy -Destination $Entry.Path -Force
            } elseif (-not $Entry.PrevExists) {
                Remove-Item -LiteralPath $Entry.Path -Force -ErrorAction SilentlyContinue
            }
            return "Archivo $($Entry.Path)"
        }
        'PowerScheme' {
            if ($Entry.PrevActive) { & powercfg.exe /setactive $Entry.PrevActive | Out-Null }
            if ($Entry.Created) { & powercfg.exe /delete $Entry.Created 2>$null | Out-Null }
            return "Plan de energía -> $($Entry.PrevActive)"
        }
        'PowerSetting' {
            & powercfg.exe /setacvalueindex $Entry.Scheme $Entry.SubGroup $Entry.Setting $Entry.PrevAC | Out-Null
            return "Ajuste de energía $($Entry.Setting)"
        }
        'Dns' {
            $servers = @($Entry.PrevServers | Where-Object { $_ })
            if ($servers.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceIndex $Entry.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $Entry.InterfaceIndex -ServerAddresses $servers -ErrorAction Stop
            }
            return "DNS en $($Entry.InterfaceAlias)"
        }
        'TcpAutoTuning' {
            & netsh.exe int tcp set global ("autotuninglevel={0}" -f $Entry.PrevLevel.ToLowerInvariant()) | Out-Null
            return "TCP autotuning -> $($Entry.PrevLevel)"
        }
        'NetAdapterProperty' {
            Set-NetAdapterAdvancedProperty -Name $Entry.Adapter -RegistryKeyword $Entry.Keyword -RegistryValue $Entry.PrevValue -NoRestart -ErrorAction Stop
            return "NIC $($Entry.Adapter) $($Entry.Keyword)"
        }
        'QosPolicy' {
            Remove-NetQosPolicy -Name $Entry.Name -PolicyStore ActiveStore -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetQosPolicy -Name $Entry.Name -Confirm:$false -ErrorAction SilentlyContinue
            return "QoS $($Entry.Name)"
        }
        'ScheduledTask' {
            Stop-ScheduledTask -TaskName $Entry.Name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $Entry.Name -Confirm:$false -ErrorAction SilentlyContinue
            if ($Entry.ProcessMatch) {
                Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like "*$($Entry.ProcessMatch)*" } |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            }
            # Modo partida: si se mató a mitad de sesión, devolver servicios, prioridades y plan.
            $rs = $Entry.PSObject.Properties['RestoreScript']
            if ($rs -and $rs.Value -and (Test-Path $rs.Value)) {
                & $rs.Value -Root $Entry.RestoreRoot -RestoreOnly
            }
            return "Tarea programada $($Entry.Name)"
        }
        'Acl' {
            if (Test-Path $Entry.Path) {
                $acl = Get-Acl -Path $Entry.Path
                $id = New-Object Security.Principal.NTAccount($Entry.Identity)
                $acl.PurgeAccessRules($id)
                Set-Acl -Path $Entry.Path -AclObject $acl
            }
            return "Permiso de $($Entry.Identity) en $($Entry.Path)"
        }
        'Bcd' {
            if ($Entry.Created) { & bcdedit.exe /deletevalue '{current}' $Entry.Element | Out-Null }
            return "BCD $($Entry.Element)"
        }
        'DisplayMode' {
            . $Entry.ModulePath
            Initialize-HLDisplayApi
            $r = [Hardline.DisplayApi]::SetRefresh($Entry.Device, [int]$Entry.Width, [int]$Entry.Height, [int]$Entry.PrevHz)
            if ($r -ne 0) { throw "Windows rechazó volver a $($Entry.PrevHz) Hz (código $r)." }
            return "Refresco $($Entry.Device) -> $($Entry.PrevHz) Hz"
        }
        'AudioEndpointName' {
            . $Entry.ModulePath
            Initialize-HLEndpointApi
            $hr = [Hardline.AudioEndpoints]::Rename($Entry.Id, $Entry.PrevName)
            if ($hr -ne 0) { throw ("Windows no dejó devolver el nombre ""{0}"" (0x{1:X8})." -f $Entry.PrevName, $hr) }
            return "Nombre de audio -> $($Entry.PrevName)"
        }
        'Info' { return $null }
        default { throw "Tipo de entrada desconocido: $($Entry.Type)" }
    }
}

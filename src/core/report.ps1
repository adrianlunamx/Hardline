#Requires -Version 5.1
<#
    Hardline - reporte final en reports/YYYY-MM-DD_HH-MM.txt
#>

function Save-HLBenchmark {
    param($Bench)
    if (-not $Bench) { return }
    $path = Join-Path $HL.ReportDir ("bench_{0}_{1}.json" -f $HL.Stamp, $Bench.Phase.ToLowerInvariant())
    $Bench | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
}

function Get-HLLastBenchmark {
    param([ValidateSet('pre', 'post')] [string]$Phase = 'pre')
    $f = Get-ChildItem $HL.ReportDir -Filter "bench_*_$Phase.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    return (Get-Content $f.FullName -Raw | ConvertFrom-Json)
}

function Write-HLReport {
    param([Parameter(Mandatory)] $Hardware)

    $path = Join-Path $HL.ReportDir ("{0}.txt" -f $HL.Stamp)
    $sb = New-Object System.Text.StringBuilder
    function L([string]$s = '') { [void]$sb.AppendLine($s) }

    L "HARDLINE v$HLVersion - reporte"
    L ("Fecha: {0:yyyy-MM-dd HH:mm}   Equipo: {1}   Usuario: {2}" -f (Get-Date), $env:COMPUTERNAME, $env:USERNAME)
    if ($HL.DryRun) { L 'MODO DRYRUN: no se aplicó ningún cambio.' }
    L ('=' * 78)
    L ''
    L 'HARDWARE'
    L ('  CPU      {0} ({1}C/{2}T, {3})' -f $Hardware.CPU.Name, $Hardware.CPU.Cores, $Hardware.CPU.Threads, $Hardware.CPU.Family)
    if ($Hardware.GPU.Primary) { L ('  GPU      {0} {1}GB, driver {2}' -f $Hardware.GPU.Primary.Name, $Hardware.GPU.Primary.VRAMGB, $Hardware.GPU.Primary.DriverVersion) }
    L ('  RAM      {0}GB {1} @ {2} MT/s, EXPO/XMP {3}' -f $Hardware.RAM.TotalGB, $Hardware.RAM.Type, $Hardware.RAM.SpeedMTs, $Hardware.RAM.Profile)
    L ('  Disco    {0} {1}' -f $Hardware.Storage.SystemBus, $Hardware.Storage.SystemModel)
    L ('  Placa    {0} {1}, BIOS {2}' -f $Hardware.Board.Vendor, $Hardware.Board.Product, $Hardware.Board.BiosVersion)
    L ('  OS       {0} build {1}' -f $Hardware.OS.Caption, $Hardware.OS.Build)
    if ($Hardware.Game.Primary) { L ('  Warzone  {0}' -f $Hardware.Game.Primary) }
    L ''

    foreach ($status in @('Applied', 'Manual', 'Failed', 'Skipped', 'Info')) {
        $items = @($HL.Results | Where-Object { $_.Status -eq $status })
        if ($items.Count -eq 0) { continue }
        $title = switch ($status) {
            'Applied' { 'CAMBIOS APLICADOS' } 'Manual' { 'REQUIERE ACCIÓN MANUAL' } 'Failed' { 'FALLOS' }
            'Skipped' { 'OMITIDO (ya estaba bien o no aplica)' } 'Info' { 'INFORMACIÓN' }
        }
        L "$title ($($items.Count))"
        foreach ($i in $items) { L ('  [{0}] {1}: {2}' -f $i.Module, $i.Item, $i.Detail) }
        L ''
    }

    if ($HL.Manual.Count -gt 0) {
        L 'PASOS MANUALES (BIOS, Adrenalin, Windows, juego)'
        $n = 1
        foreach ($group in ($HL.Manual | Group-Object Area)) {
            L "  $($group.Name)"
            foreach ($m in $group.Group) {
                L ("   {0,2}. {1}" -f $n, $m.Text)
                if ($m.Link) { L ("       {0}" -f $m.Link) }
                $n++
            }
        }
        L ''
    }

    $cmp = @(Format-HLBenchComparison -Pre $HL.BenchPre -Post $HL.BenchPost)
    if ($cmp.Count -gt 0) {
        L 'BENCHMARK'
        foreach ($r in $cmp) { L "  $r" }
        L '  Nota: timer resolution, HAGS y servicios se aplican del todo tras reiniciar.'
        L '  Para medir después del reinicio: .\install.ps1 -BenchmarkOnly'
        L ''
    }

    L 'REVERTIR'
    L "  Todo lo de esta sesión:   .\rollback.ps1 -Stamp $($HL.Stamp)"
    L '  Última sesión:            .\rollback.ps1'
    L '  Alternativa:              Panel de control > Recuperación > Restaurar sistema > punto "Hardline_*"'
    L "  Manifiesto de cambios:    $(Join-Path $HL.BackupDir 'manifest.json')"
    L "  Log detallado:            $($HL.LogFile)"
    if ($HL.NeedsReboot) { L ''; L 'REINICIO NECESARIO para completar los cambios.' }

    if (-not (Test-Path $HL.ReportDir)) { New-Item -ItemType Directory -Path $HL.ReportDir -Force | Out-Null }
    Set-Content -Path $path -Value $sb.ToString() -Encoding UTF8
    return $path
}

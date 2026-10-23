<#
.SYNOPSIS
    Ejecuta el mantenimiento de SQL Server sobre todas las bases de usuario y guarda un log.

.EXAMPLE
    .\99_ejecutar_todo.ps1 -Instancia 'SRVDB01\SQLEXPRESS'
    .\99_ejecutar_todo.ps1 -Instancia 'SRVDB01' -SoloReporte

.NOTES
    Requiere el módulo SqlServer:  Install-Module SqlServer -Scope CurrentUser
    Autor: Juan Sebastián Ortiz Quintero
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Instancia,
    [switch]$SoloReporte,
    [string]$CarpetaLogs = (Join-Path $PSScriptRoot 'logs')
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer

New-Item -ItemType Directory -Force -Path $CarpetaLogs | Out-Null
$log = Join-Path $CarpetaLogs ("mantenimiento_{0:yyyyMMdd_HHmm}.log" -f (Get-Date))
function Log($m) { $l = "{0:HH:mm:ss}  {1}" -f (Get-Date), $m; $l | Tee-Object -FilePath $log -Append }

$comun = @{ ServerInstance = $Instancia; TrustServerCertificate = $true; QueryTimeout = 0; Verbose = $true }

if ($SoloReporte) {
    $salida = Join-Path $CarpetaLogs ("reporte_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date))
    Invoke-Sqlcmd @comun -Database master -InputFile (Join-Path $PSScriptRoot '05_reporte_salud.sql') |
        Format-Table -AutoSize | Out-String -Width 400 | Set-Content $salida -Encoding UTF8
    Log "Reporte generado: $salida"
    return
}

$bases = Invoke-Sqlcmd @comun -Database master -Query `
    "SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE' AND is_read_only = 0" |
    Select-Object -ExpandProperty name

Log "Instancia $Instancia - bases: $($bases -join ', ')"

foreach ($db in $bases) {
    foreach ($paso in '01_indices.sql', '02_estadisticas.sql') {
        try {
            Invoke-Sqlcmd @comun -Database $db -InputFile (Join-Path $PSScriptRoot $paso) 4>&1 |
                ForEach-Object { Log "[$db] $_" }
        }
        catch { Log "[$db] ERROR en ${paso}: $($_.Exception.Message)" }
    }
}

# Integridad una vez por semana (domingo)
if ((Get-Date).DayOfWeek -eq 'Sunday') {
    Invoke-Sqlcmd @comun -Database master -InputFile (Join-Path $PSScriptRoot '03_integridad.sql') 4>&1 |
        ForEach-Object { Log "[CHECKDB] $_" }
}

Log 'Mantenimiento terminado'

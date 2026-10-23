# Mantenimiento de SQL Server

Scripts T‑SQL y PowerShell para mantener sanas las bases de datos de SQL Server en empresas pequeñas y medianas, incluidas las instalaciones **Express**, que no traen planes de mantenimiento ni Agente SQL.

## Contenido

| Script | Qué hace | Frecuencia sugerida |
|---|---|---|
| `01_indices.sql` | Reorganiza o reconstruye índices según su fragmentación | Diaria o semanal |
| `02_estadisticas.sql` | Actualiza solo las estadísticas con cambios significativos | Diaria |
| `03_integridad.sql` | `DBCC CHECKDB` en todas las bases y guarda historial | Semanal |
| `04_respaldos.sql` | Respaldos FULL, DIFF y LOG con `CHECKSUM` y verificación | Ver abajo |
| `05_reporte_salud.sql` | Reporte de estado: tamaños, respaldos, CHECKDB, discos, CPU, esperas | Bajo demanda |
| `99_ejecutar_todo.ps1` | Ejecuta índices + estadísticas en todas las bases y deja log | Tarea programada |

## Criterios de mantenimiento de índices

| Fragmentación | Acción |
|---|---|
| Menos de 10 % | Nada |
| 10 % a 30 % | `REORGANIZE` |
| Más de 30 % | `REBUILD` (`ONLINE` en Enterprise) |

Los índices con menos de 1000 páginas se omiten: su fragmentación no afecta el rendimiento y reconstruirlos solo genera carga.

Para revisar qué se haría sin tocar nada, cambie `@SoloMostrar = 1` en `01_indices.sql`.

## Estrategia de respaldos

| Tipo | Cuándo | Para qué |
|---|---|---|
| FULL | Domingo 22:00 | Punto base de restauración |
| DIFF | Lunes a sábado 22:00 | Restaurar rápido sin aplicar toda la semana de logs |
| LOG | Cada 30 min | Recuperar hasta minutos antes de una falla (modelo FULL) |

Cada respaldo se crea con `CHECKSUM` y se verifica con `RESTORE VERIFYONLY`. El reporte de salud marca **FULL VENCIDO** o **LOG VENCIDO** si algo dejó de correr.

## Uso con PowerShell

```powershell
Install-Module SqlServer -Scope CurrentUser

# Mantenimiento completo
.\99_ejecutar_todo.ps1 -Instancia 'SRVDB01\SQLEXPRESS'

# Solo el reporte de salud a un archivo de texto
.\99_ejecutar_todo.ps1 -Instancia 'SRVDB01' -SoloReporte
```

En SQL Server Express, programe `99_ejecutar_todo.ps1` con el Programador de tareas de Windows. En ediciones con Agente SQL, cree un trabajo por script.

## Compatibilidad

SQL Server 2016 o superior (Express, Standard, Enterprise) y Azure SQL Managed Instance.

---
Juan Sebastián Ortiz Quintero · Ingeniero en Mecatrónica · [Industrias Ortiz](https://jsortizq.github.io)

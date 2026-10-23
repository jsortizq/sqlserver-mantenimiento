/*
    Reporte de salud del servidor SQL Server
    ----------------------------------------
    Una sola ejecución devuelve lo que reviso primero cuando algo anda lento
    o antes de una auditoría:

      1. Información del servidor
      2. Tamaño y espacio libre de cada base
      3. Último respaldo por base y tipo (alerta si FULL > 7 días o LOG > 1 día)
      4. Último CHECKDB exitoso
      5. Espacio en los discos donde hay archivos de datos
      6. Consultas que más CPU han consumido
      7. Esperas principales del servidor

    Autor: Juan Sebastián Ortiz Quintero
*/
SET NOCOUNT ON;

-- 1. Servidor
SELECT  SERVERPROPERTY('MachineName')     AS Servidor,
        SERVERPROPERTY('ProductVersion')  AS Version,
        SERVERPROPERTY('ProductLevel')    AS Nivel,
        SERVERPROPERTY('Edition')         AS Edicion,
        sqlserver_start_time              AS EncendidoDesde,
        DATEDIFF(DAY, sqlserver_start_time, SYSDATETIME()) AS DiasEncendido,
        cpu_count                         AS CPUs,
        physical_memory_kb / 1024         AS MemoriaMB
FROM    sys.dm_os_sys_info;

-- 2. Tamaño de bases
SELECT  DB_NAME(mf.database_id)                                        AS BaseDatos,
        d.recovery_model_desc                                          AS ModeloRecuperacion,
        CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8 / 1024.0 AS decimal(12,1)) AS DatosMB,
        CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8 / 1024.0 AS decimal(12,1)) AS LogMB
FROM    sys.master_files AS mf
JOIN    sys.databases    AS d ON d.database_id = mf.database_id
GROUP   BY mf.database_id, d.recovery_model_desc
ORDER   BY DatosMB DESC;

-- 3. Últimos respaldos
WITH ult AS (
    SELECT database_name, type, MAX(backup_finish_date) AS Ultimo
    FROM   msdb.dbo.backupset
    GROUP  BY database_name, type
)
SELECT  d.name AS BaseDatos,
        d.recovery_model_desc AS Modelo,
        f.Ultimo AS UltimoFull,
        df.Ultimo AS UltimoDiff,
        l.Ultimo AS UltimoLog,
        CASE
            WHEN f.Ultimo IS NULL                                   THEN 'SIN RESPALDO FULL'
            WHEN f.Ultimo < DATEADD(DAY, -7, SYSDATETIME())         THEN 'FULL VENCIDO'
            WHEN d.recovery_model_desc = 'FULL'
             AND (l.Ultimo IS NULL OR l.Ultimo < DATEADD(DAY, -1, SYSDATETIME())) THEN 'LOG VENCIDO'
            ELSE 'OK'
        END AS Estado
FROM    sys.databases AS d
LEFT JOIN ult AS f  ON f.database_name  = d.name AND f.type  = 'D'
LEFT JOIN ult AS df ON df.database_name = d.name AND df.type = 'I'
LEFT JOIN ult AS l  ON l.database_name  = d.name AND l.type  = 'L'
WHERE   d.name <> 'tempdb'
ORDER   BY Estado DESC, d.name;

-- 4. Último CHECKDB exitoso (dato guardado en la página de arranque de cada base)
DECLARE @dbcc TABLE (ParentObject varchar(255), [Object] varchar(255), Field varchar(255), [Value] varchar(255));
DECLARE @r TABLE (BaseDatos sysname, UltimoCheckDB datetime);
DECLARE @db sysname;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' AND name <> 'tempdb';
OPEN c; FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    DELETE @dbcc;
    INSERT @dbcc EXEC ('DBCC DBINFO(' + '''' + @db + '''' + ') WITH TABLERESULTS, NO_INFOMSGS');
    INSERT @r SELECT TOP (1) @db, TRY_CONVERT(datetime, [Value]) FROM @dbcc WHERE Field = 'dbi_dbccLastKnownGood';
    FETCH NEXT FROM c INTO @db;
END;
CLOSE c; DEALLOCATE c;
SELECT BaseDatos, UltimoCheckDB,
       CASE WHEN UltimoCheckDB < DATEADD(DAY, -7, GETDATE()) OR UltimoCheckDB <= '1900-01-02'
            THEN 'REVISAR' ELSE 'OK' END AS Estado
FROM @r ORDER BY UltimoCheckDB;

-- 5. Discos
SELECT DISTINCT
        vs.volume_mount_point                                     AS Unidad,
        CAST(vs.total_bytes     / 1073741824.0 AS decimal(10,1))  AS TotalGB,
        CAST(vs.available_bytes / 1073741824.0 AS decimal(10,1))  AS LibreGB,
        CAST(vs.available_bytes * 100.0 / vs.total_bytes AS decimal(5,1)) AS [Libre %]
FROM    sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
ORDER   BY [Libre %];

-- 6. Consultas con más CPU desde el último reinicio
SELECT TOP (10)
        DB_NAME(st.dbid)                                         AS BaseDatos,
        qs.execution_count                                       AS Ejecuciones,
        qs.total_worker_time / 1000                              AS CPUTotalMs,
        qs.total_worker_time / qs.execution_count / 1000         AS CPUPromedioMs,
        qs.total_logical_reads / qs.execution_count              AS LecturasPromedio,
        SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                  ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS Consulta
FROM    sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER   BY qs.total_worker_time DESC;

-- 7. Esperas principales (excluye esperas benignas)
SELECT TOP (10)
        wait_type                                    AS Espera,
        CAST(wait_time_ms / 1000.0 AS decimal(14,1)) AS Segundos,
        CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER () AS decimal(5,1)) AS [%]
FROM    sys.dm_os_wait_stats
WHERE   wait_type NOT IN (
            'SLEEP_TASK','BROKER_TASK_STOP','BROKER_TO_FLUSH','SQLTRACE_BUFFER_FLUSH','CLR_AUTO_EVENT',
            'CLR_MANUAL_EVENT','LAZYWRITER_SLEEP','SLEEP_SYSTEMTASK','WAITFOR','XE_TIMER_EVENT',
            'XE_DISPATCHER_WAIT','REQUEST_FOR_DEADLOCK_SEARCH','LOGMGR_QUEUE','CHECKPOINT_QUEUE',
            'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_EVENTHANDLER','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
            'SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE','BROKER_RECEIVE_WAITFOR','XE_LIVE_TARGET_TVF')
  AND   wait_time_ms > 0
ORDER   BY wait_time_ms DESC;

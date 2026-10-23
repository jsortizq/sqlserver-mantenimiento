/*
    Actualización de estadísticas
    -----------------------------
    Actualiza solo las estadísticas que tuvieron cambios desde la última vez,
    usando un muestreo mayor en tablas pequeñas y FULLSCAN en las que tienen
    muchas modificaciones relativas.

    Autor: Juan Sebastián Ortiz Quintero
*/
SET NOCOUNT ON;

DECLARE @PorcentajeCambio float = 10.0;   -- % de filas modificadas para actualizar

DECLARE @Pendientes TABLE (Comando nvarchar(max), Filas bigint, Cambios bigint);

INSERT INTO @Pendientes (Comando, Filas, Cambios)
SELECT N'UPDATE STATISTICS ' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + N'.' + QUOTENAME(o.name)
       + N' ' + QUOTENAME(st.name)
       + CASE WHEN sp.rows < 500000 OR sp.modification_counter * 100.0 / NULLIF(sp.rows, 0) > 30
              THEN N' WITH FULLSCAN;'
              ELSE N' WITH SAMPLE 30 PERCENT;'
         END,
       sp.rows,
       sp.modification_counter
FROM   sys.stats AS st
JOIN   sys.objects AS o ON o.object_id = st.object_id
CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) AS sp
WHERE  o.is_ms_shipped = 0
  AND  o.type = 'U'
  AND  sp.modification_counter > 0
  AND  sp.modification_counter * 100.0 / NULLIF(sp.rows, 0) >= @PorcentajeCambio;

DECLARE @cmd nvarchar(max), @n int = 0;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Comando FROM @Pendientes ORDER BY Cambios DESC;
OPEN c;
FETCH NEXT FROM c INTO @cmd;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql @cmd;
        SET @n += 1;
    END TRY
    BEGIN CATCH
        PRINT CONCAT('ERROR: ', ERROR_MESSAGE(), ' -> ', @cmd);
    END CATCH;
    FETCH NEXT FROM c INTO @cmd;
END;
CLOSE c;
DEALLOCATE c;

PRINT CONCAT('Estadísticas actualizadas: ', @n);

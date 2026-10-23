/*
    Mantenimiento de índices según fragmentación
    ---------------------------------------------
    - Fragmentación entre 10 % y 30 %  -> REORGANIZE
    - Fragmentación mayor a 30 %       -> REBUILD (ONLINE si la edición lo permite)
    - Ignora índices pequeños (< 1000 páginas): reorganizarlos no aporta nada.

    Uso: ejecutar en la base de datos objetivo, o desde 99_ejecutar_todo.ps1.
    @SoloMostrar = 1 lista lo que haría sin ejecutar nada.

    Autor: Juan Sebastián Ortiz Quintero
*/
SET NOCOUNT ON;

DECLARE @SoloMostrar     bit = 0;
DECLARE @MinPaginas      int = 1000;
DECLARE @UmbralReorg     float = 10.0;
DECLARE @UmbralRebuild   float = 30.0;
DECLARE @Online          bit = CASE WHEN SERVERPROPERTY('EngineEdition') IN (3, 5, 8) THEN 1 ELSE 0 END; -- Enterprise / Azure

DECLARE @Trabajo TABLE (
    Esquema        sysname,
    Tabla          sysname,
    Indice         sysname,
    Fragmentacion  float,
    Paginas        bigint,
    Accion         varchar(10),
    Comando        nvarchar(max)
);

INSERT INTO @Trabajo (Esquema, Tabla, Indice, Fragmentacion, Paginas, Accion)
SELECT  s.name,
        t.name,
        i.name,
        ps.avg_fragmentation_in_percent,
        ps.page_count,
        CASE WHEN ps.avg_fragmentation_in_percent >= @UmbralRebuild THEN 'REBUILD' ELSE 'REORGANIZE' END
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ps
JOIN    sys.indexes  AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN    sys.tables   AS t ON t.object_id = i.object_id
JOIN    sys.schemas  AS s ON s.schema_id = t.schema_id
WHERE   ps.avg_fragmentation_in_percent >= @UmbralReorg
  AND   ps.page_count >= @MinPaginas
  AND   i.name IS NOT NULL            -- excluye heaps
  AND   ps.alloc_unit_type_desc = 'IN_ROW_DATA';

UPDATE @Trabajo
SET Comando = N'ALTER INDEX ' + QUOTENAME(Indice) + N' ON ' + QUOTENAME(Esquema) + N'.' + QUOTENAME(Tabla)
            + CASE Accion
                WHEN 'REBUILD' THEN N' REBUILD WITH (SORT_IN_TEMPDB = ON'
                                   + CASE WHEN @Online = 1 THEN N', ONLINE = ON' ELSE N'' END + N');'
                ELSE N' REORGANIZE;'
              END;

SELECT Esquema, Tabla, Indice,
       CAST(Fragmentacion AS decimal(5,1)) AS [Fragmentacion %],
       Paginas, Accion
FROM   @Trabajo
ORDER  BY Fragmentacion DESC;

IF @SoloMostrar = 1
BEGIN
    PRINT 'Modo solo mostrar: no se ejecutó ningún cambio.';
    RETURN;
END;

DECLARE @cmd nvarchar(max), @inicio datetime2;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Comando FROM @Trabajo ORDER BY Fragmentacion DESC;
OPEN c;
FETCH NEXT FROM c INTO @cmd;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @inicio = SYSDATETIME();
    BEGIN TRY
        EXEC sys.sp_executesql @cmd;
        PRINT CONCAT('OK  (', DATEDIFF(SECOND, @inicio, SYSDATETIME()), ' s) ', @cmd);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('ERROR ', ERROR_NUMBER(), ': ', ERROR_MESSAGE(), ' -> ', @cmd);
    END CATCH;
    FETCH NEXT FROM c INTO @cmd;
END;
CLOSE c;
DEALLOCATE c;

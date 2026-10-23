/*
    Respaldos completos, diferenciales y de log
    -------------------------------------------
    @Tipo = 'FULL' | 'DIFF' | 'LOG'
    Los archivos quedan en @Ruta\<Base>\<Base>_<TIPO>_aaaammdd_hhmm.<bak|trn>
    con compresión (si la edición lo soporta) y CHECKSUM, y se verifican con
    RESTORE VERIFYONLY.

    Programación sugerida (Agente SQL Server):
      FULL  domingo 22:00
      DIFF  lunes a sábado 22:00
      LOG   cada 30 min (solo bases en modelo FULL)

    Autor: Juan Sebastián Ortiz Quintero
*/
SET NOCOUNT ON;

DECLARE @Tipo  varchar(4)     = 'FULL';
DECLARE @Ruta  nvarchar(260)  = N'E:\SQL\Backups';

DECLARE @comprimir bit = CASE WHEN SERVERPROPERTY('EngineEdition') = 4 THEN 0 ELSE 1 END; -- Express no comprime
DECLARE @fecha nvarchar(13) = FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmm');
DECLARE @db sysname, @carpeta nvarchar(400), @archivo nvarchar(500), @sql nvarchar(max);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE  database_id > 4
      AND  state_desc = 'ONLINE'
      AND  (@Tipo <> 'LOG' OR recovery_model_desc = 'FULL')
    ORDER  BY name;

OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @carpeta = @Ruta + N'\' + @db;
    EXEC master.dbo.xp_create_subdir @carpeta;

    SET @archivo = @carpeta + N'\' + @db + N'_' + @Tipo + N'_' + @fecha
                 + CASE WHEN @Tipo = 'LOG' THEN N'.trn' ELSE N'.bak' END;

    SET @sql = CASE @Tipo
                 WHEN 'LOG' THEN N'BACKUP LOG '      + QUOTENAME(@db)
                 ELSE            N'BACKUP DATABASE ' + QUOTENAME(@db)
               END
             + N' TO DISK = @archivo WITH CHECKSUM, INIT'
             + CASE WHEN @Tipo = 'DIFF' THEN N', DIFFERENTIAL' ELSE N'' END
             + CASE WHEN @comprimir = 1 THEN N', COMPRESSION' ELSE N'' END
             + N';';

    BEGIN TRY
        EXEC sys.sp_executesql @sql, N'@archivo nvarchar(500)', @archivo = @archivo;
        RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;
        PRINT CONCAT('OK    ', @Tipo, '  ', @db, '  ->  ', @archivo);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('ERROR ', @Tipo, '  ', @db, ': ', ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM c INTO @db;
END;
CLOSE c;
DEALLOCATE c;

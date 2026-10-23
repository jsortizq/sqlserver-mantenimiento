/*
    Chequeo de integridad de todas las bases de usuario
    ---------------------------------------------------
    Ejecuta DBCC CHECKDB en cada base ONLINE y deja el resultado en la tabla
    dbo.HistorialIntegridad de la base de administración (por defecto: master).
    Recomendado: una vez por semana, fuera del horario laboral.

    Autor: Juan Sebastián Ortiz Quintero
*/
SET NOCOUNT ON;

IF OBJECT_ID('dbo.HistorialIntegridad') IS NULL
    CREATE TABLE dbo.HistorialIntegridad (
        Id         int IDENTITY PRIMARY KEY,
        BaseDatos  sysname       NOT NULL,
        Inicio     datetime2(0)  NOT NULL,
        Fin        datetime2(0)  NULL,
        Resultado  varchar(10)   NOT NULL,
        Mensaje    nvarchar(4000) NULL
    );

DECLARE @db sysname, @inicio datetime2(0), @sql nvarchar(400);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE  database_id > 4 AND state_desc = 'ONLINE' AND is_read_only = 0
    ORDER  BY name;

OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @inicio = SYSDATETIME();
    SET @sql = N'DBCC CHECKDB (' + QUOTENAME(@db) + N') WITH NO_INFOMSGS, ALL_ERRORMSGS;';
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
        INSERT dbo.HistorialIntegridad (BaseDatos, Inicio, Fin, Resultado)
        VALUES (@db, @inicio, SYSDATETIME(), 'OK');
        PRINT CONCAT('OK     ', @db);
    END TRY
    BEGIN CATCH
        INSERT dbo.HistorialIntegridad (BaseDatos, Inicio, Fin, Resultado, Mensaje)
        VALUES (@db, @inicio, SYSDATETIME(), 'ERROR', ERROR_MESSAGE());
        PRINT CONCAT('ERROR  ', @db, ': ', ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM c INTO @db;
END;
CLOSE c;
DEALLOCATE c;

SELECT TOP (50) * FROM dbo.HistorialIntegridad ORDER BY Id DESC;

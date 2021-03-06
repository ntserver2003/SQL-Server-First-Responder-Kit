﻿-- Sample script to restore db-yesterday
DECLARE @dbSrc NVARCHAR(256)
       ,@dbDst NVARCHAR(256)
       ,@BackupRoot NVARCHAR(256)
       ,@DataRoot NVARCHAR(256)
       ,@Execute CHAR(1)
       ,@Debug BIT
       ,@ExistingDbAction TINYINT
       ,@DatabaseOwner SYSNAME
       ,@StopAt NVARCHAR(14);

-- Main parameters
-- Execute Y|N
SET @Execute = 'N';
-- Debug 0|1
SET @Debug = 0
-- source db name
SET @dbSrc = N'DBA';
-- destination db name
SET @dbDst = @dbSrc + N'-yesterday';
-- backup root folder
SET @BackupRoot = N'D:\MSSQL\Backup\';
-- data root folder
SET @DataRoot = N'D:\MSSQL\Data\';
/* Existing DB Action
  0 - Do nothing
  1 - SET Single user
  2 - KILL connections
  3 - DROP Database
  4 - OFFLINE database
  */
SET @ExistingDBAction = 3;
-- Set db_owner for Clr
SET @DatabaseOwner = N'sa';
-- Set restore time
SET @StopAt = REPLACE(CONVERT(NVARCHAR(20), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), 120), N'-', N'') + N'235959';

--region db folders
DECLARE @BackupPathFull NVARCHAR(256)
       ,@BackupPathDiff NVARCHAR(256)
       ,@MoveDataDrive NVARCHAR(256)
       ,@MoveLogDrive NVARCHAR(256);

SET @BackupPathFull = FORMATMESSAGE('%s\%s\FULL\', @BackupRoot, @dbSrc);
SET @BackupPathDiff = FORMATMESSAGE('%s\%s\DIFF\', @BackupRoot, @dbSrc);
SET @MoveDataDrive = FORMATMESSAGE('%s\%s', @DataRoot, @dbDst);
SET @MoveLogDrive = FORMATMESSAGE('%s\%s', @DataRoot, @dbDst);
--endregion db folders

--region create destination db folders
DECLARE @FileListSimple TABLE (
  BackupFile NVARCHAR(255) NOT NULL
 ,depth INT NOT NULL
);
DECLARE @tmp NVARCHAR(256);

SET @tmp = @MoveDataDrive + '\..';
INSERT INTO @FileListSimple (BackupFile, depth) EXEC master.sys.xp_dirtree @tmp
                                                                          ,1
                                                                          ,0;

IF NOT EXISTS (SELECT 1 FROM @FileListSimple)
  EXEC master.sys.xp_create_subdir @MoveDataDrive;

DELETE @FileListSimple;

SET @tmp = @MoveLogDrive + '\..';
INSERT INTO @FileListSimple (BackupFile, depth) EXEC master.sys.xp_dirtree @tmp
                                                                          ,1
                                                                          ,0;

IF NOT EXISTS (SELECT 1 FROM @FileListSimple)
  EXEC master.sys.xp_create_subdir @MoveLogDrive
--endregion

EXEC dbo.sp_DatabaseRestore @Database = @dbSrc
                           ,@BackupPathFull = @BackupPathFull
                           ,@BackupPathDiff = @BackupPathDiff
                           ,@RestoreDatabaseName = @dbDst
                           ,@MoveDataDrive = @MoveDataDrive
                           ,@MoveLogDrive = @MoveLogDrive
                           ,@RestoreDiff = 1
                            -- Switch restored DB to Simple mode
                           ,@ForceSimpleRecovery = 1
                           ,@ExistingDBAction = @ExistingDbAction
                           ,@ContinueLogs = 0
                           ,@RunRecovery = 1
                           ,@TestRestore = 0
                           ,@RunCheckDB = 0
                           ,@DatabaseOwner = @DatabaseOwner
                           ,@Debug = @Debug
                           ,@StopAt = @StopAt
                           ,@Execute = @Execute;

-- execute shrink database
DECLARE @sql NVARCHAR(MAX)
       ,@quotedDbName NVARCHAR(256);
SET @quotedDbName = QUOTENAME(@dbDst);
SET @sql = FORMATMESSAGE(N'DBCC SHRINKDATABASE(%s);', @quotedDbName);
IF @Debug = 1 OR @Execute = 'N'
  RAISERROR ('DBCC SHRINKDATABASE', 0, 1) WITH NOWAIT;
IF @Execute = 'Y'
  EXECUTE @sql = [dbo].[CommandExecute] @DatabaseContext = N'master'
                                       ,@Command = @sql
                                       ,@CommandType = 'DBCC SHRINKDATABASE'
                                       ,@Mode = 1
                                       ,@DatabaseName = @dbDst
                                       ,@LogToTable = 'Y'
                                       ,@Execute = 'Y';

-- set TRUSTWORTHY
SET @sql = FORMATMESSAGE(N'ALTER DATABASE %s SET TRUSTWORTHY ON;', @quotedDbName);
IF @Debug = 1 OR @Execute = 'N'
  RAISERROR ('SET TRUSTWORTHY ON', 0, 1) WITH NOWAIT;
IF @Execute = 'Y'
  EXECUTE @sql = [dbo].[CommandExecute] @DatabaseContext = N'master'
                                       ,@Command = @sql
                                       ,@CommandType = 'ALTER DATABASE SET TRUSTWORTHY ON'
                                       ,@Mode = 1
                                       ,@DatabaseName = @dbDst
                                       ,@LogToTable = 'Y'
                                       ,@Execute = 'Y';

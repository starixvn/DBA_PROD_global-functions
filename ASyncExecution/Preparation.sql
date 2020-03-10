/*
	Creator:	20200212@Billy
	Task:		ASync Service Broker Preparation - [Redmine: #000000]
	Server:		
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
GO


--	BEGIN STEP :
--		Storage
----------------------------------------------------------------------------------------------------

-- Filegroup --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Filegroup]			= fg.name
		,	[DataSpaceId]		= fg.data_space_id
		,	[Query]				= CASE	WHEN fg.data_space_id IS NULL THEN N'\
ALTER DATABASE ' + QUOTENAME(DB_NAME()) + N'
	ADD FILEGROUP ASYNC;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.filegroups AS fg WITH (NOLOCK)
			ON	fg.name = 'async';
END;

-- File --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[File]				= f.name
		,	[FileId]			= f.file_id
		,	[Type]				= f.type_desc
		,	[State]				= f.state_desc
		,	[Query]				= CASE	WHEN f.data_space_id IS NULL THEN N'\
ALTER DATABASE	' + QUOTENAME(DB_NAME()) + N'
	ADD FILE (
		NAME		= N''' + DB_NAME() + N'_ASync''
	,	FILENAME	= N''' + fp.BasePath + DB_NAME() + N'_ASync.ndf''
	,	SIZE		= 64MB
	,	FILEGROWTH	= 64MB
	) TO FILEGROUP ASYNC;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.database_files AS f WITH (NOLOCK)
			ON	f.name = DB_NAME() + '_ASync'
	OUTER APPLY	(
		SELECT	[BasePath]	= LEFT(physical_name, LEN(physical_name) - CHARINDEX('\', REVERSE(physical_name), 0)) + N'\'
		FROM	sys.database_files AS _f WITH (NOLOCK)
		WHERE	_f.file_id = 1
	) AS fp;
END;
GO


--	BEGIN STEP :
--		Schema for ASync
----------------------------------------------------------------------------------------------------

-- Schema --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Schema]			= sch.name
		,	[SchemaId]			= sch.schema_id
		,	[Authorization]		= USER_NAME(sch.principal_id)
		,	[Query]				= CASE	WHEN sch.schema_id IS NULL THEN N'\
CREATE SCHEMA	async
	AUTHORIZATION dbo;'
										WHEN USER_NAME(sch.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON SCHEMA::async TO dbo;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.schemas AS sch WITH (NOLOCK)
			ON	sch.name = 'async';
END;
GO


--	BEGIN STEP :
--		Enable Service Broker
----------------------------------------------------------------------------------------------------

-- Service Broker Status --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Status]			= CASE	WHEN db.is_broker_enabled = 1 THEN 'ENABLED'
										ELSE ''
								  END
		,	[Query]				= CASE	WHEN db.is_broker_enabled = 0 THEN N'\
USE	master;
ALTER DATABASE ' + QUOTENAME(DB_NAME()) + N' SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.databases AS db WITH (NOLOCK)
			ON	db.database_id = DB_ID();
END;
GO


--	BEGIN STEP :
--		Create Service for ASync
----------------------------------------------------------------------------------------------------

-- Message Type --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[MsgType]			= smt.name
		,	[MsgTypeId]			= smt.message_type_id
		,	[Authorization]		= USER_NAME(smt.principal_id)
		,	[Validation]		= smt.validation_desc
		,	[Query]				= CASE	WHEN smt.message_type_id IS NULL THEN N'\
CREATE MESSAGE TYPE	ASyncQuery
	AUTHORIZATION dbo
	VALIDATION = NONE;'
										WHEN USER_NAME(smt.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON MESSAGE TYPE::ASyncQuery TO dbo;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.service_message_types AS smt WITH (NOLOCK)
			ON	smt.name = N'ASyncQuery';
END;

-- Contract --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Contract]			= sc.name
		,	[ContractId]		= sc.service_contract_id
		,	[Authorization]		= USER_NAME(sc.principal_id)
		,	[Query]				= CASE	WHEN sc.service_contract_id IS NULL THEN N'\
CREATE CONTRACT	ASyncContract
	AUTHORIZATION dbo (
		ASyncQuery		SENT BY INITIATOR
	);

--GRANT REFERENCES ON CONTRACT::ASyncContract TO xxx;'
										WHEN USER_NAME(sc.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON CONTRACT::ASyncContract TO dbo;'
										ELSE N''
								  END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.service_contracts AS sc WITH (NOLOCK)
			ON	sc.name = N'ASyncContract';
END;

-- Initiator --
BEGIN;
	-- Initiator Activation Procedure --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Schema]			= SCHEMA_NAME(sp.schema_id)
			,	[Procedure]			= sp.name
			,	[ObjectId]			= sp.object_id
			,	[Definition]		= sm.definition
			,	[ExecuteAs]			= CASE	WHEN sm.execute_as_principal_id = -2 THEN N'OWNER'
											WHEN sm.object_id IS NOT NULL AND sm.execute_as_principal_id IS NULL THEN N'CALLER'
											ELSE USER_NAME(sm.execute_as_principal_id)
									  END
			,	[Query]				= CASE	WHEN sp.object_id IS NULL THEN N'\
CREATE PROCEDURE	async.ASyncInitiatorQueueActivator
AS
BEGIN;
	SET NOCOUNT ON;
END;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.procedures AS sp WITH (NOLOCK)
				ON	sp.name = N'ASyncInitiatorQueueActivator'
		LEFT JOIN	sys.sql_modules AS sm WITH (NOLOCK)
				ON	sp.object_id = sm.object_id;
	END;

	-- Initiator Queue --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Schema]			= SCHEMA_NAME(sq.schema_id)
			,	[Queue]				= sq.name
			,	[ObjectId]			= sq.object_id
			,	[MaxReaders]		= sq.max_readers
			,	[ActivationSP]		= sq.activation_procedure
			,	[ExecuteAs]			= CASE	WHEN sq.execute_as_principal_id = -2 THEN N'OWNER'
											WHEN sq.activation_procedure IS NOT NULL AND sq.execute_as_principal_id IS NULL THEN N'CALLER'
											ELSE USER_NAME(sq.execute_as_principal_id)
									  END
			,	[Activation]		= sq.is_activation_enabled
			,	[Receive]			= sq.is_receive_enabled
			,	[EnQueue]			= sq.is_enqueue_enabled
			,	[Retention]			= sq.is_retention_enabled
			,	[PoisonHandling]	= sq.is_poison_message_handling_enabled
			,	[Query]				= CASE	WHEN sq.object_id IS NULL THEN N'\
CREATE QUEUE	async.ASyncInitiatorQueue
	WITH	ACTIVATION (
				STATUS				= ON
			,	PROCEDURE_NAME		= async.ASyncInitiatorQueueActivator
			,	MAX_QUEUE_READERS	= 10
			,	EXECUTE AS OWNER
			)
	ON ASYNC;

--GRANT RECEIVE ON async.ASyncInitiatorQueue TO xxx;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.service_queues AS sq WITH (NOLOCK)
				ON	sq.name = N'ASyncInitiatorQueue';
	END;

	-- Initiator Service --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Service]			= svc.name
			,	[ServiceId]			= svc.service_id
			,	[Authorization]		= USER_NAME(svc.principal_id)
			,	[Queue]				= OBJECT_NAME(svc.service_queue_id)
			,	[Query]				= CASE	WHEN svc.service_id IS NULL THEN N'\
CREATE SERVICE	ASyncInitiator
	AUTHORIZATION dbo
	ON QUEUE	async.ASyncInitiatorQueue (
					ASyncContract
				);

--GRANT SEND ON SERVICE::ASyncInitiator TO PUBLIC;'
											WHEN USER_NAME(svc.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON SERVICE::ASyncInitiator TO dbo;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.services AS svc WITH (NOLOCK)
				ON	svc.name = N'ASyncInitiator';
	END;
END;

-- Target --
BEGIN;
	-- Target Activation Procedure --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Schema]			= SCHEMA_NAME(sp.schema_id)
			,	[Procedure]			= sp.name
			,	[ObjectId]			= sp.object_id
			,	[Definition]		= sm.definition
			,	[ExecuteAs]			= CASE	WHEN sm.execute_as_principal_id = -2 THEN N'OWNER'
											WHEN sm.object_id IS NOT NULL AND sm.execute_as_principal_id IS NULL THEN N'CALLER'
											ELSE USER_NAME(sm.execute_as_principal_id)
									  END
			,	[Query]				= CASE	WHEN sp.object_id IS NULL THEN N'\
CREATE PROCEDURE	async.ASyncTargetQueueActivator
AS
BEGIN;
	SET NOCOUNT ON;
END;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.procedures AS sp WITH (NOLOCK)
				ON	sp.name = N'ASyncTargetQueueActivator'
		LEFT JOIN	sys.sql_modules AS sm WITH (NOLOCK)
				ON	sp.object_id = sm.object_id;
	END;

	-- Target Queue --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Schema]			= SCHEMA_NAME(sq.schema_id)
			,	[Queue]				= sq.name
			,	[ObjectId]			= sq.object_id
			,	[MaxReaders]		= sq.max_readers
			,	[ActivationSP]		= sq.activation_procedure
			,	[ExecuteAs]			= CASE	WHEN sq.execute_as_principal_id = -2 THEN N'OWNER'
											WHEN sq.activation_procedure IS NOT NULL AND sq.execute_as_principal_id IS NULL THEN N'CALLER'
											ELSE USER_NAME(sq.execute_as_principal_id)
									  END
			,	[Activation]		= sq.is_activation_enabled
			,	[Receive]			= sq.is_receive_enabled
			,	[EnQueue]			= sq.is_enqueue_enabled
			,	[Retention]			= sq.is_retention_enabled
			,	[PoisonHandling]	= sq.is_poison_message_handling_enabled
			,	[Query]				= CASE	WHEN sq.object_id IS NULL THEN N'\
CREATE QUEUE	async.ASyncTargetQueue
	WITH	ACTIVATION (
				STATUS				= ON
			,	PROCEDURE_NAME		= async.ASyncTargetQueueActivator
			,	MAX_QUEUE_READERS	= 10
			,	EXECUTE AS OWNER
			)
	ON ASYNC;

--GRANT RECEIVE ON async.ASyncTargetQueue TO xxx;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.service_queues AS sq WITH (NOLOCK)
				ON	sq.name = N'ASyncTargetQueue';
	END;

	-- Target Service --
	BEGIN;
		SELECT	[ ]					= step.msg
			,	[Service]			= svc.name
			,	[ServiceId]			= svc.service_id
			,	[Authorization]		= USER_NAME(svc.principal_id)
			,	[Queue]				= OBJECT_NAME(svc.service_queue_id)
			,	[Query]				= CASE	WHEN svc.service_id IS NULL THEN N'\
CREATE SERVICE	ASyncTarget
	AUTHORIZATION dbo
	ON QUEUE	async.ASyncTargetQueue (
					ASyncContract
				);

--GRANT SEND ON SERVICE::ASyncTarget TO PUBLIC;'
											WHEN USER_NAME(svc.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON SERVICE::ASyncTarget TO dbo;'
											ELSE N''
									  END
		FROM		(
			VALUES	(QUOTENAME(DB_NAME()))
		) AS step(msg)
		LEFT JOIN	sys.services AS svc WITH (NOLOCK)
				ON	svc.name = N'ASyncTarget';
	END;
END;
GO


--	BEGIN STEP :
--		Tables
----------------------------------------------------------------------------------------------------

-- Service Broker Failed Message --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Schema]			= SCHEMA_NAME(tbl.schema_id)
		,	[Table]				= tbl.name
		,	[ObjectId]			= tbl.object_id
		,	[Query]				= CASE	WHEN tbl.object_id IS NULL THEN N'\
CREATE TABLE	async.ASyncServiceFailedLogs (
					LogDate		DATETIME
				,	ServiceName	NVARCHAR(128)
				,	Msg			XML
				) ON ASYNC;

CREATE CLUSTERED INDEX	CIX_ASyncServiceFailedLogs ON async.ASyncServiceFailedLogs (
							ServiceName	ASC
						,	LogDate		ASC
						) WITH (DATA_COMPRESSION = PAGE) ON ASYNC;

CREATE NONCLUSTERED INDEX	IX_ASyncServiceFailedLogs_LogDate ON async.ASyncServiceFailedLogs (
								LogDate	ASC
							) WITH (DATA_COMPRESSION = PAGE) ON ASYNC;'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.tables AS tbl WITH (NOLOCK)
			ON	tbl.name = N'ASyncServiceFailedLogs';
END;

-- Failed Log --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Schema]			= SCHEMA_NAME(tbl.schema_id)
		,	[Table]				= tbl.name
		,	[ObjectId]			= tbl.object_id
		,	[Query]				= CASE	WHEN tbl.object_id IS NULL THEN N'\
CREATE TABLE	async.ASyncActivationFailedLogs (
					LogDate		DATETIME
				,	Msg			NVARCHAR(MAX)
				,	ErrorMsg	NVARCHAR(MAX)
				) ON ASYNC;

CREATE CLUSTERED INDEX	CIX_ASyncActivationFailedLogs ON async.ASyncActivationFailedLogs (
							LogDate	ASC
						) WITH (DATA_COMPRESSION = PAGE) ON ASYNC;'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.tables AS tbl WITH (NOLOCK)
			ON	tbl.name = N'ASyncActivationFailedLogs';
END;

-- Queue Initiator View --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Schema]			= SCHEMA_NAME(obj.schema_id)
		,	[View]				= obj.name
		,	[ObjectId]			= obj.object_id
		,	[Query]				= CASE	WHEN obj.object_id IS NULL THEN N'\
CREATE VIEW	async.ASyncInitiatorQueueView
AS
SELECT	[status]					= q.status
	,	[conversation_group_id]		= q.conversation_group_id
	,	[priority]					= q.priority
	,	[conversation_handle]		= q.conversation_handle
	,	[queuing_order]				= q.queuing_order
	,	[message_sequence_number]	= q.message_sequence_number
	,	[service_name]				= q.service_name
	,	[service_contract_name]		= q.service_contract_name
	,	[message_type_name]			= q.message_type_name
	,	[validation]				= q.validation
	,	[message_body]				= CAST(q.message_body AS NVARCHAR(MAX))
FROM	async.ASyncInitiatorQueue AS q WITH (NOLOCK);'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.objects AS obj WITH (NOLOCK)
			ON	obj.name = N'ASyncInitiatorQueueView'
			AND	obj.type = 'V';
END;

-- Queue Target View --
BEGIN;
	SELECT	[ ]					= step.msg
		,	[Schema]			= SCHEMA_NAME(obj.schema_id)
		,	[View]				= obj.name
		,	[ObjectId]			= obj.object_id
		,	[Query]				= CASE	WHEN obj.object_id IS NULL THEN N'\
CREATE VIEW	async.ASyncTargetQueueView
AS
SELECT	[status]					= q.status
	,	[conversation_group_id]		= q.conversation_group_id
	,	[priority]					= q.priority
	,	[conversation_handle]		= q.conversation_handle
	,	[queuing_order]				= q.queuing_order
	,	[message_sequence_number]	= q.message_sequence_number
	,	[service_name]				= q.service_name
	,	[service_contract_name]		= q.service_contract_name
	,	[message_type_name]			= q.message_type_name
	,	[validation]				= q.validation
	,	[message_body]				= CAST(q.message_body AS NVARCHAR(MAX))
FROM	async.ASyncTargetQueue AS q WITH (NOLOCK);'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.objects AS obj WITH (NOLOCK)
			ON	obj.name = N'ASyncTargetQueueView'
			AND	obj.type = 'V';
END;
GO


--	BEGIN STEP :
--		External access - Security
----------------------------------------------------------------------------------------------------

BEGIN;
	-- Input --
	DECLARE	@CertPassword		NVARCHAR(MAX) = N'W`=Q5GY*WJEm)M)>18#*axd)uJixBM}Q'
		,	@CertSubject		NVARCHAR(MAX) = N'Certificate for ASync to access server level permission'
		,	@CertBackupPassword	NVARCHAR(MAX) = N'X2$FPg0wI079>8>u[IYmfkZ8K^52?kys'
		;

	DECLARE	@Drives AS TABLE (
				Drive			NVARCHAR(128)
					PRIMARY KEY CLUSTERED
			,	Free			INT
			);

	DECLARE	@Status AS TABLE (
			FileExists				BIT
		,	isDirectory				BIT
		,	ParentDirectoryExists	BIT
		,	Path					NVARCHAR(4000)
		);

	DECLARE	@Path		NVARCHAR(4000)
		,	@File		NVARCHAR(4000)
		;

	-- Check Certificate Folder --
	INSERT INTO	@Drives (Drive, Free)
	EXECUTE	sys.xp_fixeddrives;

	SELECT	TOP(1)
			@Path = d.Drive + ':\Certificates'
	FROM	@Drives AS d
	WHERE	d.Drive > 'C'
	ORDER BY d.Drive ASC;

	DELETE	@Status;

	SELECT	@File = @Path + N'\ASyncAccessCertificate.cer';
	INSERT INTO	@Status (FileExists, isDirectory, ParentDirectoryExists)
	EXECUTE	sys.xp_fileexist @File;
	UPDATE	@Status
	SET		Path = @File
	WHERE	Path IS NULL;

	SELECT	@File = @Path + N'\ASyncAccessCertificate.pvk';
	INSERT INTO	@Status (FileExists, isDirectory, ParentDirectoryExists)
	EXECUTE	sys.xp_fileexist @File;
	UPDATE	@Status
	SET		Path = @File
	WHERE	Path IS NULL;

	-- Create Certificate --
	SELECT	[ ]					= step.msg
		,	[Certificate]		= crt.name
		,	[CertificateId]		= crt.certificate_id
		,	[Authorization]		= USER_NAME(crt.principal_id)
		,	[Subject]			= crt.subject
		,	[ExpiryDate]		= crt.expiry_date
		,	[PrivateKeyEncrypt]	= crt.pvt_key_encryption_type_desc
		,	[Query]				= CASE	WHEN crt.certificate_id IS NULL AND cer.FileExists & pvk.FileExists = 1 THEN N'\
CREATE CERTIFICATE	ASyncAccessCertificate
AUTHORIZATION dbo
FROM FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.cer', NCHAR(39)) + N'
WITH PRIVATE KEY (
	FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.pvk', NCHAR(39)) + N'
,	DECRYPTION BY PASSWORD = ' + QUOTENAME(@CertBackupPassword, NCHAR(39)) + N'
,	ENCRYPTION BY PASSWORD = ' + QUOTENAME(@CertPassword, NCHAR(39)) + N'
);'
										WHEN crt.certificate_id IS NULL AND cer.FileExists & pvk.FileExists = 0 THEN N'\
CREATE CERTIFICATE	ASyncAccessCertificate
AUTHORIZATION dbo
ENCRYPTION BY PASSWORD = ' + QUOTENAME(@CertPassword, NCHAR(39)) + N'
WITH	SUBJECT		= ' + QUOTENAME(@CertSubject, NCHAR(39)) + N'
	,	EXPIRY_DATE	= ' + QUOTENAME(N'2049-12-31', NCHAR(39)) + '
	;'
										WHEN USER_NAME(crt.principal_id) <> N'dbo' THEN N'\
ALTER AUTHORIZATION ON CERTIFICATE::ASyncAccessCertificate TO dbo;'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.certificates AS crt WITH (NOLOCK)
			ON	crt.name = N'ASyncAccessCertificate'
	LEFT JOIN	@Status AS cer
			ON	cer.Path = @Path + N'\ASyncAccessCertificate.cer'
	LEFT JOIN	@Status AS pvk
			ON	pvk.Path = @Path + N'\ASyncAccessCertificate.pvk';

	-- Backup Folder --
	SELECT	[ ]					= step.msg
		,	[BackupFolder]		= cer.ParentDirectoryExists
		,	[Query]				= CASE	WHEN cer.ParentDirectoryExists = 0 THEN N'\
EXECUTE	sys.xp_create_subdir ' + QUOTENAME(@Path, NCHAR(39)) + N';'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	@Status AS cer
			ON	cer.Path = @Path + N'\ASyncAccessCertificate.cer';

	-- Backup Certificate --
	SELECT	[ ]					= step.msg
		,	[CertBackup]		= cer.FileExists
		,	[CertPvkBackup]		= pvk.FileExists
		,	[Query]				= CASE	WHEN cer.ParentDirectoryExists & pvk.ParentDirectoryExists = 1 AND cer.FileExists = 0 AND pvk.FileExists = 0 THEN N'\
BACKUP CERTIFICATE	ASyncAccessCertificate
TO FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.cer', NCHAR(39)) + '
WITH PRIVATE KEY (
	FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.pvk', NCHAR(39)) + '
,	DECRYPTION BY PASSWORD = ' + QUOTENAME(@CertPassword, NCHAR(39)) + N'
,	ENCRYPTION BY PASSWORD = ' + QUOTENAME(@CertBackupPassword, NCHAR(39)) + N'
);'
										WHEN cer.ParentDirectoryExists & pvk.ParentDirectoryExists = 1 AND cer.FileExists = 0 AND pvk.FileExists = 1 THEN N'\
BACKUP CERTIFICATE	ASyncAccessCertificate
TO FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.cer', NCHAR(39)) + ';'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	@Status AS cer
			ON	cer.Path = @Path + N'\ASyncAccessCertificate.cer'
	LEFT JOIN	@Status AS pvk
			ON	pvk.Path = @Path + N'\ASyncAccessCertificate.pvk';

	-- Master Certificate --
	SELECT	[ ]					= step.msg
		,	[Certificate]		= crt.name
		,	[CertificateId]		= crt.certificate_id
		,	[Authorization]		= USER_NAME(crt.principal_id)
		,	[Subject]			= crt.subject
		,	[ExpiryDate]		= crt.expiry_date
		,	[PrivateKeyEncrypt]	= crt.pvt_key_encryption_type_desc
		,	[Query]				= CASE	WHEN crt.certificate_id IS NULL THEN N'\
USE master;
CREATE CERTIFICATE	ASyncAccessCertificate
AUTHORIZATION dbo
FROM	FILE = ' + QUOTENAME(@Path + N'\ASyncAccessCertificate.cer', NCHAR(39)) + N';
USE ' + QUOTENAME(DB_NAME()) + N';'
										WHEN USER_NAME(crt.principal_id) <> N'dbo' THEN N'\
USE master;
ALTER AUTHORIZATION ON CERTIFICATE::ASyncAccessCertificate TO dbo;
USE ' + QUOTENAME(DB_NAME()) + N';'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	master.sys.certificates AS crt WITH (NOLOCK)
			ON	crt.name = N'ASyncAccessCertificate';

	-- Certificate Login --
	SELECT	[ ]					= step.msg
		,	[Login]				= lgn.name
		,	[PrincipalId]		= lgn.principal_id
		,	[SecurityId]		= lgn.sid
		,	[Type]				= lgn.type_desc
		,	[Enabled]			= ~lgn.is_disabled
		,	[Query]				= CASE	WHEN lgn.principal_id IS NULL THEN N'\
USE master;
CREATE LOGIN		ASyncLogin
FROM CERTIFICATE	ASyncAccessCertificate;
GRANT AUTHENTICATE SERVER TO ASyncLogin;
USE ' + QUOTENAME(DB_NAME()) + ';'
										ELSE N''
									END
	FROM		(
		VALUES	(QUOTENAME(DB_NAME()))
	) AS step(msg)
	LEFT JOIN	sys.server_principals AS lgn WITH (NOLOCK)
			ON	lgn.name = N'ASyncLogin';
END;
GO
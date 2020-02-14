SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	async.ASyncTargetQueueActivator
WITH EXECUTE AS OWNER
AS
/*
	Creator:	20200212@Billy
	Task:		Activator for ASync Target Service Queue - [Redmine: #127620]
	Database:	
	
	Revisions:
		- 20200212@Billy:	Initial - [Redmine: #127620]
		
	Developer's Notes:
		- @Example:			NULL		- Explaination [DEFAULT]
		
*/
BEGIN;
	SET NOCOUNT ON;

	-- Service Broker variables --
	DECLARE	@Dialog				UNIQUEIDENTIFIER
		,	@Type				NVARCHAR(256)
		,	@Message			NVARCHAR(MAX)
		,	@ErrorNo			INT
		,	@ErrorMsg			NVARCHAR(MAX)
		;

	-- Get message from queue --
	RECEIVE	TOP(1)
			@dialog		= conversation_handle
		,	@type		= message_type_name
		,	@message	= CAST(message_body AS NVARCHAR(MAX))
	FROM	async.ASyncTargetQueue;

	-- Execute new monitoring task --
	IF	@Type = N'ASyncQuery'
	BEGIN;
		BEGIN TRY;
			EXECUTE	sys.sp_executesql @query = @Message;

			END CONVERSATION @Dialog;
		END TRY
		BEGIN CATCH;
			SELECT	@ErrorNo	= ERROR_NUMBER()
				,	@ErrorMsg	= ERROR_MESSAGE()
				;

			INSERT INTO	async.ASyncActivationFailedLogs (LogDate, Msg, ErrorMsg)
			VALUES	(GETDATE(), @Message, @ErrorMsg);

			END CONVERSATION @Dialog
			WITH	ERROR		= @ErrorNo
					DESCRIPTION	= @ErrorMsg
				;
		END CATCH;
	END;

	-- End conversation with Error --
	IF	@Type = 'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
	BEGIN;
		INSERT INTO	async.ASyncServiceFailedLogs (LogDate, ServiceName, Msg)
		VALUES	(GETDATE(), 'ASyncTarget', @Message);

		END CONVERSATION @Dialog WITH CLEANUP;

		SELECT	@Message = N'\
Service Broker Error - [ASyncInitiator]
' + @@SERVERNAME + N'.' + DB_NAME() + N'

' + @Message;
		EXECUTE	DBNOTI.NotificationDB.dbo.Skype_SendMessage N'BILLY', @Message;
	END;

	-- End conversation --
	IF	@Type = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
	BEGIN;
		END CONVERSATION @Dialog WITH CLEANUP;
	END;
END;
GO

ADD SIGNATURE TO OBJECT::async.ASyncTargetQueueActivator
BY CERTIFICATE ASyncAccessCertificate
WITH PASSWORD = 'W`=Q5GY*WJEm)M)>18#*axd)uJixBM}Q';
GO
/*<info serverAlias="DBDCHK-CheckDataDB" executers="" viewers="" isFunction="0" isNested="0"></info>*/
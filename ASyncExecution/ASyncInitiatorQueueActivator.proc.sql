SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	async.ASyncInitiatorQueueActivator
WITH EXECUTE AS OWNER
AS
/*
	Creator:	20200213@Billy
	Task:		Activator for ASync Initiator Service Queue - [Redmine: #127620]
	Database:	
	
	Revisions:
		- 20200213@Billy:	Initial - [Redmine: #127620]
		
	Developer's Notes:
		- @Example:			NULL		- Explaination [DEFAULT]
		
*/
BEGIN;
	SET NOCOUNT ON;

	-- Service Broker variables --
	DECLARE	@Dialog				UNIQUEIDENTIFIER
		,	@Type				NVARCHAR(256)
		,	@Message			NVARCHAR(MAX)
		;

	-- Get message from queue --
	RECEIVE	TOP(1)
			@Dialog		= conversation_handle
		,	@Type		= message_type_name
		,	@Message	= CAST(message_body AS NVARCHAR(MAX))
	FROM	async.ASyncInitiatorQueue;

	-- End conversation with Error --
	IF	@Type = 'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
	BEGIN;
		INSERT INTO	async.ASyncServiceFailedLogs (LogDate, ServiceName, Msg)
		VALUES	(GETDATE(), 'ASyncInitiator', @Message);

		END CONVERSATION @Dialog WITH CLEANUP;
	END;

	-- End conversation --
	IF	@Type = N'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
	BEGIN;
		END CONVERSATION @Dialog WITH CLEANUP;
	END;
END;
GO

ADD SIGNATURE TO OBJECT::async.ASyncInitiatorQueueActivator
BY CERTIFICATE ASyncAccessCertificate
WITH PASSWORD = 'W`=Q5GY*WJEm)M)>18#*axd)uJixBM}Q';
GO
/*<info serverAlias="DBDCHK-CheckDataDB" executers="" viewers="" isFunction="0" isNested="0"></info>*/
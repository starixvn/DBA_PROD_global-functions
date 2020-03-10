SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	async.ASyncExecution
						@Query				NVARCHAR(MAX)
					,	@ConversationGroup	UNIQUEIDENTIFIER	= NULL
					,	@Lifetime			INT					= 172800
AS
/*
	Creator:	20200213@Billy
	Task:		ASync Query Execution - [Redmine: #127620]
	Database:	

	Revisions:
		- 20200213@Billy:	Initial - [Redmine: #127620]

	Developer's Notes:
		- @Query:				[REQUIRED]		- The content of message that will be send to ASync
		- @ConversationGroup:	[optional]		- The conversation group that the message will be in
					<DEFAULT>	NULL			- The message will be in its own converstaion group.
		- @Lifetime:			[optional]		- The dialog created will expired after this amount of seconds
					<DEFAULT>	172800			- 48 hours
		
*/
BEGIN;
	SET NOCOUNT ON;

	-- Service Broker variables --
	DECLARE	@Dialog				UNIQUEIDENTIFIER
		;

	-- Send message --
	IF	@ConversationGroup IS NULL
	BEGIN;
		BEGIN DIALOG CONVERSATION	@Dialog
		FROM SERVICE	ASyncInitiator
		TO SERVICE		'ASyncTarget'
		ON CONTRACT		ASyncContract
		WITH	LIFETIME					= @Lifetime
			,	ENCRYPTION					= OFF
			;
	END;
	ELSE
	BEGIN;
		BEGIN DIALOG CONVERSATION	@Dialog
		FROM SERVICE	ASyncInitiator
		TO SERVICE		'ASyncTarget'
		ON CONTRACT		ASyncContract
		WITH	RELATED_CONVERSATION_GROUP	= @ConversationGroup
			,	LIFETIME					= @Lifetime
			,	ENCRYPTION					= OFF
			;
	END;

	IF	@@ERROR = 0
	AND	@Dialog IS NOT NULL
	BEGIN;
		SEND ON CONVERSATION @Dialog MESSAGE TYPE ASyncQuery (@Query);
	END;
END;
GO
/*<info serverAlias="DBDCHK-CheckDataDB,FPSMON-FPS_MONITOR" executers="" viewers="" isFunction="0" isNested="1"></info>*/
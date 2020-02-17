SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	async.ASyncErrorHandling
					@Pattern				NVARCHAR(MAX)
				,	@From					DATETIME			= NULL
				,	@Debug					BIT					= 0
AS
/*
	Creator:	20200217@Billy
	Task:		ASync Query Error Handling - [Redmine: #127620]
	Database:	

	Revisions:
		- 20200217@Billy:	Initial - [Redmine: #127620]

	Developer's Notes:
		- @Pattern:				[REQUIRED]		- The start of the messages that will be picked.
		- @From:				[optional]		- The time when to start picking message.
					<DEFAULT>	NULL			- All messages.
		- @Debug:				[optional]		- Print debug messages.
					<DEFAULT>	0				- Not print.
								1				- Print.
*/
BEGIN;
	SET NOCOUNT ON;

	-- Variables --
	DECLARE	@_From			DATETIME
		,	@Id				INT
		,	@Query			NVARCHAR(MAX)
		;

	-- Debug variables --
	DECLARE	@Rowcount		INT
		;

	-- Temporary tables --
	CREATE TABLE	#FailedQueries (
						Id				INT				IDENTITY(1, 1)
					,	Query			NVARCHAR(MAX)
					,	PRIMARY KEY CLUSTERED (Id)
					);

	-- Reform parameter --
	SELECT	@_From = ISNULL(@From, 0);

	-- Pick failed messages --
	DELETE	async.ASyncActivationFailedLogs
	OUTPUT	Deleted.Msg
	INTO	#FailedQueries(Query)
	WHERE	LogDate >= @_From
		AND	Msg LIKE @Pattern + '%';

	SELECT	@Rowcount = @@ROWCOUNT;

	IF	@Debug = 1 AND @Rowcount > 0
	BEGIN;
		RAISERROR(N'\
[VERBOSE]	ASyncErrorHandling:
			Picked %d queries to re-execute.', 0, 0, @Rowcount) WITH NOWAIT;
	END;

	WHILE	0 = 0
	BEGIN;
		SELECT	TOP(1)
				@Id		= q.Id
			,	@Query	= q.Query
		FROM	#FailedQueries AS q WITH (NOLOCK);

		IF	@@ROWCOUNT = 0
			BREAK;

		EXECUTE	async.ASyncExecution @Query;

		DELETE	#FailedQueries WITH (ROWLOCK)
		WHERE	Id = @Id;
	END;
END;
GO
/*<info serverAlias="DBDCHK-CheckDataDB" executers="" viewers="" isFunction="0" isNested="1"></info>*/
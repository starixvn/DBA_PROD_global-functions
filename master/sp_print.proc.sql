SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	dbo.sp_print
						@Msg				NVARCHAR(MAX)
AS
/*
	Creator:	20200218@Billy
	Task:		Print large text - [Redmine: #000000]
	Database:	

	Revisions:
		- 20200218@Billy:	Initial - [Redmine: #000000]

	Developer's Notes:
		- @Msg:					[REQUIRED]		- Message to be printed
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	DECLARE	@message	NVARCHAR(MAX);

	SELECT	@message = @Msg;

	SELECT	@message = RTRIM(@message);

	DECLARE	@cr				CHAR(1)		= CHAR(13)
		,	@lf				CHAR(1)		= CHAR(10)
		,	@sp				CHAR(1)		= CHAR(32)
		,	@tb				CHAR(1)		= CHAR(09)
		;

	DECLARE	@len			INT
		,	@cr_index		INT
		,	@lf_index		INT
		,	@crlf_index		INT
		,	@sp_index		INT
		,	@tb_index		INT
		,	@left			NVARCHAR(4000)
		,	@reverse		NVARCHAR(4000)
		;

	WHILE	LEN(@message) > 0
	BEGIN;
		SELECT	@reverse	= RTRIM(REVERSE(LEFT(@message, 1000)))
			;
		SELECT	@crlf_index	= CHARINDEX(@lf + @cr, @reverse)
			,	@lf_index	= CHARINDEX(@lf, @reverse)
			,	@cr_index	= CHARINDEX(@cr, @reverse)
			,	@sp_index	= CHARINDEX(@sp, @reverse)
			,	@tb_index	= CHARINDEX(@tb, @reverse)
			;

		IF		@crlf_index <> 0
		BEGIN;
			SELECT	@left		= LEFT(REVERSE(@reverse), LEN(@reverse) - @crlf_index + 1)
			SELECT	@len		= LEN(@left) + 1
		END;
		ELSE IF	@lf_index <> 0
		BEGIN;
			SELECT	@left		= LEFT(REVERSE(@reverse), LEN(@reverse) - @lf_index + 0)
			SELECT	@len		= LEN(@left) + 2
		END;
		ELSE IF	@cr_index <> 0
		BEGIN;
			SELECT	@left		= LEFT(REVERSE(@reverse), LEN(@reverse) - @cr_index + 0)
			SELECT	@len		= LEN(@left) + 2
		END;
		ELSE IF	@tb_index <> 0
		BEGIN;
			SELECT	@left		= LEFT(REVERSE(@reverse), LEN(@reverse) - @tb_index + 0)
			SELECT	@len		= LEN(@left) + 2
		END;
		ELSE IF	@sp_index <> 0
		BEGIN;
			SELECT	@left		= LEFT(REVERSE(@reverse), LEN(@reverse) - @sp_index + 0)
			SELECT	@len		= LEN(@left) + 2
		END;
		ELSE
		BEGIN;
			SELECT	@left		= REVERSE(@reverse)
			SELECT	@len		= LEN(@left) + 1
		END;

		SELECT	@left		= REPLACE(@left, '%', '%%');
		RAISERROR(@left, 0, 0) WITH NOWAIT;

		SELECT	@message	= LTRIM(SUBSTRING(@message, @len, LEN(@message)));
	END;
END;
GO
EXECUTE	sys.sp_ms_marksystemobject 'sp_print';
GO
/*<info serverAlias="DBDCHK-master" executers="" viewers="" isFunction="0" isNested="1"></info>*/
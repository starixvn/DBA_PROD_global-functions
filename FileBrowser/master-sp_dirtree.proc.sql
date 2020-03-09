SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE PROCEDURE	dbo.sp_dirtree
						@path			NVARCHAR(MAX)
					,	@depth			INT					= 1
					,	@file			BIT					= 1
AS
/*
	Creator:	20200309@Billy
	Task:		Visualize version of xp_dirtree - [Redmine: #112758]
	Database:	master

	Revisions:
		- 20200309@Billy:	Initial - [Redmine: #112758]

	Developer's Notes:
		- @path:					[REQUIRED]		- The root path to trace from
		- @depth:					[optional]		- Number of nested folder to trace
						<DEFAULT>	1				- Only list item in current folder
									NULL			- List all
									0				- List all
		- @file:					[optional]		- Is file listed?
						<DEFAULT>	1				- Yes - List files and folders
									0				- No - List folders only
*/
BEGIN;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET NOCOUNT ON;

	-- Variables --
	DECLARE	@_depth			INT
		,	@_path			NVARCHAR(MAX)
		,	@current_hie	HIERARCHYID
		,	@current_dir	NVARCHAR(MAX)
		;

	-- Dynamic Query --
	DECLARE	@Query			NVARCHAR(MAX)
		;

	DECLARE	@xp_fileexist AS TABLE (
				file_exists			BIT
			,	is_directory		BIT
			,	parent_dir_exists	BIT
			);

	DECLARE	@xp_dirtree AS TABLE (
				subdirectory		NVARCHAR(MAX)
			,	depth				INT
			,	is_file				BIT
			);

	DECLARE	@sp_dirtree AS TABLE (
				hie_id				HIERARCHYID
			,	path				NVARCHAR(MAX)
			,	name				NVARCHAR(MAX)
			,	is_file				BIT
			,	is_done				BIT
			,	PRIMARY KEY CLUSTERED (hie_id)
			);


	-- Init input --
	SELECT	@_depth	= ISNULL(NULLIF(@depth, 0), CAST(0x7FFFFFFF AS INT))
		,	@_path	= CASE WHEN RIGHT(@path, 1) <> N'\' THEN @path + N'\' ELSE @path END
		;

	-- Init data --
	DELETE	@xp_fileexist;

	SELECT	@Query = N'';
	SELECT	@Query += N'\
EXECUTE	sys.xp_fileexist N''' + @path + N''';
';

	INSERT INTO	@xp_fileexist(file_exists, is_directory, parent_dir_exists)
	EXECUTE	sys.sp_executesql @Query;

	-- Only work with folder --
	IF	EXISTS (SELECT 1 FROM @xp_fileexist WHERE ~file_exists & is_directory & parent_dir_exists = 1)
	BEGIN;
		INSERT INTO	@sp_dirtree (hie_id, path, name, is_file, is_done)
		VALUES	('/1/', @_path, @_path, 0, 0);
	END;


	WHILE	0 = 0
	BEGIN;
		UPDATE	TOP(1)
				tbl
		SET		is_done = 1
			,	@current_hie = tbl.hie_id
			,	@current_dir = tbl.path
		FROM	@sp_dirtree AS tbl
		WHERE	tbl.is_done = 0
			AND	tbl.is_file = 0;

		IF	@@ROWCOUNT = 0
			BREAK;

		-- Check depth --
		IF	@current_hie.GetLevel() - 1 >= @_depth
			CONTINUE;

		DELETE	@xp_dirtree;

		SELECT	@Query = N'';
		SELECT	@Query += N'\
EXECUTE	sys.xp_dirtree N''' + @current_dir + N''', 1, ' + CAST(@file AS NVARCHAR(MAX)) + N';
';

		INSERT INTO	@xp_dirtree (subdirectory, depth, is_file)
		EXECUTE	sys.sp_executesql @Query;

		INSERT INTO	@sp_dirtree (hie_id, path, name, is_file, is_done)
		SELECT	[hie_id]	= CAST(@current_hie.ToString() + CAST(ROW_NUMBER() OVER(ORDER BY subdirectory) AS VARCHAR(MAX)) + '/' AS HIERARCHYID)
			,	[path]		= @current_dir + subdirectory + CASE is_file WHEN 0 THEN N'\' ELSE N'' END
			,	[name]		= subdirectory
			,	[is_file]	= is_file
			,	[is_done]	= 0
		FROM	@xp_dirtree;
	END;

	-- Select dir tree --
	SELECT	[Tree]		= ISNULL(REPLICATE('|   ', hie_id.GetLevel() - 2), '') + CASE WHEN hie_id.GetLevel() = 1 THEN '' ELSE '|-- ' END + name
		,	[Path]		= path
		,	[isFile]	= is_file
	FROM	@sp_dirtree
	ORDER BY hie_id;

	-- Print dir tree --
	UPDATE	@sp_dirtree
	SET		is_done = 0;

	WHILE	0 = 0
	BEGIN;
		UPDATE	tbl
		SET		is_done			= 1
			,	@current_dir	= ISNULL(REPLICATE('|   ', tbl.hie_id.GetLevel() - 2), '') + CASE WHEN tbl.hie_id.GetLevel() = 1 THEN '' ELSE '|-- ' END + tbl.name
		FROM	(
			SELECT	TOP(1)
					_tbl.hie_id, _tbl.name, _tbl.is_done
			FROM	@sp_dirtree AS _tbl
			WHERE	_tbl.is_done = 0
			ORDER BY _tbl.hie_id
		) AS tbl;

		IF	@@ROWCOUNT = 0
			BREAK;

		RAISERROR(N'%s', 0, 0, @current_dir) WITH NOWAIT;
	END;
END;
GO
EXECUTE	sys.sp_MS_marksystemobject @objname = N'sp_dirtree';
GO
/*<info serverAlias="INTERNAL_FPS-master,INTERNAL_MAINDB-master,INTERNAL_OTHER-master" executers="" viewers="" isFunction="0" isNested="0"></info>*/
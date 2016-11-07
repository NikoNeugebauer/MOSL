/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Memory Optimised Objects within the database
	Version: 0.2.0, November 2016

	Copyright 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/), (http://www.oh22.is/)

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

/*
Known Issues & Limitations: 

Modifications:

*/
declare @SQLServerVersion nvarchar(128) = cast(SERVERPROPERTY('ProductVersion') as NVARCHAR(128)), 
		@SQLServerEdition nvarchar(128) = cast(SERVERPROPERTY('Edition') as NVARCHAR(128));
declare @errorMessage nvarchar(512);

 --Ensure that we are running SQL Server 2016
if substring(@SQLServerVersion,1,CHARINDEX('.',@SQLServerVersion)-1) <> N'13'
begin
	set @errorMessage = (N'You are not running a SQL Server 2016. Your SQL Server version is ' + @SQLServerVersion);
	Throw 51000, @errorMessage, 1;
end

if SERVERPROPERTY('EngineEdition') <> 3 
begin
	set @errorMessage = (N'Your SQL Server 2016 Edition is not an Enterprise or a Developer Edition: Your are running a ' + @SQLServerEdition);
	Throw 51000, @errorMessage, 1;
end

--------------------------------------------------------------------------------------------------------------------
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetObjects' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetObjects as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Memory Optimised Objects within the database
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetObjects(
-- Params --
	@objectType varchar(40) = NULL,					-- Allows to filter Memory Optimised Objects by their type, with possible values 'Table', 'Table Type', 'Stored Proc' & 'Function'
	@tableName nvarchar(256) = NULL,				-- Allows to show data filtered down to the specified table name pattern
	@schemaName nvarchar(256) = NULL,				-- Allows to show data filtered down to the specified schema
	@showWithDependencies bit = 0,					-- Allows to filter Memory Optimised Objects that have dependencies
	@showDependencies bit = 1						-- Controls if the details on the Memory Optimised Objects Dependencies are to be shown or not
-- end of --
) as 
begin
	set nocount on;

	-- Tables
	-- Table Types
	-- Stored Procedures
	-- Functions

	IF OBJECT_ID('tempdb..#FoundObjects') IS NOT NULL
		DROP TABLE #FoundObjects;

	CREATE TABLE #FoundObjects
	(
		ObjectType varchar(40) NOT NULL,
		ObjectName sysname NOT NULL, 
		Durability varchar(20) NOT NULL,
		[RowCount] bigint NOT NULL,
		ReservedInMB Decimal(9,2) NULL
	);

	IF OBJECT_ID('tempdb..#FoundDependencies') IS NOT NULL
		DROP TABLE #FoundDependencies;

	CREATE TABLE #FoundDependencies
	(
		ObjectType varchar(40) NOT NULL,
		ObjectName sysname NOT NULL, 
		RefObjectType varchar(60) NOT NULL,
		ReferencedObject sysname NOT NULL,	
		ReferencedObjectId int NOT NULL,
		ReferenceClass Varchar(60) NOT NULL,
		CallerDependent smallint NOT NULL
	);

	INSERT INTO #FoundObjects
	SELECT ObjectType, ObjectFullName, Durability, 
		ISNULL(st.rows,0),
		cast((memStats.memory_allocated_for_table_kb + memStats.memory_allocated_for_indexes_kb) / 1024.  as decimal(9,2)) as ReservedInMB
		FROM (
			SELECT 'Table' as ObjectType,
				quotename(object_schema_name(tab.object_id)) + '.' + quotename(object_name(tab.object_id)) as ObjectFullName, 
				object_schema_name(tab.object_id) as ObjectSchema,
				object_name(tab.object_id) as ObjectName,
				tab.object_id,
				case tab.durability_desc WHEN 'SCHEMA_AND_DATA' then 'Schema & Data' else 'Schema' end as Durability	
				FROM sys.tables tab
					WHERE tab.is_memory_optimized = 1
			UNION ALL	
			SELECT 'Table Type' as ObjectType,
				quotename(isnull(object_schema_name(schema_id),'dbo')) + '.' + quotename(name) as ObjectFullName, 
				isnull(object_schema_name(schema_id),'dbo') as ObjectSchema,
				name as ObjectName,
				NULL as object_id,
				'None' as Durability
				FROM sys.table_types
				WHERE is_memory_optimized = 1
			UNION ALL
			SELECT 'Stored Proc' as ObjectType,
				quotename(object_schema_name(procs.object_id)) + '.' + quotename(object_name(procs.object_id)) as ObjectFullName, 
				object_schema_name(procs.object_id) as ObjectSchema,
				object_name(procs.object_id) as ObjectName,
				procs.object_id,
				'None' as Durability	
				FROM sys.procedures procs 
					INNER JOIN sys.sql_modules mod
						ON procs.object_id = mod.object_id
				WHERE mod.uses_native_compilation = 1
			UNION ALL
			SELECT 'Function' as ObjectType,
				quotename(object_schema_name(mod.object_id)) + '.' + quotename(object_name(mod.object_id)) as ObjectFullName, 
				object_schema_name(mod.object_id) as ObjectSchema,
				object_name(mod.object_id) as ObjectName,
				mod.object_id,
				'None' as Durability	
				FROM sys.sql_modules mod
					INNER JOIN sys.objects o 
						ON mod.object_id=o.object_id
				WHERE type = 'F' AND mod.uses_native_compilation = 1 
			) F
			LEFT JOIN sys.indexes ind
				on F.object_id = ind.object_id  AND ind.is_primary_key = 1
			OUTER APPLY sys.dm_db_stats_properties (F.object_id,ind.index_id) st
			LEFT JOIN sys.dm_db_xtp_table_memory_stats memStats
				on F.object_id = memStats.object_id
		WHERE ObjectType = ISNULL( @objectType, ObjectType )
			AND (@tableName is null or ObjectName like '%' + @tableName + '%')
			AND (@schemaName is null or ObjectSchema = @schemaName);



	-- Find Dependencies for the Memory Optimised Objects
	IF @showDependencies = 1 
	BEGIN
		INSERT INTO #FoundDependencies
		SELECT found.ObjectType, found.ObjectName
			, obj.type_desc as RefObjectType
			, quotename(referencing_schema_name) + '.' + quotename(referencing_entity_name) as ReferencedObject
			, referencing_id as RefObjectId
			, referencing_class_desc as ReferenceClass
			, is_caller_dependent as CallerDependent
			FROM #FoundObjects found
				OUTER APPLY sys.dm_sql_referencing_entities ( ObjectName, 'OBJECT') refs
				INNER JOIN sys.objects obj
					ON refs.referencing_id = obj.object_id
			WHERE referencing_entity_name IS NOT NULL
				AND found.ObjectType in ('Table') 
				AND found.ObjectType = ISNULL( @objectType, ObjectType )
		UNION ALL 
		SELECT DISTINCT found.ObjectType, found.ObjectName
			, obj.type_desc as RefObjectType
			, quotename(referenced_schema_name) + '.' + quotename(referenced_entity_name) as ReferencedObject
			, referenced_id as RefObjectId
			, referenced_class_desc as ReferenceClass
			, is_caller_dependent as CallerDependent
			FROM #FoundObjects found
				OUTER APPLY sys.dm_sql_referenced_entities ( ObjectName, 'OBJECT') refs
				INNER JOIN sys.objects obj
					ON refs.referenced_id = obj.object_id
			WHERE referenced_entity_name IS NOT NULL
				AND found.ObjectType in ('Function','Stored Proc')
				AND found.ObjectType = ISNULL( @objectType, ObjectType )
			ORDER BY found.ObjectName, ReferencedObject;
	END


	-- Show Found Objects
	SELECT *
		FROM #FoundObjects
		WHERE (@showWithDependencies = 0 OR (@showWithDependencies = 1 AND ObjectName IN (SELECT dep.ObjectName FROM #FoundDependencies dep)))
		ORDER BY ReservedInMB desc

	-- Show Dependencies for the Memory Optimised Objects
	IF @showDependencies = 1 
	BEGIN
		SELECT *
			FROM #FoundDependencies
	END

END

GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Checkpoint Pair Files
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetCheckpointFiles' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetCheckpointFiles as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Checkpoint Pair Files
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetCheckpointFiles(
-- Params --
	@showDetails bit = 1,							-- Allows to show the detailed information on the checkpoint pair files
	@fileStateDesc NVARCHAR(60) = NULL,				-- Allows to filter the CFP details by the file state 
	@fileTypeDesc NVARCHAR(60) = NULL,				-- Allows to filter the CFP details by the file type
	@minInsertedRows BIGINT = NULL,					-- Filters the CFP by the minimum number of inserted rows
	@maxInsertedRows BIGINT = NULL,					-- Filters the CFP by the maximum number of inserted rows
	@minDeletedRows BIGINT = NULL,					-- Filters the CFP by the minimum number of deleted rows
	@maxDeletedRows BIGINT =  NULL 					-- Filters the CFP by the maximum number of deleted rows
-- end of --
) as 
begin
	set nocount on;
	
	SELECT DB_NAME() as DatabaseName
		,count(*) as TotalFiles
		,SUM(case file_type when 1 then 1 when 0 then 1 else 0 end) / 2 as FilePairs
		,cast(SUM((file_size_in_bytes)/(1024.*1024*1024)) as Decimal(9,3)) as ReservedSizeInGB
		,cast(SUM((file_size_used_in_bytes)/(1024.*1024*1024)) as Decimal(9,3)) as UsedSizeInGB
		,SUM(case file_type when 0 then logical_row_count end) as InsertedRows
		,SUM(case file_type when 1 then logical_row_count end) as DeletedRows
		,sum(case state when 0 then 1 else 0 end) as PreCreated
		,sum(case state when 1 then 1 else 0 end) as UnderConstruction
		,sum(case state when 2 then 1 else 0 end) as Active
		,sum(case state when 3 then 1 else 0 end) as MergeTarget
		,sum(case state when 4 then 1 else 0 end) as MergedSource
		,sum(case state when 8 then 1 else 0 end) as LogTrancation
		,sum(case state when 5 then 1 else 0 end) as [Backup/HA]
		,sum(case state when 6 then 1 else 0 end) as Transition
		,sum(case state when 7 then 1 else 0 end) as Tombstone	
		FROM sys.dm_db_xtp_checkpoint_files;

	-- Details on the occupied space
	SELECT [PRECREATED] as PrecreatedInMB,
		   [UNDER CONSTRUCTION] as UnderConstructionInMB,
		   [ACTIVE] as ActiveInMB,
		   [MERGE TARGET] as MergeTargetInMB,
		   [MERGED SOURCE] as MergedSourceInMB,
		   [WAITING FOR LOG TRUNCATION] as WaitingForLogTruncationInMB,
		   [REQUIRED FOR BACKUP/HA] as [Backup/HA in MB],
		   [IN TRANSITION TO TOMBSTONE] as [TransitionInMB],
		   [TOMBSTONE] as TombstoneInMB,
		   cast(EncryptionPercentage as Decimal(9,2)) as [EncryptionPercentage]
		FROM
		(
		SELECT state_desc 
			, isnull(sum(encryption_status) / (count(*) * 100.),0.) as EncryptionPercentage
			--,file_type_desc  
			--,COUNT(*) AS [count]  
			,SUM(file_size_in_bytes) / 1024 / 1024 AS [SizeInMB]   
			FROM sys.dm_db_xtp_checkpoint_files  
			GROUP BY state, state_desc--, file_type, file_type_desc  
			--ORDER BY state, file_type  
		) cfiles
		PIVOT ( SUM(SizeInMB) FOR state_desc in ([PRECREATED],[UNDER CONSTRUCTION],[ACTIVE],[MERGE TARGET],[MERGED SOURCE],[REQUIRED FOR BACKUP/HA],[IN TRANSITION TO TOMBSTONE],[TOMBSTONE],[WAITING FOR LOG TRUNCATION]) ) as PivotCFP;




	-- Show the details on the individual files and their types
	IF @showDetails = 1 
	BEGIN
		select container_id, checkpoint_file_id,--, checkpoint_pair_file_id, 
				f.state as FileState, 
				state_desc as FileStateDesc,
				file_type, file_type_desc, 
				cast(file_size_in_bytes / 1024. / 1024 as Decimal(9,2)) as FileSizeInMB, 
				cast(file_size_used_in_bytes / 1024. / 1024 as Decimal(9,2)) as FileSizeUsedInMB, 
				case file_type when 0 then logical_row_count else 0 end as InsertedRows,
				case file_type when 1 then logical_row_count else 0 end as DeletedRows,
				0 as DropedRows,
				lower_bound_tsn as BeginTSN,
				upper_bound_tsn as EndTSN,
				encryption_status_desc as Encryption
			from sys.dm_db_xtp_checkpoint_files f
			WHERE state_desc = ISNULL(@fileStateDesc,state_desc)
				AND (file_type_desc = ISNULL(@fileTypeDesc,file_type_desc) OR (file_type_desc IS NULL and @fileTypeDesc IS NULL))
				AND isnull(case file_type when 0 then logical_row_count else 0 end,0) >= COALESCE(@minInsertedRows, case file_type when 0 then logical_row_count else 0 end,0)
				AND isnull(case file_type when 0 then logical_row_count else 0 end,0) <= COALESCE(@maxInsertedRows, case file_type when 0 then logical_row_count else 0 end,0)
				AND isnull(case file_type when 1 then logical_row_count end,0) >= COALESCE(@minDeletedRows, case file_type when 1 then logical_row_count end, 0)
				AND isnull(case file_type when 1 then logical_row_count end,0) <= COALESCE(@maxDeletedRows, case file_type when 1 then logical_row_count end, 0)
			ORDER BY f.state;
	END

end

GO




/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Database Configuration
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetDatabaseInfo' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetDatabaseInfo as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Database Configuration
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetDatabaseInfo--(
-- Params --
-- end of --
--) 
as 
begin
	set nocount on;

	DECLARE @pool SYSNAME,
			@dbMemElevateSnapshot bit = 0,
		    @poolMinMemory Decimal(9,2) = NULL,
			@poolMaxMemory Decimal(9,2) = NULL,
			@MemOptFileGroup NVARCHAR(512) = NULL,
			@MemOptFileName NVARCHAR(512) = NULL,
			@MemOptFilePath NVARCHAR(2048) = NULL,
			@MemOptStatus VARCHAR(20) = NULL,
			@memOptTables INT = 0;


	-- Check if the current database is bound to a resource pool
	SELECT @pool = p.name,
		   @poolMinMemory = p.min_memory_percent,
		   @poolMaxMemory = p.max_memory_percent,
		   @dbMemElevateSnapshot = d.is_memory_optimized_elevate_to_snapshot_on
		FROM sys.databases d
			INNER JOIN sys.resource_governor_resource_pools p
				ON d.resource_pool_id = p.pool_id
		WHERE d.name = DB_NAME()
			and p.name <> 'default';


	-- Decode values from the Resource Governor and trans
	SELECT @poolMinMemory = cast(iif( value < value_in_use, value, value_in_use ) as Decimal(18,2)) * @poolMinMemory / 100
		FROM sys.configurations
		WHERE name = 'min server memory (MB)';
	SELECT @poolMaxMemory = cast(iif( value > value_in_use, value, value_in_use ) as Decimal(18,2)) * @poolMaxMemory / 100
		FROM sys.configurations
		WHERE name = 'max server memory (MB)'

	-- Get the information on the database files
	SELECT @MemOptFileGroup = fg.name,
		   @MemOptFileName = files.name,
		   @MemOptFilePath = files.physical_name,
		   @MemOptStatus = files.state_desc
		from sys.filegroups fg
		INNER JOIN sys.database_files files
			on fg.data_space_id = files.data_space_id
		WHERE fg.type = 'FX'

	SELECT @MemOptTables = count(1) from sys.tables where is_memory_optimized = 1;



	/* Display the Information */
	SELECT DB_NAME() as DbName, 
		case when @MemOptFileGroup IS NULL then 'Disabled' else 'Enabled' end as MemoryOptimised,
		case @dbMemElevateSnapshot when 1 then 'true' else 'false' end as ElevateSnapshot,
		@MemOptFileGroup as FileGroup, 
		@MemOptFileName as FileName,
		@MemOptFilePath as FilePath,
		@MemOptStatus as DataFileStatus,
		@MemOptTables as MemOptTables, 
		@pool as ResourceGroupPool,
		@poolMinMemory as MinMemoryPercent,
		@poolMaxMemory as MaxMemoryPercent

END

GO
/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Garbage Collector
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

-- Ensure that we are running SQL Server 2016
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetGarbageCollector' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetGarbageCollector as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Garbage Collector
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetGarbageCollector
-- Params --
-- end of --
as 
begin
	set nocount on;

	SELECT 
		(SELECT COUNT(*)
			FROM sys.dm_db_xtp_transactions tr
			WHERE tr.transaction_id > 0
				AND tr.state = 0 /*Active*/) as ActiveTransactions,
		(SELECT COUNT(*)
			FROM sys.dm_db_xtp_transactions tr
			WHERE tr.transaction_id > 0
				AND tr.state = 1 /*Succesfull*/) as SuccesfullTransactions,
		COUNT(*) as Queues,
		Cast(AVG(total_dequeues * 100. / case total_enqueues when 0 then 1 else total_enqueues end ) as Decimal(6,2)) as [De/En Queues],
		SUM(current_queue_depth) as TotalQueueDepth,
		MAX(current_queue_depth) as MaxDepth,
		AVG(current_queue_depth) as AvgDepth,
		MAX(maximum_queue_depth) as MaxQueueDepth
			FROM sys.dm_xtp_gc_queue_stats

	--SELECT *
	--	FROM sys.dm_xtp_gc_queue_stats

	--SELECT *
	--	FROM sys.dm_xtp_gc_stats

	--SELECT *
	--	FROM sys.dm_db_xtp_gc_cycle_stats

END

GO
/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Hash Indexes of the Memory Optimized Tables
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetHashIndexes' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetHashIndexes as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Hash Indexes of the Memory Optimized Tables
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetHashIndexes(
-- Params --
	@minEmptyBucketPercent Decimal(9,2) = NULL,		-- Filters the Indexes by the minimum percentage of the empty buckets
	@maxEmptyBucketPercent Decimal(9,2) = NULL,		-- Filters the Indexes by the maximum percentage of the empty buckets
	@minBuckets BIGINT = 0,							-- Allows to filter the indexes based on the minimum total number of buckets
	@minAvgChainLength bigint = 0,					-- Allows to filter the indexes with the number of Average Chain length equals or superior the parameter value
	@minMaxChainLrngth bigint = 0,					-- Allows to filter the indexes with the number of Maximum Chain length equals or superior the parameter value
	@schemaName nvarchar(256) = NULL,				-- Allows to show data filtered down to the specified schema		
	@tableName nvarchar(256) = NULL					-- Allows to show data filtered down to the specified table name pattern
-- end of --
) as 
begin
	set nocount on;
	
	SELECT  
		quotename(object_schema_name(t.object_id)) + '.' + quotename(object_name(t.object_id)) as TableName,   
		i.name as IndexName,   
		part.rows as TotalRows, 
		h.total_bucket_count as TotalBuckets,  
		h.empty_bucket_count as EmptyBuckets, 
		CAST(( (h.empty_bucket_count * 1.) / h.total_bucket_count) * 100 as Decimal(9,3) ) as EmptyBucketPercent,  
		h.avg_chain_length as AvgChainLength,   
		h.max_chain_length as MaxChainLength
		FROM sys.dm_db_xtp_hash_index_stats as h   
			INNER JOIN sys.indexes as i  
				ON h.object_id = i.object_id  
			   AND h.index_id = i.index_id  
			INNER JOIN sys.memory_optimized_tables_internal_attributes ia 
				ON h.xtp_object_id = ia.xtp_object_id 
			INNER JOIN sys.tables t 
				ON h.object_id = t.object_id
			INNER JOIN sys.partitions part
				ON part.object_id = i.object_id and part.index_id = i.index_id
			--OUTER APPLY sys.dm_db_stats_properties (i.object_id,i.index_id) st
		WHERE ia.type = 1 /* Index */
			AND h.avg_chain_length >= @minAvgChainLength
			AND h.max_chain_length >= @minMaxChainLrngth
			AND ((h.empty_bucket_count * 1.) / h.total_bucket_count) * 100 >= ISNULL( @minEmptyBucketPercent, 0 )
			AND ((h.empty_bucket_count * 1.) / h.total_bucket_count) * 100 <= ISNULL( @maxEmptyBucketPercent, 100 )
			AND total_bucket_count >= ISNULL(@minBuckets,total_bucket_count)
			AND (@tableName is null or object_name(t.object_id) like '%' + @tableName + '%')
			AND (@schemaName is null or schema_name(t.schema_id) = @schemaName)
		ORDER BY tableName, indexName;  
 

END

GO
/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Loaded Memory Optimized Modules
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetLoadedModules' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetLoadedModules as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Loaded Memory Optimized Modules
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetLoadedModules(
-- Params --
	@objectName nvarchar(128) = NULL,							-- Allows to filter by the name of the object
	@objectType varchar(20) = NULL								-- Allows to filter the type of the Memory-Optimised object
-- end of --
) as 
begin
	set nocount on;

	SELECT 
		obj.object_id as ObjectId,
		quotename(object_schema_name(obj.object_id)) + '.' + quotename(object_name(obj.object_id)) as ObjectName,
		case obj.type_desc 
			when 'USER_TABLE' then 'Table' 
			when 'TABLE_TYPE' then 'Table Type' 
			when 'SQL_TRIGGER' then 'Trigger' 
			when 'SQL_STORED_PROCEDURE' then 'Stored Proc'
			when 'SQL_INLINE_TABLE_VALUED_FUNCTION' then 'Inline Table Valued Function'
			when 'SQL_SCALAR_FUNCTION' then 'Scalar Function'
			when 'SQL_TABLE_VALUED_FUNCTION' then 'Table Valued Function'
		end as ObjectType,
		md.name as FilePath,	
		md.description, 
		--md.file_version,
		--md.product_version,
		--substring(md.name, 0, len(md.name) - charindex('\',reverse(md.name)) + 1 ) as X,	
		--substring(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ), 
		--		  len(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 )) - charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))) + 2, 10 ) as DatabaseId
		DB_ID() as DatabaseId
		--*
		FROM sys.dm_os_loaded_modules md  
			LEFT JOIN sys.objects obj
				ON cast( substring(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ), 
							len(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 )) - charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))) + 2, 10 ) as bigint) = obj.object_id
		WHERE description = 'XTP Native DLL'  
			--AND substring(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ), 
			--	  len(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 )) - charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))) + 2, 10 ) = cast(DB_ID() as varchar(10))	
			AND quotename(object_name(obj.object_id)) like '%' + isnull(@objectName,'') + '%'
			AND(case obj.type_desc 
					when 'USER_TABLE' then 'Table' 
					when 'TABLE_TYPE' then 'Table Type' 
					when 'SQL_TRIGGER' then 'Trigger' 
					when 'SQL_STORED_PROCEDURE' then 'Stored Proc'
					when 'SQL_INLINE_TABLE_VALUED_FUNCTION' then 'Inline Table Valued Function'
					when 'SQL_SCALAR_FUNCTION' then 'Scalar Function'
					when 'SQL_TABLE_VALUED_FUNCTION' then 'Table Valued Function'
				end = @objectType OR @objectType IS NULL )
		ORDER BY quotename(object_schema_name(obj.object_id)) + '.' + quotename(object_name(obj.object_id)) 
END

GO

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
/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	SQL Server Instance Information - Provides with the list of the known SQL Server versions that have bugfixes or improvements over your current version + lists currently enabled trace flags on the instance & session
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
		- Custom non-standard (non-CU & non-SP) versions are not targeted yet
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetSQLInfo' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetSQLInfo as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	SQL Server Instance Information - Provides with the list of the known SQL Server versions that have bugfixes or improvements over your current version + lists currently enabled trace flags on the instance & session
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetSQLInfo(
-- Params --
	@showUnrecognizedTraceFlags bit = 1,		-- Enables showing active trace flags, even if they are not columnstore indexes related
	@identifyCurrentVersion bit = 1,			-- Enables identification of the currently used SQL Server Instance version
	@showNewerVersions bit = 0					-- Enables showing the SQL Server versions that are posterior the current version
-- end of --
) as 
begin
	set nocount on;

	--------------------------------------------------------------------------------------------------------------------
	declare @SQLServerVersion nvarchar(128) = cast(SERVERPROPERTY('ProductVersion') as NVARCHAR(128)), 
			@SQLServerEdition nvarchar(128) = cast(SERVERPROPERTY('Edition') as NVARCHAR(128)),
			@SQLServerBuild smallint = NULL;
	declare @errorMessage nvarchar(512);



	--------------------------------------------------------------------------------------------------------------------
	set @SQLServerBuild = substring(@SQLServerVersion,CHARINDEX('.',@SQLServerVersion,5)+1,CHARINDEX('.',@SQLServerVersion,8)-CHARINDEX('.',@SQLServerVersion,5)-1);

	if OBJECT_ID('tempdb..#SQLMemOptImprovements', 'U') IS NOT NULL
		drop table #SQLMemOptImprovements;
	if OBJECT_ID('tempdb..#SQLBranches', 'U') IS NOT NULL
		drop table #SQLBranches;
	if OBJECT_ID('tempdb..#SQLVersions', 'U') IS NOT NULL
		drop table #SQLVersions;

	-- Returns tables suggested for using Columnstore Indexes for the DataWarehouse environments
	create table #SQLMemOptImprovements(
		BuildVersion smallint not null,
		SQLBranch char(3) not null,
		Description nvarchar(500) not null,
		URL nvarchar(1000)
	);

	create table #SQLBranches(
		SQLBranch char(3) not null Primary Key,
		MinVersion smallint not null );

	create table #SQLVersions(
		SQLBranch char(3) not null,
		SQLVersion smallint not null Primary Key,
		ReleaseDate datetime not null,
		SQLVersionDescription nvarchar(100) );


	insert into #SQLBranches (SQLBranch, MinVersion)
		values ('CTP', 200 ), ( 'RC0', 1100 ), ( 'RC1', 1200 ), ( 'RC2', 1300 ), ( 'RC3', 1400 ), ( 'RTM', 1601 );

	insert #SQLVersions( SQLBranch, SQLVersion, ReleaseDate, SQLVersionDescription )
		values 
		( 'CTP', 200, convert(datetime,'27-05-2015',105), 'CTP 2 for SQL Server 2016' ),
		( 'CTP', 300, convert(datetime,'24-06-2015',105), 'CTP 2.1 for SQL Server 2016' ),
		( 'CTP', 400, convert(datetime,'23-07-2015',105), 'CTP 2.2 for SQL Server 2016' ),
		( 'CTP', 500, convert(datetime,'28-08-2015',105), 'CTP 2.3 for SQL Server 2016' ),
		( 'CTP', 600, convert(datetime,'30-09-2015',105), 'CTP 2.4 for SQL Server 2016' ),
		( 'CTP', 700, convert(datetime,'28-10-2015',105), 'CTP 3 for SQL Server 2016' ),
		( 'CTP', 800, convert(datetime,'30-11-2015',105), 'CTP 3.1 for SQL Server 2016' ),
		( 'CTP', 900, convert(datetime,'16-12-2015',105), 'CTP 3.2 for SQL Server 2016' ),
		( 'CTP', 1000, convert(datetime,'03-02-2016',105), 'CTP 3.3 for SQL Server 2016' ),
		( 'RC0', 1100, convert(datetime,'07-03-2016',105), 'RC 0 for SQL Server 2016' ),
		( 'RC1', 1200, convert(datetime,'16-03-2016',105), 'RC 1 for SQL Server 2016' ),
		( 'RC2', 1300, convert(datetime,'01-04-2016',105), 'RC 2 for SQL Server 2016' ),
		( 'RC3', 1400, convert(datetime,'15-04-2016',105), 'RC 3 for SQL Server 2016' ),
		( 'RTM', 1601, convert(datetime,'01-06-2016',105), 'RTM for SQL Server 2016' ),
		( 'RTM', 2149, convert(datetime,'25-07-2016',105), 'CU 1 for SQL Server 2016' ),
		( 'RTM', 2164, convert(datetime,'22-09-2016',105), 'CU 2 for SQL Server 2016' ),
		( 'RTM', 2169, convert(datetime,'26-10-2016',105), 'On-Demand fix for CU 2 for SQL Server 2016' ),
		( 'RTM', 2170, convert(datetime,'01-11-2016',105), 'On-Demand fix for CU 2 for SQL Server 2016' );


	insert into #SQLMemOptImprovements (BuildVersion, SQLBranch, Description, URL )
		values 
		( 2149, 'RTM', 'Creating or updating statistics takes a long time on a large memory-optimized table in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3170996' ),
		( 2149, 'RTM', 'A deadlock condition occurs when you make updates on a memory-optimized temporal table and you run the SWITCH PARTITION statement on a history table in SQL Server 2016 ', 'https://support.microsoft.com/en-us/kb/3174712' ),
		( 2149, 'RTM', 'FIX: Secondary replica in "not healthy" state after you upgrade the primary database in SQL Server 2016 ', 'https://support.microsoft.com/en-us/kb/31718630' ),
		( 2149, 'RTM', 'FIX: Checkpoint files are missing from sys.dm_db_xtp_checkpoint_files on SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3173975' ),
		( 2149, 'RTM', 'SQL Server 2016 database log restore fails with the "Hk Recovery LSN is not NullLSN" error message', 'https://support.microsoft.com/en-us/kb/3171002' ),
		( 2149, 'RTM', 'FIX: Data loss when you alter column operation on a large memory-optimized table in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3174963' ),
		( 2149, 'RTM', 'FIX: Large disk checkpoint usage occurs for an In-Memory optimized filegroup during heavy non-In-Memory workloads', 'https://support.microsoft.com/en-us/kb/3147012' ),
		( 2149, 'RTM', 'FIX: Slow database recovery in SQL Server 2016 due to large log when you use In-Memory OLTP on a high-end computer', 'https://support.microsoft.com/en-us/kb/3171001' ),
		( 2149, 'RTM', 'Data Flush Tasks of a memory-optimized temporal table may consume 100-percent CPU usage in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3174713' ),
		( 2149, 'RTM', 'FIX: Error 5120 when you create or use a FILESTREAM-enabled database on a dynamic disk in an instance of SQL Server 2014 or 2016', 'https://support.microsoft.com/en-us/kb/3152377' ),
		( 2149, 'RTM', 'FIX: Fatal Error when you run a query against the sys.sysindexes view in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3173976' ),
		( 2149, 'RTM', 'Data loss or incorrect results occur when you use the sp_settriggerorder stored procedure in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3173004' ),
		( 2149, 'RTM', 'A data flush task may cause a deadlock condition when queries are executed on a memory-optimized table in SQL Server 2016', 'https://support.microsoft.com/en-us/kb/3173004' );

	
	if @identifyCurrentVersion = 1
	begin
		if OBJECT_ID('tempdb..#TempVersionResults') IS NOT NULL
			drop table #TempVersionResults;

		create table #TempVersionResults(
			MessageText nvarchar(512) NOT NULL,		
			SQLVersionDescription nvarchar(200) NOT NULL,
			SQLBranch char(3) not null,
			SQLVersion smallint NULL );

		-- Identify the number of days that has passed since the installed release
		declare @daysSinceLastRelease int = NULL;
		select @daysSinceLastRelease = datediff(dd,max(ReleaseDate),getdate())
			from #SQLVersions
			where SQLBranch = ServerProperty('ProductLevel')
				and SQLVersion = cast(@SQLServerBuild as int);

		-- Display the current information about this SQL Server 
		if( exists (select 1
						from #SQLVersions
						where SQLVersion = cast(@SQLServerBuild as int) ) )
			select 'You are Running:' as MessageText, SQLVersionDescription, SQLBranch, SQLVersion as BuildVersion, 'Your version is ' + cast(@daysSinceLastRelease as varchar(3)) + ' days old' as DaysSinceRelease
				from #SQLVersions
				where SQLVersion = cast(@SQLServerBuild as int);
		else
			select 'You are Running a Non RTM/SP/CU standard version:' as MessageText, '-' as SQLVersionDescription, 
				ServerProperty('ProductLevel') as SQLBranch, @SQLServerBuild as SQLVersion, 'Your version is ' + cast(@daysSinceLastRelease as varchar(3)) + ' days old' as DaysSinceRelease;

		-- Select information about all newer SQL Server versions that are known
		if @showNewerVersions = 1
		begin 
			insert into #TempVersionResults
				select 'Available Newer Versions:' as MessageText, '' as SQLVersionDescription, 
					'' as SQLBranch, NULL as BuildVersion
				UNION ALL
				select '' as MessageText, SQLVersionDescription as SQLVersionDescription, 
						SQLBranch as SQLVersionDescription, SQLVersion as BuildVersion
						from #SQLVersions
						where  @SQLServerBuild <  SQLVersion;

			select * 
				from #TempVersionResults;
		end 



		drop table #TempVersionResults;
	end

	select min(imps.BuildVersion) as BuildVersion, min(vers.SQLVersionDescription) as SQLVersionDescription, imps.Description, imps.URL
		from #SQLMemOptImprovements imps
			inner join #SQLBranches branch
				on imps.SQLBranch = branch.SQLBranch
			inner join #SQLVersions vers
				on imps.BuildVersion = vers.SQLVersion
		where BuildVersion > @SQLServerBuild 
			and branch.SQLBranch >= ServerProperty('ProductLevel')
			and branch.MinVersion < BuildVersion
		group by Description, URL, SQLVersionDescription
		having min(imps.BuildVersion) = (select min(imps2.BuildVersion)	from #SQLMemOptImprovements imps2 where imps.Description = imps2.Description and imps2.BuildVersion > @SQLServerBuild group by imps2.Description)
		order by BuildVersion;


	drop table if exists #SQLMemOptImprovements;
	drop table if exists #SQLBranches;
	drop table if exists #SQLVersions;
	drop table if exists #ActiveTraceFlags;
	drop table if exists #ColumnstoreTraceFlags;

	--------------------------------------------------------------------------------------------------------------------
	-- Trace Flags part
	create table #ActiveTraceFlags(	
		TraceFlag nvarchar(20) not null,
		Status bit not null,
		Global bit not null,
		Session bit not null );

	insert into #ActiveTraceFlags
		exec sp_executesql N'DBCC TRACESTATUS()';

	create table #ColumnstoreTraceFlags(
		TraceFlag int not null,
		Description nvarchar(500) not null,
		URL nvarchar(600),
		SupportedStatus bit not null 
	);

	insert into #ColumnstoreTraceFlags (TraceFlag, Description, URL, SupportedStatus )
		values 
		( 1851, 'Disables automerge for CFP', '', 0 ),
		( 9989, 'Enables Reading In-Memory Tables on the secondary replicas of AlwaysOn Availability Groups', 'https://connect.microsoft.com/SQLServer/feedback/details/795360/secondary-db-gets-suspect-when-i-add-in-memory-table-to-db-which-is-part-of-alwayson-availability-group', 0 ),
		( 9851, 'Disables automated merge process', '', 0 ),
		( 9837, 'Enables extra-tracing informations for the checkpoint files', '', 0 ),
		( 9926, 'Removes the limit on the number of transactions that can depend on a given transaction', '', 0 ),
		( 9912, 'Disables large checkpoints', 'https://beanalytics.wordpress.com/2016/05/20/logging-and-checkpoint-process-for-memory-optimized-tables-in-sql-2016/', 0 );


	select tf.TraceFlag, isnull(conf.Description,'Unrecognized') as Description, isnull(conf.URL,'-') as URL, SupportedStatus
		from #ActiveTraceFlags tf
			left join #ColumnstoreTraceFlags conf
				on conf.TraceFlag = tf.TraceFlag
		where @showUnrecognizedTraceFlags = 1 or (@showUnrecognizedTraceFlags = 0 AND Description is not null);

	drop table if exists #ColumnstoreTraceFlags;
	drop table if exists #ActiveTraceFlags;


END

GO
/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Memory Optimised Tables within the database
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetTables' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetTables as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Memory Optimised Tables within the database
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_GetTables(
-- Params --
	@durability varchar(20) = NULL,					-- Allows to filter Memory Optimised Tables by their durability status with possible values 'Schema' & 'Schema & Data'
	@pkType varchar(50) = NULL,						-- Allows to filter based on the type of the Primary Key with possible values NULL meaning all, 'None', 'Nonclustered' and 'Nonclustered Hash'
	@minRows bigint = 000,							-- Minimum number of rows for a table to be included
	@minReservedSizeInGB Decimal(16,3) = 0.00,		-- Minimum size in GB for a table to be included		
	@schemaName nvarchar(256) = NULL,				-- Allows to show data filtered down to the specified schema		
	@tableName nvarchar(256) = NULL					-- Allows to show data filtered down to the specified table name pattern
-- end of --
) as 
begin
	set nocount on;
	
	SELECT quotename(object_schema_name(tab.object_id)) + '.' + quotename(object_name(tab.object_id)) as 'TableName', 
		case tab.durability_desc WHEN 'SCHEMA_AND_DATA' then 'Schema & Data' else 'Schema' end as Durability,
		case ind.type_desc when 'NONCLUSTERED HASH' then 'Hash' when 'NONCLUSTERED' then 'NC' else NULL end as PrimaryKeyType,
		(SELECT COUNT(*) FROM sys.indexes ind
			WHERE tab.object_id = ind.object_id 
				AND ind.data_space_id = 0
				AND ind.type = 2) as 'NC Indexes',
		(SELECT COUNT(*) FROM sys.indexes ind
				WHERE tab.object_id = ind.object_id 
					AND ind.data_space_id = 0
					AND ind.type = 7) as 'Hash Indexes',
		(SELECT COUNT(*) FROM sys.indexes ind
			WHERE tab.object_id = ind.object_id 
				AND ind.data_space_id = 0
				AND ind.type in (5,6) ) as 'Columnstore',
		ISNULL(MAX(part.rows),0) as 'Rows Count',
		max(cast((memStats.memory_allocated_for_table_kb + memStats.memory_allocated_for_indexes_kb) / 1024.  as decimal(9,2))) as ReservedInMB,
		max(cast(memStats.memory_allocated_for_table_kb / 1024.  as decimal(9,2))) as TableAllocatedInMB,
		max(cast(memStats.memory_allocated_for_indexes_kb / 1024.  as decimal(9,2))) as IndexesAllocatedInMB,
	
		max(cast(memStats.memory_used_by_table_kb / 1024.  as decimal(9,2))) as TableUsedInMB,
		max(cast(memStats.memory_used_by_indexes_kb / 1024.  as decimal(9,2))) as IndexesUsedInMB,

		case (SELECT COUNT(*) FROM sys.indexes ind
			WHERE tab.object_id = ind.object_id 
				AND ind.data_space_id = 0
				AND ind.type in (5,6) ) 
			when 0 then 'true' 
			else 'false'
		end	as MetaDataUpdatable
		FROM sys.tables tab
			INNER JOIN sys.partitions part with(READUNCOMMITTED)
				on tab.object_id = part.object_id 
			INNER JOIN sys.dm_db_xtp_memory_consumers memCons
				on tab.object_id = memCons.object_id
			INNER JOIN sys.dm_db_xtp_table_memory_stats memStats
				on tab.object_id = memStats.object_id
			LEFT JOIN sys.indexes ind
				on tab.object_id = ind.object_id AND ind.is_primary_key = 1
		WHERE tab.is_memory_optimized = 1
			AND tab.durability_desc = ISNULL(case @Durability WHEN 'Schema & Data' THEN 'SCHEMA_AND_DATA' WHEN 'Schema' THEN 'SCHEMA_ONLY' ELSE NULL end, tab.durability_desc)
			AND ISNULL(ind.type_desc,'None') =  coalesce(@pkType,ind.type_desc,'None')
			AND (@tableName is null or object_name(tab.object_id) like '%' + @tableName + '%')
			AND (@schemaName is null or object_schema_name(tab.schema_id) = @schemaName)
		GROUP BY tab.object_id, tab.name, tab.durability_desc, ind.type_desc
		HAVING ISNULL(MAX(part.rows),0) >= @minRows
			AND MAX((memStats.memory_allocated_for_table_kb + memStats.memory_allocated_for_indexes_kb) / 1024.) >= @minReservedSizeInGB
		ORDER BY max(cast((memStats.memory_allocated_for_table_kb + memStats.memory_allocated_for_indexes_kb) / 1024.  as decimal(9,2))) desc



END

GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Suggested Tables - Shows details for the suggessted Memory Optimised Tables within the database
	Version: 0.2.0, November 2016

	Copyright 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/columnstore/), (http://www.oh22.is/)

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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_SuggestedTables' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_SuggestedTables as select 1');
GO

/*
	Memory Optimised Scripts Library for SQL Server 2016: 
	Shows details for the Memory Optimised Tables within the database
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_SuggestedTables(
-- Params --
	@minRowsToConsider bigint = 000001,							-- Minimum number of rows for a table to be considered for the suggestion inclusion
	@minSizeToConsiderInGB Decimal(16,3) = 0.00,				-- Minimum size in GB for a table to be considered for the suggestion inclusion
	@schemaName nvarchar(256) = NULL,							-- Allows to show data filtered down to the specified schema
	@tableName nvarchar(256) = NULL,							-- Allows to show data filtered down to the specified table name pattern
	@showReadyTablesOnly bit = 0,								-- Shows only those Rowstore tables that can already be converted to Memory-Optimised tables without any additional work
	@showUnsupportedColumnsDetails bit = 0						-- Shows a list of all Unsupported from the listed tables
-- end of --
) as 
begin
	set nocount on;

	-- Returns tables suggested for using Memory-Optimised
	DROP TABLE IF EXISTS #TablesToInMemory;

	create table #TablesToInMemory(
		[ObjectId] int NOT NULL PRIMARY KEY,
		[TableName] nvarchar(1000) NOT NULL,
		[ShortTableName] nvarchar(256) NOT NULL,
		[Compression] nvarchar(20) NOT NULL,
		[Row Count] bigint NOT NULL,
		[Size in GB] decimal(16,3) NOT NULL,
		[Cols Count] smallint NOT NULL,
		[String Cols] smallint NOT NULL,
		[Sum Length] int NOT NULL,
		[Unsupported] smallint NOT NULL,
		[LOBs] smallint NOT NULL,
		[Computed] smallint NOT NULL,
		[GUIDs] smallint NOT NULL,
		[Clustered Index] tinyint NOT NULL,
		[Nonclustered Indexes] smallint NOT NULL,
		[Columnstore] varchar(20) NULL,
		[XML Indexes] smallint NOT NULL,
		[Spatial Indexes] smallint NOT NULL,
		[Primary Key] tinyint NOT NULL,
		[Foreign Keys] smallint NOT NULL,
		[Constraints] smallint NOT NULL,
		[Triggers] smallint NOT NULL,
		[CDC] tinyint NOT NULL,
		[CT] tinyint NOT NULL,
		[Replication] tinyint NOT NULL,
		[FileStream] tinyint NOT NULL,
		[FileTable] tinyint NOT NULL
	);

	insert into #TablesToInMemory
	select t.object_id as [ObjectId]
		--, case ind.data_space_id when 0 then 'In-Memory' else 'Disk-Based' end 
		, quotename(object_schema_name(t.object_id)) + '.' + quotename(object_name(t.object_id)) as 'TableName'
		, replace(object_name(t.object_id),' ', '') as 'ShortTableName'
		, max(p.data_compression_desc) as 'Compression'
		, isnull(max(p.rows),0) as 'Row Count'
		, cast( sum(a.total_pages) * 8.0 / 1024. / 1024 as decimal(16,3)) as 'size in GB'
		, (select count(*) from sys.columns as col
			where t.object_id = col.object_id ) as 'Cols Count'
		, (select count(*) 
				from sys.columns as col
					inner join sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id and 
					 UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','SYSNAME') 
		   ) as 'String Cols'
		, (select sum(case col.max_length when -1 then 8000 else col.max_length end) 
				from sys.columns as col
					inner join sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id 
		  ) as 'Sum Length'
		, (select count(*) 
				from sys.columns as col
					inner join sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id AND 
					 (
						 (UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') OR
						  (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','BINARY','VARBINARY') and (col.max_length = 8000 or col.max_length = -1)) 
						 )
						 OR ( col.is_computed = 1 )
					 )
		   ) as 'Unsupported'
		, (select count(*) 
				from sys.columns as col
					inner join sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id and 
					 (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','VARBINARY','BINARY') and (col.max_length = 8000 or col.max_length = -1)) 
		   ) as 'LOBs'
		, (select count(*) 
				from sys.columns as col
				where t.object_id = col.object_id AND is_computed = 1 ) as 'Computed'
		, (select count(*)
			FROM sys.columns col
			INNER JOIN sys.types as tp
				ON col.user_type_id = tp.user_type_id
			WHERE t.object_id = col.object_id
				AND UPPER(tp.name) = 'UNIQUEIDENTIFIER') as 'Guid'
		, (select count(*)
				from sys.indexes ind
				where type = 1 AND ind.object_id = t.object_id ) as 'Clustered Index'
		, (select count(*)
				from sys.indexes ind
				where type = 2 AND ind.object_id = t.object_id ) as 'Nonclustered Indexes'
		, (select max(case ind.type when 5 then 'CCI' when 6 then 'NCCI' end)
				from sys.indexes ind
				where type in (5,6) AND ind.object_id = t.object_id ) as 'Columnstore'
		, (select count(*)
				from sys.indexes ind
				where type = 3 AND ind.object_id = t.object_id ) as 'XML Indexes'
		, (select count(*)
				from sys.indexes ind
				where type = 4 AND ind.object_id = t.object_id ) as 'Spatial Indexes'
		, (select count(*)
				from sys.objects
				where UPPER(type) = 'PK' AND parent_object_id = t.object_id ) as 'Primary Key'
		, (select count(*)
				from sys.objects
				where UPPER(type) = 'F' AND parent_object_id = t.object_id ) as 'Foreign Keys'
		, (select count(*)
				from sys.objects
				where UPPER(type) in ('UQ','C') AND parent_object_id = t.object_id ) as 'Constraints'
		, (select count(*)
				from sys.objects
				where UPPER(type) in ('TA','TR') AND parent_object_id = t.object_id ) as 'Triggers'
		, t.is_tracked_by_cdc as 'CDC'
		, (select count(*) 
				from sys.change_tracking_tables ctt with(READUNCOMMITTED)
				where ctt.object_id = t.object_id and ctt.is_track_columns_updated_on = 1 
					  and DB_ID() in (select database_id from sys.change_tracking_databases ctdb)) as 'CT'
		, t.is_replicated as 'Replication'
		, coalesce(t.filestream_data_space_id,0,1) as 'FileStream'
		, t.is_filetable as 'FileTable'
		from sys.tables t
			inner join sys.partitions as p 
				ON t.object_id = p.object_id
			inner join sys.allocation_units as a 
				ON p.partition_id = a.container_id
			inner join sys.indexes ind
				on ind.object_id = p.object_id and ind.index_id = p.index_id
			left join sys.dm_db_xtp_table_memory_stats xtpMem
				on xtpMem.object_id = t.object_id
		where --p.data_compression in (0,1,2) -- None, Row, Page
			 --and 
				t.is_memory_optimized = 0 -- Do not include In-Memory Tables
			 and (@tableName is null or object_name (t.object_id) like '%' + @tableName + '%')
			 and (@schemaName is null or object_schema_name( t.object_id ) = @schemaName)
		 
			 and (( @showReadyTablesOnly = 1 
					and  		
					(select count(*) 
								from sys.columns as col
									inner join sys.types as tp
										on col.user_type_id = tp.user_type_id
								where t.object_id = col.object_id AND 
									 (
										 (UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') OR
										  (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','BINARY','VARBINARY') and (col.max_length = 8000 or col.max_length = -1)) 
										 )
										 OR ( col.is_computed = 1 )
				 						) ) = 0 
					and (select count(*)
							from sys.objects so
							where UPPER(so.type) in ('PK','F','UQ','TA','TR') and parent_object_id = t.object_id ) = 0
					and (select count(*)
							from sys.indexes ind
							where t.object_id = ind.object_id
								and ind.type in (3,4) ) = 0
					and (select count(*) 
							from sys.change_tracking_tables ctt with(READUNCOMMITTED)
							where ctt.object_id = t.object_id and ctt.is_track_columns_updated_on = 1 
									and DB_ID() in (select database_id from sys.change_tracking_databases ctdb)) = 0
					and t.is_tracked_by_cdc = 0
					and t.is_memory_optimized = 0
					and t.is_replicated = 0
					and coalesce(t.filestream_data_space_id,0,1) = 0
					and t.is_filetable = 0
				  )
				 or @showReadyTablesOnly = 0)
		group by t.object_id, ind.data_space_id, t.is_tracked_by_cdc, t.is_memory_optimized, t.is_filetable, t.is_replicated, t.filestream_data_space_id
		having 
				(sum(p.rows) >= @minRowsToConsider or (sum(p.rows) = 0 and is_memory_optimized = 1) )
				and
				((select sum(col.max_length) 
					from sys.columns as col
						inner join sys.types as tp
							on col.system_type_id = tp.system_type_id
					where t.object_id = col.object_id 
				  ) < 8000 )
				and 
				(sum(a.total_pages) + isnull(sum(memory_allocated_for_table_kb),0) / 1024. / 1024 * 8.0 / 1024. / 1024 >= @minSizeToConsiderInGB)
	union all
	select t.object_id as [ObjectId]
		, quotename(object_schema_name(t.object_id, db_id('tempdb'))) + '.' + quotename(object_name(t.object_id, db_id('tempdb'))) as 'TableName'
		, replace(object_name(t.object_id, db_id('tempdb')),' ', '') as 'ShortTableName'
		, max(p.data_compression_desc) as 'Compression'
		, max(p.rows) as 'Row Count'
		, cast( sum(a.total_pages) * 8.0 / 1024. / 1024 as decimal(16,3)) as 'size in GB'
		, (select count(*) from tempdb.sys.columns as col
			where t.object_id = col.object_id ) as 'Cols Count'
		, (select count(*) 
				from tempdb.sys.columns as col
					inner join tempdb.sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id and 
					 UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','SYSNAME') 
		   ) as 'String Cols'
		, (select sum(col.max_length) 
				from tempdb.sys.columns as col
					inner join tempdb.sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id 
		  ) as 'Sum Length'
		, (select count(*) 
				from tempdb.sys.columns as col
					inner join tempdb.sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id AND 
					 (
						 (UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') OR
						  (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','BINARY','VARBINARY') and (col.max_length = 8000 or col.max_length = -1)) 
						 )
						 OR ( col.is_computed = 1 )
					 )
		   ) as 'Unsupported'
		, (select count(*) 
				from tempdb.sys.columns as col
					inner join tempdb.sys.types as tp
						on col.user_type_id = tp.user_type_id
				where t.object_id = col.object_id and 
					 (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR') and (col.max_length = 8000 or col.max_length = -1)) 
		   ) as 'LOBs'
		, (select count(*) 
				from tempdb.sys.columns as col
				where is_computed = 1 ) as 'Computed'
		, (select count(*)
			FROM sys.columns col
			INNER JOIN sys.types as tp
				ON col.user_type_id = tp.user_type_id
			WHERE t.object_id = col.object_id
				AND UPPER(tp.name) = 'UNIQUEIDENTIFIER') as 'Guid'
		, (select count(*)
				from tempdb.sys.indexes ind
				where type = 1 AND ind.object_id = t.object_id ) as 'Clustered Index'
		, (select count(*)
				from tempdb.sys.indexes ind
				where type = 2 AND ind.object_id = t.object_id ) as 'Nonclustered Indexes'
		, (select max(case ind.type when 5 then 'CCI' when 6 then 'NCCI' end)
				from sys.indexes ind
				where type in (5,6) AND ind.object_id = t.object_id ) as 'Columnstore'
		, (select count(*)
				from tempdb.sys.indexes ind
				where type = 3 AND ind.object_id = t.object_id ) as 'XML Indexes'
		, (select count(*)
				from tempdb.sys.indexes ind
				where type = 4 AND ind.object_id = t.object_id ) as 'Spatial Indexes'
		, (select count(*)
				from tempdb.sys.objects
				where UPPER(type) = 'PK' AND parent_object_id = t.object_id ) as 'Primary Key'
		, (select count(*)
				from tempdb.sys.objects
				where UPPER(type) = 'F' AND parent_object_id = t.object_id ) as 'Foreign Keys'
		, (select count(*)
				from tempdb.sys.objects
				where UPPER(type) in ('UQ','C') AND parent_object_id = t.object_id ) as 'Constraints'
		, (select count(*)
				from tempdb.sys.objects
				where UPPER(type) in ('TA','TR') AND parent_object_id = t.object_id ) as 'Triggers'
		, t.is_tracked_by_cdc as 'CDC'
		, (select count(*) 
				from tempdb.sys.change_tracking_tables ctt with(READUNCOMMITTED)
				where ctt.object_id = t.object_id and ctt.is_track_columns_updated_on = 1 
					  and DB_ID() in (select database_id from sys.change_tracking_databases ctdb)) as 'CT'
		, t.is_replicated as 'Replication'
		, coalesce(t.filestream_data_space_id,0,1) as 'FileStream'
		, t.is_filetable as 'FileTable'
		from tempdb.sys.tables t
			inner join tempdb.sys.partitions as p 
				ON t.object_id = p.object_id
			inner join tempdb.sys.allocation_units as a 
				ON p.partition_id = a.container_id
		where p.data_compression in (0,1,2) -- None, Row, Page
			 and (@tableName is null or object_name( t.object_id, db_id('tempdb') ) like '%' + @tableName + '%')
			 and (@schemaName is null or object_schema_name( t.object_id, db_id('tempdb') ) = @schemaName)
			 and t.is_memory_optimized = 0
			 and (( @showReadyTablesOnly = 1 
					and  
					(select count(*) 
								from sys.columns as col
									inner join sys.types as tp
										on col.user_type_id = tp.user_type_id
								where t.object_id = col.object_id AND 
									 (
										 (UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') 
										 )
										 OR ( col.is_computed = 1 )
				 						) ) = 0 
					and (select count(*)
							from tempdb.sys.objects so
							where UPPER(so.type) in ('PK','F','UQ','TA','TR') and parent_object_id = t.object_id ) = 0
					and (select count(*)
							from tempdb.sys.indexes ind
							where t.object_id = ind.object_id
								and ind.type in (3,4) ) = 0
					and (select count(*) 
							from tempdb.sys.change_tracking_tables ctt with(READUNCOMMITTED)
							where ctt.object_id = t.object_id and ctt.is_track_columns_updated_on = 1 
									and DB_ID() in (select database_id from sys.change_tracking_databases ctdb)) = 0
					and t.is_tracked_by_cdc = 0
					and t.is_memory_optimized = 0
					and t.is_replicated = 0
					and coalesce(t.filestream_data_space_id,0,1) = 0
					and t.is_filetable = 0
				  )
				 or @showReadyTablesOnly = 0)
		group by t.object_id, t.is_tracked_by_cdc, t.is_memory_optimized, t.is_filetable, t.is_replicated, t.filestream_data_space_id
		having sum(p.rows) >= @minRowsToConsider 
				and
				(((select sum(col.max_length) 
					from tempdb.sys.columns as col
						inner join tempdb.sys.types as tp
							on col.system_type_id = tp.system_type_id
					where t.object_id = col.object_id 
				  ) < 8000 ) )
				and 
				(sum(a.total_pages) * 8.0 / 1024. / 1024 >= @minSizeToConsiderInGB)

	delete from #TablesToInMemory
		where [Size in GB] < @minSizeToConsiderInGB
			or [Row Count] < @minRowsToConsider;

	-- Show the found results
	select [TableName], [Compression], [Row Count], [Size in GB], [Cols Count], [Sum Length], [Unsupported], [LOBs], [Computed], [GUIDs]
		, [Clustered Index] as CI, [Nonclustered Indexes] as NCI
		, isnull([Columnstore],'none') as [Columnstore]
		, [XML Indexes], [Spatial Indexes], [Primary Key], [Foreign Keys], [Constraints]
		, [Triggers], [CDC], [CT], [Replication], [FileStream], [FileTable]
		from #TablesToInMemory
		order by [Size in GB] desc;

	if( @showUnsupportedColumnsDetails = 1 ) 
	begin
		select quotename(object_schema_name(t.object_id)) + '.' + quotename(object_name (t.object_id)) as 'TableName',
			col.name as 'Unsupported Column Name',
			tp.name as 'Data Type',
			col.collation_name as 'Collation',
			col.max_length as 'Max Length',
			col.precision as 'Precision',
			col.is_computed as 'Computed'
			from sys.tables t
				inner join sys.columns as col
					on t.object_id = col.object_id 
				inner join sys.types as tp
					on col.user_type_id = tp.user_type_id 
				where  ((UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') OR
						(UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR') and (col.max_length = 8000 or col.max_length = -1)) 
						) 
						OR col.is_computed = 1 
					  )
				 and t.object_id in (select ObjectId from #TablesToInMemory);
	end

	--if( @showTSQLCommandsBeta = 1 ) 
	--begin
		--select coms.TableName, coms.[TSQL Command], coms.[type] 
		--	from (
		--		select t.TableName, 
		--				'create ' + @columnstoreIndexTypeForTSQL + ' columnstore index ' + 
		--				case @columnstoreIndexTypeForTSQL when 'Clustered' then 'CCI' when 'Nonclustered' then 'NCCI' end 
		--				+ '_' + t.[ShortTableName] + 
		--				' on ' + t.TableName + case @columnstoreIndexTypeForTSQL when 'Nonclustered' then '()' else '' end + ';' as [TSQL Command]
		--			   , 'CCL' as type,
		--			   101 as [Sort Order]
		--			from #TablesToInMemory t
		--		union all
		--		select t.TableName, 'alter table ' + t.TableName + ' drop constraint ' + (quotename(so.name) collate SQL_Latin1_General_CP1_CI_AS) + ';' as [TSQL Command], [type], 
		--			   case UPPER(type) when 'PK' then 100 when 'F' then 1 when 'UQ' then 100 end as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.objects so
		--				on t.ObjectId = so.parent_object_id or t.ObjectId = so.object_id
		--			where UPPER(type) in ('PK','F','UQ')
		--		union all
		--		select t.TableName, 'drop trigger ' + (quotename(so.name) collate SQL_Latin1_General_CP1_CI_AS) + ';' as [TSQL Command], type,
		--			50 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.objects so
		--				on t.ObjectId = so.parent_object_id
		--			where UPPER(type) in ('TR')
		--		union all
		--		select t.TableName, 'drop assembly ' + (quotename(so.name) collate SQL_Latin1_General_CP1_CI_AS) + ' WITH NO DEPENDENTS ;' as [TSQL Command], type,
		--			50 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.objects so
		--				on t.ObjectId = so.parent_object_id
		--			where UPPER(type) in ('TA')	
		--		union all 
		--		select t.TableName, 'drop index ' + (quotename(ind.name) collate SQL_Latin1_General_CP1_CI_AS) + ' on ' + t.TableName + ';' as [TSQL Command], 'CL' as type,
		--			10 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.indexes ind
		--				on t.ObjectId = ind.object_id
		--			where type = 1 and not exists
		--				(select 1 from #TablesToInMemory t1
		--					inner join sys.objects so1
		--						on t1.ObjectId = so1.parent_object_id
		--					where UPPER(so1.type) in ('PK','F','UQ')
		--						and quotename(ind.name) <> quotename(so1.name))
		--		union all 
		--		select t.TableName, 'drop index ' + (quotename(ind.name) collate SQL_Latin1_General_CP1_CI_AS) + ' on ' + t.TableName + ';' as [TSQL Command], 'NC' as type,
		--			10 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.indexes ind
		--				on t.ObjectId = ind.object_id
		--			where type = 2 and not exists
		--				(select * from #TablesToInMemory t1
		--					inner join sys.objects so1
		--						on t1.ObjectId = so1.parent_object_id 
		--					where UPPER(so1.type) in ('PK','F','UQ')
		--						and quotename(ind.name) <> quotename(so1.name) and t.ObjectId = t1.ObjectId )
		--		union all 
		--		select t.TableName, 'drop index ' + (quotename(ind.name) collate SQL_Latin1_General_CP1_CI_AS) + ' on ' + t.TableName + ';' as [TSQL Command], 'XML' as type,
		--			10 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.indexes ind
		--				on t.ObjectId = ind.object_id
		--			where type = 3
		--		union all 
		--		select t.TableName, 'drop index ' + (quotename(ind.name) collate SQL_Latin1_General_CP1_CI_AS) + ' on ' + t.TableName + ';' as [TSQL Command], 'SPAT' as type,
		--			10 as [Sort Order]
		--			from #TablesToInMemory t
		--			inner join sys.indexes ind
		--				on t.ObjectId = ind.object_id
		--			where type = 4
		--	) coms
		--order by coms.type desc, coms.[Sort Order]; --coms.TableName 
	
	--end

	drop table #TablesToInMemory; 

END 

GO

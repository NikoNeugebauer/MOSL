/*
	Memory Optimised Library for SQL Server 2014: 
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

 --Ensure that we are running SQL Server 2014
if substring(@SQLServerVersion,1,CHARINDEX('.',@SQLServerVersion)-1) <> N'12'
begin
	set @errorMessage = (N'You are not running a SQL Server 2014. Your SQL Server version is ' + @SQLServerVersion);
	Throw 51000, @errorMessage, 1;
end

if SERVERPROPERTY('EngineEdition') <> 3 
begin
	set @errorMessage = (N'Your SQL Server 2014 Edition is not an Enterprise or a Developer Edition: Your are running a ' + @SQLServerEdition);
	Throw 51000, @errorMessage, 1;
end

--------------------------------------------------------------------------------------------------------------------
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_SuggestedTables' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_SuggestedTables as select 1');
GO

/*
	Memory Optimised Library for SQL Server 2014: 
	Shows details for the Memory Optimised Tables within the database
	Version: 0.2.0, November 2016
*/
alter procedure dbo.memopt_SuggestedTables(
-- Params --
	@minRowsToConsider bigint = 000000,							-- Minimum number of rows for a table to be considered for the suggestion inclusion
	@minSizeToConsiderInGB Decimal(16,3) = 0.00,				-- Minimum size in GB for a table to be considered for the suggestion inclusion
	@schemaName nvarchar(256) = NULL,							-- Allows to show data filtered down to the specified schema
	@tableName nvarchar(256) = NULL,							-- Allows to show data filtered down to the specified table name pattern
	@showReadyTablesOnly bit = 0,								-- Shows only those Rowstore tables that can already be converted to Memory-Optimised tables without any additional work
	@showUnsupportedColumnsDetails bit = 0						-- Shows a list of all Unsupported from the listed tables
-- end of --
) as 
begin
	set nocount on;


	declare 
		@isEncrypted tinyint = 0;

	-- Verify Snapshot Isolation Level or Read Commited Snapshot 
	select
		@isEncrypted = is_encrypted
		from sys.databases
		where database_id = DB_ID();

	-- Returns tables suggested for using Memory-Optimised
	if OBJECT_ID('tempdb..#TablesToInMemory') IS NOT NULL
		drop table #TablesToInMemory;

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
		[TDE] tinyint NOT NULL,
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
						 OR (col.collation_name is not null AND col.collation_name not like '%_bin2')
						 OR (COLLATIONPROPERTY(col.collation_name, 'CodePage') <> 1252)
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
		, @isEncrypted as 'TDE'
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
										 OR (col.collation_name is not null AND col.collation_name not like '%_bin2')
										 OR (COLLATIONPROPERTY(col.collation_name, 'CodePage') <> 1252)
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
						 OR (col.collation_name is not null AND col.collation_name not like '%_bin2')
						 OR (COLLATIONPROPERTY(col.collation_name, 'CodePage') <> 1252)
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
		, @isEncrypted as 'TDE'
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
										 (UPPER(tp.name) in ('IMAGE','TEXT','NTEXT','TIMESTAMP','HIERARCHYID','SQL_VARIANT','XML','GEOGRAPHY','GEOMETRY','DATETIMEOFFSET','UNIQUEIDENTIFIER') OR
										  (UPPER(tp.name) in ('VARCHAR','NVARCHAR','CHAR','NCHAR','BINARY','VARBINARY') and (col.max_length = 8000 or col.max_length = -1)) 
										 )
										 OR (col.collation_name is not null AND col.collation_name not like '%_bin2')
										 OR (COLLATIONPROPERTY(col.collation_name, 'CodePage') <> 1252)
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
		, [Triggers], [TDE], [CDC], [CT], [Replication], [FileStream], [FileTable]
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
						OR (col.collation_name is not null AND col.collation_name not like '%_bin2')
						OR (COLLATIONPROPERTY(col.collation_name, 'CodePage') <> 1252)
					  )
				 and t.object_id in (select ObjectId from #TablesToInMemory);
	end

	drop table #TablesToInMemory; 

END 

GO

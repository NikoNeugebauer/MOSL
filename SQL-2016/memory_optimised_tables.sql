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

-- Params --
declare @durability varchar(20) = NULL,					-- Allows to filter Memory Optimised Tables by their durability status with possible values 'Schema' & 'Schema & Data'
		@pkType varchar(50) = NULL,						-- Allows to filter based on the type of the Primary Key with possible values NULL meaning all, 'None', 'Nonclustered' and 'Nonclustered Hash'
		@minRows bigint = 000,							-- Minimum number of rows for a table to be included
		@minReservedSizeInGB Decimal(16,3) = 0.00,		-- Minimum size in GB for a table to be included		
		@schemaName nvarchar(256) = NULL,				-- Allows to show data filtered down to the specified schema		
		@tableName nvarchar(256) = NULL					-- Allows to show data filtered down to the specified table name pattern
-- end of --

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

set nocount on;

/*
Is Table Modifyable (2016 vs 2016 vs InMemory Columnstore)
*/

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



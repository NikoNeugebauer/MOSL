/*
	Memory Optimised Library for SQL Server 2016: 
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
	Memory Optimised Library for SQL Server 2016: 
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

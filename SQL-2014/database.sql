/*
	Memory Optimised Library for SQL Server 2014: 
	Shows details for the Database Configuration
	Version: 0.1.0 Beta, October 2016

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

DECLARE @pool SYSNAME,
		@poolMinMemory Decimal(9,2) = NULL,
		@poolMaxMemory Decimal(9,2) = NULL,
		@MemOptFileGroup NVARCHAR(512) = NULL,
		@MemOptFileName NVARCHAR(512) = NULL,
		@MemOptFilePath NVARCHAR(2048) = NULL,
		@MemOptStatus VARCHAR(20) = NULL,
		@MemOptTables INT = 0;

-- Check if the current database is bound to a resource pool
SELECT @pool = p.name,
	   @poolMinMemory = p.min_memory_percent,
	   @poolMaxMemory = p.max_memory_percent
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
	@MemOptFileGroup as FileGroup, 
	@MemOptFileName as FileName,
	@MemOptFilePath as FilePath,
	@MemOptStatus as DataFileStatus,
	@MemOptTables as MemOptTables, 
	@pool as ResourceGroupPool,
	@poolMinMemory as MinMemoryPercent,
	@poolMaxMemory as MaxMemoryPercent

--sys.dm_db_xtp_checkpoint_stats: Shows Checkpoint statistics of the current database.
--sys.dm_db_xtp_checkpoint_files: This DMV shows information about checkpoint files, like the type of file (DATA or DELTA files) its size and relative path.
--sys.dm_db_xtp_gc_cycle_stats: Shows garbage collection cycles for the current database.

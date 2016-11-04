/*
	Memory Optimised Library for SQL Server 2014: 
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

-- Ensure that we are running SQL Server 2014
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetGarbageCollector' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetGarbageCollector as select 1');
GO

/*
	Memory Optimised Library for SQL Server 2014: 
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
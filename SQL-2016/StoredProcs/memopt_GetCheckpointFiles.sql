/*
	Memory Optimised Library for SQL Server 2016: 
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
	Memory Optimised Library for SQL Server 2016: 
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





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

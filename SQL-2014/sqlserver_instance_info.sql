/*
	Memory Optimised Library for SQL Server 2014: 
	SQL Server Instance Information - Provides with the list of the known SQL Server versions that have bugfixes or improvements over your current version + lists currently enabled trace flags on the instance & session
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
		- Custom non-standard (non-CU & non-SP) versions are not targeted yet
		- Duplicate Fixes & Improvements (CU12 for SP1 & CU2 for SP2, for example) are not eliminated from the list yet
*/


-- Params --
declare @showUnrecognizedTraceFlags bit = 1,		-- Enables showing active trace flags, even if they are not columnstore indexes related
		@identifyCurrentVersion bit = 1,			-- Enables identification of the currently used SQL Server Instance version
		@showNewerVersions bit = 1;					-- Enables showing the SQL Server versions that are posterior the current version
-- end of --

--------------------------------------------------------------------------------------------------------------------
declare @SQLServerVersion nvarchar(128) = cast(SERVERPROPERTY('ProductVersion') as NVARCHAR(128)), 
		@SQLServerEdition nvarchar(128) = cast(SERVERPROPERTY('Edition') as NVARCHAR(128)),
		@SQLServerBuild smallint = NULL;
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
	values ('RTM', 2000 ), ('SP1', 4100), ('SP2', 5000) ;

insert #SQLVersions( SQLBranch, SQLVersion, ReleaseDate, SQLVersionDescription )
	values 
	( 'RTM', 2000, convert(datetime,'01-04-2014',105), 'SQL Server 2014 RTM' ),
	( 'RTM', 2342, convert(datetime,'21-04-2014',105), 'CU 1 for SQL Server 2014 RTM' ),
	( 'RTM', 2370, convert(datetime,'27-06-2014',105), 'CU 2 for SQL Server 2014 RTM' ),
	( 'RTM', 2402, convert(datetime,'18-08-2014',105), 'CU 3 for SQL Server 2014 RTM' ),
	( 'RTM', 2430, convert(datetime,'21-10-2014',105), 'CU 4 for SQL Server 2014 RTM' ),
	( 'RTM', 2456, convert(datetime,'18-12-2014',105), 'CU 5 for SQL Server 2014 RTM' ),
	( 'RTM', 2480, convert(datetime,'16-02-2015',105), 'CU 6 for SQL Server 2014 RTM' ),
	( 'RTM', 2495, convert(datetime,'23-04-2015',105), 'CU 7 for SQL Server 2014 RTM' ),
	( 'RTM', 2546, convert(datetime,'22-06-2015',105), 'CU 8 for SQL Server 2014 RTM' ),
	( 'RTM', 2553, convert(datetime,'17-08-2015',105), 'CU 9 for SQL Server 2014 RTM' ),
	( 'RTM', 2556, convert(datetime,'20-10-2015',105), 'CU 10 for SQL Server 2014 RTM' ),
	( 'RTM', 2560, convert(datetime,'22-12-2015',105), 'CU 11 for SQL Server 2014 RTM' ),
	( 'RTM', 2564, convert(datetime,'22-02-2016',105), 'CU 12 for SQL Server 2014 RTM' ),
	( 'RTM', 2568, convert(datetime,'19-04-2016',105), 'CU 13 for SQL Server 2014 RTM' ),
	( 'RTM', 2569, convert(datetime,'20-06-2016',105), 'CU 14 for SQL Server 2014 RTM' ),
	( 'SP1', 4100, convert(datetime,'14-05-2015',105), 'SQL Server 2014 SP1' ),
	( 'SP1', 4416, convert(datetime,'22-06-2015',105), 'CU 1 for SQL Server 2014 SP1' ),
	( 'SP1', 4422, convert(datetime,'17-08-2015',105), 'CU 2 for SQL Server 2014 SP1' ),
	( 'SP1', 4427, convert(datetime,'21-10-2015',105), 'CU 3 for SQL Server 2014 SP1' ),
	( 'SP1', 4436, convert(datetime,'22-12-2015',105), 'CU 4 for SQL Server 2014 SP1' ),
	( 'SP1', 4439, convert(datetime,'22-02-2016',105), 'CU 5 for SQL Server 2014 SP1' ),
	( 'SP1', 4449, convert(datetime,'19-04-2016',105), 'CU 6 for SQL Server 2014 SP1' ),
	( 'SP1', 4457, convert(datetime,'31-05-2016',105), 'CU 6A for SQL Server 2014 SP1' ),
	( 'SP1', 4459, convert(datetime,'20-06-2016',105), 'CU 7 for SQL Server 2014 SP1' ),
	( 'SP1', 4468, convert(datetime,'15-08-2016',105), 'CU 8 for SQL Server 2014 SP1' ),
	( 'SP2', 5000, convert(datetime,'11-07-2016',105), 'SQL Server 2014 SP2' ),
	( 'SP2', 5511, convert(datetime,'25-08-2016',105), 'CU 1 for SQL Server 2014 SP2' );


insert into #SQLMemOptImprovements (BuildVersion, SQLBranch, Description, URL )
	values 
	( 2342, 'RTM', 'FIX: Errors when you join memory-optimized table to memory-optimized table type at RCSI in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2936896' ),
	( 2342, 'RTM', 'FIX: An access violation occurs when you try to use datepart (weekday) in a natively compiled stored procedure in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2938460' ),
	( 2342, 'RTM', 'FIX: Incorrect message type when you restart a SQL Server 2014 instance that has Hekaton databases', 'https://support.microsoft.com/en-us/kb/2938461' ),
	( 2342, 'RTM', 'FIX: Missing or wrong information about missing indexes is returned when you query in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2938462' ),
	( 2342, 'RTM', 'FIX: No missing index recommendation is displayed when the index is not the correct type for the query in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2938463' ),
	( 2342, 'RTM', 'FIX: Cannot use showplan_xml for the query/procedure when you create a natively compiled stored procedure with a query that contains a large expression in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2938464' ),
	( 2342, 'RTM', 'FIX: Worker time in the DMVs sys.dm_exec_procedure_stats and sys.dm_exec_query_stats for natively compiled stored procedures is reported incorrectly in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2940348' ),
	( 2370, 'RTM', 'FIX: Error in checking master database after you bind a memory-optimized database to a resource pool in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2968023' ),
	( 2370, 'RTM', 'FIX: Sys.indexes returns incorrect value for indexes in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2969741' ),
	( 2402, 'RTM', 'FIX: Cannot open the memory-optimized table template remotely in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2960924' ), 
	( 2402, 'RTM', 'FIX: "Non-yielding scheduler" error when you insert or update many rows in one transaction in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2968418' ),
	( 2402, 'RTM', 'FIX: Auto-statistics creation increases the compilation time for natively compiled stored procedure in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2984628' ),
	( 2402, 'RTM', 'FIX: LCK_M_SCH_M occurs when you access memory-optimized table variables outside natively compiled stored procedures', 'https://support.microsoft.com/en-us/kb/2984629' ),
	( 2430, 'RTM', 'FIX: Cannot recover the In-Memory OLTP database after you enable and then disable TDE on it in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/2974169' ),
	( 2456, 'RTM', 'FIX: RTDATA_LIST waits when you run natively stored procedures that encounter expected failures in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/3007050' ),
	( 2568, 'RTM', 'FIX: SQL Server 2014 crashes when you execute a query that contains a NONEXISTENT query hint on an In-Memory OLTP database', 'https://support.microsoft.com/en-us/kb/3138775' ),	
	( 4422, 'SP1', 'FIX: Increased wait time of HADR_SYNC_COMMIT wait types when you have memory-optimized tables defined in at least one availability group database', 'https://support.microsoft.com/en-us/kb/3081291' ),
	( 4427, 'SP1', 'FIX: Can’t backup in-memory OLTP database that is restored by using full and differential restore in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/3096617' ),
	( 4427, 'SP1', 'FIX: 100% CPU usage occurs when in-memory OLTP database is in recovery state in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/3099487' ),
	( 4427, 'SP1', 'FIX: Offline checkpoint thread shuts down without providing detailed exception information in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/3090141' ),
	( 4457, 'SP1', 'FIX: Large disk checkpoint usage occurs for an In-Memory optimized filegroup during heavy non-In-Memory workloads', 'https://support.microsoft.com/en-us/kb/3147012' ),	
	( 4459, 'SP1', 'FIX: SQL Server 2014 crashes when you execute a query that contains a NONEXISTENT query hint on an In-Memory OLTP database', 'https://support.microsoft.com/en-us/kb/3138775' ),	
	( 4468, 'SP1', 'FIX: Garbage collection in In-Memory OLTP may cause "non-yielding scheduler" in SQL Server 2014', 'https://support.microsoft.com/en-us/kb/3177132' );


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

select imps.BuildVersion, vers.SQLVersionDescription, imps.Description, imps.URL
	from #SQLMemOptImprovements imps
		inner join #SQLBranches branch
			on imps.SQLBranch = branch.SQLBranch
		inner join #SQLVersions vers
			on imps.BuildVersion = vers.SQLVersion
	where BuildVersion > @SQLServerBuild 
		and branch.SQLBranch = ServerProperty('ProductLevel')
		and branch.MinVersion < BuildVersion;

drop table #SQLMemOptImprovements;
drop table #SQLBranches;
drop table #SQLVersions;

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
	( 9837, 'Enables extra-tracing informations for the checkpoint files', '', 0 );

select tf.TraceFlag, isnull(conf.Description,'Unrecognized') as Description, isnull(conf.URL,'-') as URL, SupportedStatus
	from #ActiveTraceFlags tf
		left join #ColumnstoreTraceFlags conf
			on conf.TraceFlag = tf.TraceFlag
	where @showUnrecognizedTraceFlags = 1 or (@showUnrecognizedTraceFlags = 0 AND Description is not null);

drop table #ColumnstoreTraceFlags;
drop table #ActiveTraceFlags;


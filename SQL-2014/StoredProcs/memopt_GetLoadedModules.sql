/*
	Memory Optimised Library for SQL Server 2014: 
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
if NOT EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetLoadedModules' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.memopt_GetLoadedModules as select 1');
GO

/*
	Memory Optimised Library for SQL Server 2014: 
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
		--substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ),
		--charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))), 
		substring(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ), 
				  len(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 )) - charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))) + 2, 10 ) as DatabaseId
		--replace(substring(md.name, len(md.name) - charindex('_',reverse(md.name)) + 2, len(md.name) ), '.dll', '') as ObjectId,
		--object_name( replace(substring(md.name, len(md.name) - charindex('_',reverse(md.name)) + 2, len(md.name) ), '.dll', '') ) as ObjectName,
		--*
		FROM sys.dm_os_loaded_modules md  
			LEFT JOIN sys.objects obj
				ON replace(substring(md.name, len(md.name) - charindex('_',reverse(md.name)) + 2, len(md.name) ), '.dll', '')  = obj.object_id
		WHERE description = 'XTP Native DLL'  
			AND substring(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ), 
				  len(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 )) - charindex('_', reverse(substring(md.name, 0, len(md.name) - charindex('_',reverse(md.name)) + 1 ))) + 2, 10 ) = cast(DB_ID() as varchar(10))	
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
		ORDER BY quotename(object_schema_name(obj.object_id)) + '.' + quotename(object_name(obj.object_id));

END

GO


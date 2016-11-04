/*
	Memory Optimised Library for SQL Server 2014: 
	Cleanup - This script removes from the current database all MOSL Stored Procedures that were previously installed there
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

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetCheckpointFiles' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetCheckpointFiles;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetDatabaseInfo' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetDatabaseInfo;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetGarbageCollector' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetGarbageCollector;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetHashIndexes' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetHashIndexes;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetLoadedModules' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetLoadedModules;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetObjects' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetObjects;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetSQLInfo' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetSQLInfo;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_GetTables' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_GetTables;

if EXISTS (select * from sys.objects where type = 'p' and name = 'memopt_SuggestedTables' and schema_id = SCHEMA_ID('dbo') )
	drop procedure dbo.memopt_SuggestedTables;
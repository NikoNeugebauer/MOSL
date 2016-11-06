#	MOSL - Memory Optimized Scripts Library for SQL Server
#	Powershell Script to setup the Stored Procedures & Tests for the MOSL
#	Version: 1.4.0, October 2016
#
#	Copyright 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/), (http://www.oh22.is/)
#
#	Licensed under the Apache License, Version 2.0 (the "License");
#	you may not use this file except in compliance with the License.
#	You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific lan guage governing permissions and
#    limitations under the License.

$scriptRootPath = Split-Path -Parent $PSCommandPath

###############################################################################
# SQL Server 2014
Get-Content $scriptRootPath\SQL-2014\StoredProcs\memopt_GetCheckpointFiles.sql, $scriptRootPath\SQL-2014\StoredProcs\memopt_GetDatabaseInfo.sql, `
            $scriptRootPath\SQL-2014\StoredProcs\memopt_GetGarbageCollector.sql, $scriptRootPath\SQL-2014\StoredProcs\memopt_GetHashIndexes.sql, `
            $scriptRootPath\SQL-2014\StoredProcs\memopt_GetLoadedModules.sql, $scriptRootPath\SQL-2014\StoredProcs\memopt_GetObjects.sql, `
            $scriptRootPath\SQL-2014\StoredProcs\memopt_GetSQLInfo.sql, $scriptRootPath\SQL-2014\StoredProcs\memopt_GetTables.sql, `
            $scriptRootPath\SQL-2014\StoredProcs\memopt_SuggestedTables.sql | `
    Set-Content $scriptRootPath\SQL-2014\StoredProcs\memopt_install_all_stored_procs.sql

# Unit Tests for SQL Server 2014
#Get-Content $scriptRootPath\Tests\SQL-2014\*.sql | Set-Content $scriptRootPath\Tests\sql-2014-tests.sql

###############################################################################
# SQL Server 2016
Get-Content $scriptRootPath\SQL-2016\StoredProcs\memopt_GetCheckpointFiles.sql, $scriptRootPath\SQL-2016\StoredProcs\memopt_GetDatabaseInfo.sql, `
            $scriptRootPath\SQL-2016\StoredProcs\memopt_GetGarbageCollector.sql, $scriptRootPath\SQL-2016\StoredProcs\memopt_GetHashIndexes.sql, `
            $scriptRootPath\SQL-2016\StoredProcs\memopt_GetLoadedModules.sql, $scriptRootPath\SQL-2016\StoredProcs\memopt_GetObjects.sql, `
            $scriptRootPath\SQL-2016\StoredProcs\memopt_GetSQLInfo.sql, $scriptRootPath\SQL-2016\StoredProcs\memopt_GetTables.sql, `
            $scriptRootPath\SQL-2016\StoredProcs\memopt_SuggestedTables.sql | `
    Set-Content $scriptRootPath\SQL-2016\StoredProcs\memopt_install_all_stored_procs.sql

# Unit Tests for SQL Server 2016
#Get-Content $scriptRootPath\Tests\SQL-2016\*.sql | Set-Content $scriptRootPath\Tests\sql-2016-tests.sql


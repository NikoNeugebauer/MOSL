#	MOSL - Memory Optimised Scripts Library for SQL Server
#	Powershell Script to install the MOSL in the user databases
#	Version: 0.2.0, November 2016
#
#	Copyright 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/columnstore/), (http://www.oh22.is/)
#
#   This code is re-using the code from the amazing open-source project DBATools (https://github.com/sqlcollaborative/dbatools) 
#    created by Chrissy LeMaire & other collaborators
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

function Update-mosl(
    [parameter(Mandatory=$true)]
    $path = 'C:\Work\mosl'
)
{
    # Writing the header
    Write-Host "MOSL - Memory Optimised Scripts Library for SQL Server: " -ForegroundColor Green
    Write-Host "Version: 0.2.0, November 2016" -ForegroundColor Green
    Write-Host "(c) 2015-2016 Niko Neugebauer, OH22 IS (http://www.nikoport.com/columnstore/), (http://www.oh22.is/)" -ForegroundColor Green
    Write-Host "----------------------------------------------------------------------------------------------------"
    
        
    if (!(Test-Path -Path "$tempFolder\mosl"))
    {
        New-Item -Path "$tempFolder\mosl" -ItemType Directory | Out-Null
    }
    
    $url = 'https://github.com/NikoNeugebauer/MOSL/archive/master.zip'

    $tempFolder = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
    $zipfile = "$tempFolder\mosl.zip"


    if (!(Test-Path -Path $path))
    {
	    try
	    {
		    Write-Output "Creating directory: $path"
		    New-Item -Path $path -ItemType Directory | Out-Null
	    }
	    catch
	    {
		    throw "Can't create $Path. You may need to Run as Administrator"
	    }
    }
    else
    {
	    try
	    {
		    Write-Output "Deleting previously installed module"
		    Remove-Item -Path "$path\*" -Force -Recurse
	    }
	    catch
	    {
		    throw "Can't delete $Path. You may need to Run as Administrator"
	    }
    }

    Write-Output "Downloading archive from github"
	try
	{
		Invoke-WebRequest $url -OutFile $zipfile
	}
	catch
	{
		#try with default proxy and usersettings
		Write-Output "Probably using a proxy for internet access, trying default proxy settings"
		(New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
		Invoke-WebRequest $url -OutFile $zipfile
	}
	
	# Unblock if there's a block
	Unblock-File $zipfile -ErrorAction SilentlyContinue
	
	Write-Output "Unzipping"

    # Keep it backwards compatible
	$shell = New-Object -COM Shell.Application
	$zipPackage = $shell.NameSpace($zipfile)
	$destinationFolder = $shell.NameSpace($tempFolder)
	$destinationFolder.CopyHere($zipPackage.Items())
	
	Write-Output "Cleaning up"
	Move-Item -Path "$tempFolder\mosl-master\*" -Destination $path
	Remove-Item -Path "$tempFolder\mosl-master"
	Remove-Item -Path $zipfile
	
	Write-Output "Done!"
	#if ((Get-Command -Module mosl).count -eq 0) { Import-Module "$path\mosl.psd1" -Force }
	#Get-Command -Module mosl
	#Write-Output "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."
}
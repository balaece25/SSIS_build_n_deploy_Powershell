##
Run this File
```
#PowerShell: ParamsForGeneralEnvironmentDeploymentWithCsv.ps1
#################################################################################################
# Change source and destination properties
#################################################################################################
# Ssis
$SsisServer ="."
$EnvironmentFolderName = "Environments"
$EnvironmentName = "Generic"
 
# Path of CSV containing variables (you can also use format d:\file.csv)
$FilepathCsv = "$PSScriptRoot\EnvironmentVariables.csv"
 
# Execute deployment script
. "$PSScriptRoot\GeneralEnvironmentDeploymentWithCsv.ps1" $SsisServer $EnvironmentFolderName $EnvironmentName $FilepathCsv
```

##
##
Main File where Logic is 
```
#PowerShell: GeneralEnvironmentDeploymentWithCsv.ps1
################################
########## PARAMETERS ##########
################################ 
[CmdletBinding()]
Param(
    # SsisServer is required
    [Parameter(Mandatory=$True,Position=1)]
    [string]$SsisServer,
     
    # EnvironmentFolderName is required 
    [Parameter(Mandatory=$True,Position=2)]
    [string]$EnvironmentFolderName,
     
    # EnvironmentName is required
    [Parameter(Mandatory=$True,Position=3)]
    [string]$EnvironmentName,
     
    # FilepathCsv is required
    [Parameter(Mandatory=$True,Position=4)]
    [string]$FilepathCsv
)
 
clear
Write-Host "========================================================================================================================================================"
Write-Host "==                                                                 Used parameters                                                                    =="
Write-Host "========================================================================================================================================================"
Write-Host "SSIS Server             :" $SsisServer
Write-Host "Environment Name        :" $EnvironmentName
Write-Host "Environment Folder Path :" $EnvironmentFolderName
Write-Host "Filepath of CSV file    :" $FilepathCsv
Write-Host "========================================================================================================================================================"
 
 
#########################
########## CSV ##########
#########################
# Check if ispac file exists
if (-Not (Test-Path $FilepathCsv))
{
    Throw  [System.IO.FileNotFoundException] "CSV file $FilepathCsv doesn't exists!"
}
else
{
    $FileNameCsv = split-path $FilepathCsv -leaf
    Write-Host "CSV file" $FileNameCsv "found"
}
 
 
############################
########## SERVER ##########
############################
# Load the Integration Services Assembly
Write-Host "Connecting to SSIS server $SsisServer "
$SsisNamespace = "Microsoft.SqlServer.Management.IntegrationServices"
[System.Reflection.Assembly]::LoadWithPartialName($SsisNamespace) | Out-Null;
 
# Create a connection to the server
$SqlConnectionstring = "Data Source=" + $SsisServer + ";Initial Catalog=master;Integrated Security=SSPI;"
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection $SqlConnectionstring
 
# Create the Integration Services object
$IntegrationServices = New-Object $SsisNamespace".IntegrationServices" $SqlConnection
 
# Check if connection succeeded
if (-not $IntegrationServices)
{
  Throw  [System.Exception] "Failed to connect to SSIS server $SsisServer "
}
else
{
   Write-Host "Connected to SSIS server" $SsisServer
}
 
 
#############################
########## CATALOG ##########
#############################
# Create object for SSISDB Catalog
$Catalog = $IntegrationServices.Catalogs["SSISDB"]
 
# Check if the SSISDB Catalog exists
if (-not $Catalog)
{
    # Catalog doesn't exists. The user should create it manually.
    # It is possible to create it, but that shouldn't be part of
    # deployment of packages or environments.
    Throw  [System.Exception] "SSISDB catalog doesn't exist. Create it manually!"
}
else
{
    Write-Host "Catalog SSISDB found"
}
 
 
############################
########## FOLDER ##########
############################
# Create object to the (new) folder
$Folder = $Catalog.Folders[$EnvironmentFolderName]
 
# Check if folder already exists
if (-not $Folder)
{
    # Folder doesn't exists, so create the new folder.
    Write-Host "Creating new folder" $EnvironmentFolderName
    $Folder = New-Object $SsisNamespace".CatalogFolder" ($Catalog, $EnvironmentFolderName, $EnvironmentFolderName)
    $Folder.Create()
}
else
{
    Write-Host "Folder" $EnvironmentFolderName "found"
}
 
 
#################################
########## ENVIRONMENT ##########
#################################
# Create object for the (new) environment
$Environment = $Catalog.Folders[$EnvironmentFolderName].Environments[$EnvironmentName]
 
# Check if folder already exists
if (-not $Environment)
{
    Write-Host "Creating environment" $EnvironmentName in $EnvironmentFolderName
 
    $Environment = New-Object $SsisNamespace".EnvironmentInfo" ($Folder, $EnvironmentName, $EnvironmentName)
    $Environment.Create()
}
else
{
    Write-Host "Environment" $EnvironmentName "found with" $Environment.Variables.Count "existing variables"
    # Optional: Recreate to delete all variables, but be careful:
    # This could be harmful for existing references between vars and pars
    # if a used variable is deleted and not recreated.
    #$Environment.Drop()
    #$Environment = New-Object $SsisNamespace".EnvironmentInfo" ($folder, $EnvironmentName, $EnvironmentName)
    #$Environment.Create()
}
 
 
###############################
########## VARIABLES ##########
###############################
$InsertCount = 0
$UpdateCount = 0
 
 
Import-CSV $FilepathCsv -Header Datatype,ParameterName,ParameterValue,ParameterDescription,Sensitive -Delimiter ';' | Foreach-Object{
 If (-not($_.Datatype -eq "Datatype"))
 {
  #Write-Host $_.Datatype "|" $_.ParameterName "|" $_.ParameterValue "|" $_.ParameterDescription "|" $_.Sensitive
  # Get variablename from array and try to find it in the environment
  $Variable = $Catalog.Folders[$EnvironmentFolderName].Environments[$EnvironmentName].Variables[$_.ParameterName]
 
 
  # Check if the variable exists
  if (-not $Variable)
  {
   # Insert new variable
   Write-Host "Variable" $_.ParameterName "added"
   $Environment.Variables.Add($_.ParameterName, $_.Datatype, $_.ParameterValue, [System.Convert]::ToBoolean($_.Sensitive), $_.ParameterDescription)
 
   $InsertCount = $InsertCount + 1
  }
  else
  {
   # Update existing variable
   Write-Host "Variable" $_.ParameterName "updated"
   $Variable.Type = $_.Datatype
   $Variable.Value = $_.ParameterValue
   $Variable.Description = $_.ParameterDescription
   $Variable.Sensitive = [System.Convert]::ToBoolean($_.Sensitive)
 
   $UpdateCount = $UpdateCount + 1
  }
 }
} 
$Environment.Alter()
 
 
###########################
########## READY ##########
###########################
# Kill connection to SSIS
$IntegrationServices = $null
Write-Host "Finished, total inserts" $InsertCount " and total updates" $UpdateCount
```

##
##
CSV File
```
Datatype;Parameter Name;Parameter Value;Parameter Description;Sensitive (true or false)
String;MIS_STG_ConnectionString;"Data Source=.\sql2016;Initial Catalog=MIS_STG;Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False;";Connectionstring to stage database;false
String;MIS_HST_ConnectionString;"Data Source=.\sql2016;Initial Catalog=MIS_HST;Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False;";Connectionstring to historical stage database;false
String;MIS_DWH_ConnectionString;"Data Source=.\sql2016;Initial Catalog=MIS_DWH;Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False;";Connectionstring to data warehouse database;false
String;MIS_MTA_ConnectionString;"Data Source=.\sql2016;Initial Catalog=MIS_MTA;Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False;";Connectionstring to metadata database;false
String;MIS_DM_ConnectionString;"Data Source=.\sql2016;Initial Catalog=MIS_DM;Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False;";Connectionstring to data mart database;false
String;FtpPassword; 53cr3t!;Secret FTP password;true
String;FtpUser;SSISJoost;Username for FTP;false
String;FtpServer;ftp://SSISJoost.nl;FTP Server;false
String;FolderStageFiles;d:\sources\;Location of stage files;false
Boolean;EnableRetry; true;Enable retry for Webservice Task;false
Int16;NumberOfRetries;3;Number of retries for Webservice Task;false
Int16;SecsPauseBetweenRetry;30;Number of seconds between retry;false
```

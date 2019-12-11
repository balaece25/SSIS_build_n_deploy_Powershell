param(
    [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$false)]
    [string]$GitURL,
    [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$false)]
    [string]$ProjectFolderName,
    [Parameter(Mandatory=$True, Position=2, ValueFromPipeline=$false)]
    [string]$EnvType,
    [Parameter(Mandatory=$True, Position=2, ValueFromPipeline=$false)]
    [string]$GitBranch
)

# Timestamp while saving logs
function Get-TimeStamp {
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

$MyWorkSpace = (Get-Location).Path

# Path of CSV containing environment variables
$FilepathCsv = "$PSScriptRoot\EnvironmentVariables.csv"

# fetch details from config file
$configFile = Get-Content -Raw -Path .\Config.json | ConvertFrom-Json

$GitFolder = $GitURL.split("/")[$GitURL.split("/").length -1]

Write-Host "************************* $(Get-TimeStamp) *********************************"
Write-Host ("Project - ",$ProjectFolderName, "`nEnv - ",$EnvType, "`nGit Branch - ",$GitBranch) -ForegroundColor Green
Write-Host "**********************************************************"
<#
# condition to pull & clone
if(-not (Test-Path -LiteralPath $GitFolder)){
 	Write-Host "$(Get-TimeStamp) Cloning GIT URL $GitURL ......"
	git clone $GitURL
} else {
	Write-Host "$(Get-TimeStamp) Project Folder already exists."
	Write-Host "$(Get-TimeStamp) Fetching updates from remote git repo ......"
	Set-Location $GitFolder
	git pull
	Write-Host "$(Get-TimeStamp) local project up-to-date with remote git repo ......"
}
Set-Location $GitFolder
Write-Host "$(Get-TimeStamp) Changed Directory to Git Folder $GitFolder" -ForegroundColor Green
git checkout $GitBranch.
Write-Host "$(Get-TimeStamp) Git checked to branch $GitBranch" -ForegroundColor Green
#>

$SSISProjFolder = Get-ChildItem "$MyWorkSpace\$GitFolder\source" -Filter "*$ProjectFolderName*" -Directory
$SSISProjName = $SSISProjFolder.FullName
$SSISDBProjName = $SSISProjFolder.Name
$SSISProjETL = "$SSISProjName\ETL"
$SSISProjETLdtproj = "$SSISProjETL\ETL.dtproj"

Write-Host "$(Get-TimeStamp) .dtproj file ==> $SSISProjETLdtproj" -ForegroundColor Green

#& "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\IDE\devenv.com" $SSISProjETLdtproj  /Rebuild
& "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\devenv.com" $SSISProjETLdtproj  /Rebuild

$ispacFile = Get-ChildItem "$SSISProjETL\bin\Development" -Filter "*.ispac"
$ProjectFilePath = $ispacFile.FullName
$ProjectFileName = $ispacFile.Name
Write-Host "$(Get-TimeStamp) .ispac file ==> $ProjectFileName $ProjectFilePath" -ForegroundColor Green

$SSISDBServerEndpoint = $configFile.configuration.env.$EnvType.SSISDBServerEndpoint
$SSISDBServerAdminUserName = $configFile.configuration.env.$EnvType.SSISDBServerAdminUserName
$SSISDBServerAdminPassword = $configFile.configuration.env.$EnvType.SSISDBServerAdminPassword
$SSISDBAuthType = $configFile.configuration.env.$EnvType.SSISDBAuthType
$SSISFolderName = $SSISDBProjName
$SSISDescription = $SSISDBProjName
Write-Host "$(Get-TimeStamp) SQL server  ==> $SSISDBServerEndpoint" -ForegroundColor Green
Write-Host "$(Get-TimeStamp) SQL server Authentication Type  ==> $SSISDBAuthType" -ForegroundColor Green
Write-Host "**********************************************************"
Write-Host "********  Integration Services Assembly starts  **********"
Write-Host "**********************************************************"

# Load the IntegrationServices Assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices") | Out-Null;

# Store the IntegrationServices Assembly namespace to avoid typing it every time
$ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

Write-Host "$(Get-TimeStamp) Connecting to SSIS Server Instance ..." -ForegroundColor Green

# Create a connectionstring to the server windows authentication or sql server authentication
if ($SSISDBAuthType = "windows") {
    $sqlConnectionString = "Data Source=$SSISDBServerEndpoint;Initial Catalog=SSISDB; Integrated Security=SSPI;"
} else {
    $sqlConnectionString = "Data Source=" + $SSISDBServerEndpoint + ";User ID="+ $SSISDBServerAdminUserName +";Password="+ $SSISDBServerAdminPassword + ";Initial Catalog=$SSISFolderName"
}
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection $sqlConnectionString

Write-Host "$(Get-TimeStamp) slq connection set:" $sqlConnection

# Create the Integration Services object
$integrationServices = New-Object $ISNamespace".IntegrationServices" $sqlConnection

Write-Host "$(Get-TimeStamp) Integration Services object set:" $integrationServices -ForegroundColor Green

# Get the catalog
$catalog = $integrationServices.Catalogs["SSISDB"]
Write-Host "$(Get-TimeStamp) The catalog is:" $catalog

############################
########## FOLDER ##########
############################
$ssisFolder = $catalog.Folders.Item($SSISFolderName)
Write-Host "$(Get-TimeStamp) SSIS Folder is:" $ssisFolder -ForegroundColor Green

# Verify if we have already this folder
if (!$ssisFolder)
{
    write-host "Create folder on Catalog SSIS instance"
    $folder = New-Object Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder($catalog, $SSISFolderName, $SSISDescription) 
	write-host "New folder on catalog:" $folder -ForegroundColor Green
    $folder.Create()
    $ssisFolder = $catalog.Folders.Item($SSISFolderName)
    write-host "Newly created SSIS folder:" $ssisFolder
}

#################################
########## ENVIRONMENT ##########
#################################
# Create object for the (new) environment
$Environment = $ssisFolder.Environments[$EnvType]
if (!$Environment)
{
    Write-Host "$(Get-TimeStamp) Creating environment" $EnvType "in" $SSISFolderName -ForegroundColor Green
    $Environment = New-Object Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo($ssisFolder, $EnvType, $EnvType)
    $Environment.Create()
    Write-Host "$(Get-TimeStamp) Environment Created"
}

#Check if project is already deployed or not, if deployed deop it and deploy again
Write-Host "$(Get-TimeStamp) Checking if project is already deployed or not, if deployed drop it and deploy again" -ForegroundColor Green

$ssisProjectName = $ProjectFileName.Replace(".ispac", "")

if($ssisFolder.Projects.Item($ssisProjectName))
{
    Write-Host "$(Get-TimeStamp) Project with the name $ssisProjectName already exists. Would you like to drop it and deploy again y or n (Default is n) - " -ForegroundColor DarkYellow
    $usrResponse = Read-Host " (y / n ) "
    Switch ($usrResponse)
    {
        y {
            Write-host "Yes, Drop & Re-Deploy" -ForegroundColor Green
            $ssisFolder.Projects.Item($ssisProjectName).Drop()

            Write-Host "$(Get-TimeStamp) Re-Deploying " $ProjectFileName " project in $ssisFolder..."
            #Read the project file, and deploy it to the folder
            $ssisFolder.DeployProject($ssisProjectName,[System.IO.File]::ReadAllBytes($ProjectFilePath))
        }
        n {
            Write-Host "$(Get-TimeStamp) No, Skip Drop" -ForegroundColor Green
        }
        Default {
            Write-Host "$(Get-TimeStamp) Default, Skip Drop" -ForegroundColor Green
        }
    }

}

if(!$ssisFolder.Projects.Item($ssisProjectName))
{
    Write-Host "$(Get-TimeStamp) Deploying " $ProjectFileName " project ..."
    #Read the project file, and deploy it to the folder
    $ssisFolder.DeployProject($ssisProjectName,[System.IO.File]::ReadAllBytes($ProjectFilePath))
}

###############################
########## ENVIRONMENT VARIABLES ##########
###############################
$InsertCount = 0
$UpdateCount = 0


Import-CSV $FilepathCsv -Header Datatype,ParameterName,ParameterValue,ParameterDescription,Sensitive -Delimiter ';' | Foreach-Object{
 If (-not($_.Datatype -eq "Datatype"))
 {
  #Write-Host $_.Datatype "|" $_.ParameterName "|" $_.ParameterValue "|" $_.ParameterDescription "|" $_.Sensitive
  # Get variablename from array and try to find it in the environment
  $Variable = $Environment.Variables[$_.ParameterName]


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

##############################################
########## ENV REFERENCE TO PROJECT ##########
##############################################
Write-Host "Adding environment reference to project ..."

# making project refer to this environment
$project = $ssisFolder.Projects[$ssisProjectName]
$project.References.Add($EnvType, $SSISFolderName)
$project.Alter()

###########################
########## READY ##########
###########################
# Kill connection to SSIS
$integrationServices = $null
Write-Host "Finished, total inserts" $InsertCount " and total updates" $UpdateCount
#cd..
Set-Location $MyWorkSpace

Write-Host "$(Get-TimeStamp) All done." -ForegroundColor Green

Write-Host "#---------------------------------------------------------------------#"

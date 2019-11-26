# git clone https://user:token@dev.azure.com/proj/test/_git/test

# & cd test

# git checkout branchname

param(
    # [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$false)]
    [string]$GitURL="https://user:token@dev.azure.com/proj/test/_git/test",
    # [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$false)]
    [string]$ProjectFolderName="life",
    # [Parameter(Mandatory=$True, Position=2, ValueFromPipeline=$false)]
    [string]$EnvType="sit",
    # [Parameter(Mandatory=$True, Position=2, ValueFromPipeline=$false)]
    [string]$GitBranch="master"
)

$MyWorkSpace = (Get-Location).Path
$GitFolder = $GitURL.split("/")[$GitURL.split("/").length -1]

Write-Host "**********************************************************"
Write-Host ("Project - ",$ProjectFolderName, "`nEnv - ",$EnvType, "`nGit Branch - ",$GitBranch) -ForegroundColor Green
Write-Host "**********************************************************"

# condition to pull & clone
if(-not (Test-Path -LiteralPath $GitFolder)){
	Write-Host "Cloning GIT URL $GitURL ......"
	git clone $GitURL
} else {
	Write-Host "Project Folder already exists."
	Write-Host "Fetching updates from remote git repo ......"
	Set-Location $GitFolder
	git pull
	Write-Host "local project up-to-date with remote git repo ......"
}

# fetch details from config file
$configFile = Get-Content -Raw -Path .\Config.json | ConvertFrom-Json

Set-Location $GitFolder

Write-Host "Changed Directory to Git Folder $GitFolder" -ForegroundColor Green

git checkout $GitBranch.

Write-Host "Git checked to branch $GitBranch" -ForegroundColor Green

$SSISProjFolder = Get-ChildItem "$MyWorkSpace\$GitFolder\source" -Filter "*$ProjectFolderName*" -Directory
$SSISProjName = $SSISProjFolder.FullName
$SSISDBProjName = $SSISProjFolder.Name
$SSISProjETL = "$SSISProjName\ETL"
$SSISProjETLdtproj = "$SSISProjETL\ETL.dtproj"

Write-Host ".dtproj file ==> $SSISProjETLdtproj" -ForegroundColor Green

& "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\IDE\devenv.com" $SSISProjETLdtproj  /Rebuild

$ispacFile = Get-ChildItem "$SSISProjETL\bin\Development" -Filter "*.ispac"
$ProjectFilePath = $ispacFile.FullName
$ProjectFileName = $ispacFile.Name
Write-Host ".ispac file ==> $ProjectFileName $ProjectFilePath" -ForegroundColor Green

$SSISDBServerEndpoint = $configFile.configuration.env.$EnvType.SSISDBServerEndpoint
$SSISDBServerAdminUserName = $configFile.configuration.env.$EnvType.SSISDBServerAdminUserName
$SSISDBServerAdminPassword = $configFile.configuration.env.$EnvType.SSISDBServerAdminPassword
$SSISDBAuthType = $configFile.configuration.env.$EnvType.SSISDBAuthType
$SSISFolderName = $SSISDBProjName
$SSISDescription = $SSISDBProjName
Write-Host "SQL server  ==> $SSISDBServerEndpoint" -ForegroundColor Green
Write-Host "SQL server Authentication Type  ==> $SSISDBAuthType" -ForegroundColor Green
Write-Host "**********************************************************"
Write-Host "********  Integration Services Assembly starts  **********"
Write-Host "**********************************************************"

# Load the IntegrationServices Assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices") | Out-Null;

# Store the IntegrationServices Assembly namespace to avoid typing it every time
$ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

Write-Host "Connecting to SSIS Server Instance ..." -ForegroundColor Green

# Create a connectionstring to the server windows authentication or sql server authentication
if ($SSISDBAuthType = "windows") {
    $sqlConnectionString = "Data Source=$SSISDBServerEndpoint;Initial Catalog=SSISDB; Integrated Security=SSPI;"
} else {
    $sqlConnectionString = "Data Source=" + $SSISDBServerEndpoint + ";User ID="+ $SSISDBServerAdminUserName +";Password="+ $SSISDBServerAdminPassword + ";Initial Catalog=$SSISFolderName"
}
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection $sqlConnectionString

Write-Host "slq connection set:" $sqlConnection

# Create the Integration Services object
$integrationServices = New-Object $ISNamespace".IntegrationServices" $sqlConnection

Write-Host "Integration Services object set:" $integrationServices -ForegroundColor Green

# Get the catalog
$catalog = $integrationServices.Catalogs['SSISDB']
Write-Host "The catalog is:" $catalog

############################
########## FOLDER ##########
############################
$ssisFolder = $catalog.Folders.Item($SSISFolderName)
Write-Host "SSIS Folder is:" $ssisFolder -ForegroundColor Green

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
    Write-Host "Creating environment" $EnvType "in" $SSISFolderName -ForegroundColor Green
    $Environment = New-Object Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo($ssisFolder, $EnvType, $EnvType)
    $Environment.Create()
    Write-Host "Environment Created"
}

#Check if project is already deployed or not, if deployed deop it and deploy again
Write-Host "Checking if project is already deployed or not, if deployed drop it and deploy again" -ForegroundColor Green

$ssisProjectName = $ProjectFileName.Replace(".ispac", "")

if($ssisFolder.Projects.Item($ssisProjectName))
{
    Write-Host "Project with the name $ssisProjectName already exists. Would you like to drop it and deploy again 'y or n' (Default is n) - " -ForegroundColor DarkYellow
    $usrResponse = Read-Host " (y / n ) "
    Switch ($usrResponse)
    {
        y {
            Write-host "Yes, Drop & Re-Deploy" -ForegroundColor Green
            $ssisFolder.Projects.Item($ssisProjectName).Drop()

            Write-Host "Re-Deploying " $ProjectFileName " project in $ssisFolder..."
            #Read the project file, and deploy it to the folder
            $ssisFolder.DeployProject($ssisProjectName,[System.IO.File]::ReadAllBytes($ProjectFilePath))
        }
        n {
            Write-Host "No, Skip Drop" -ForegroundColor Green
        }
        Default {
            Write-Host "Default, Skip Drop" -ForegroundColor Green
        }
    }

}

if(!$ssisFolder.Projects.Item($ssisProjectName))
{
    Write-Host "Deploying " $ProjectFileName " project ..."
    #Read the project file, and deploy it to the folder
    $ssisFolder.DeployProject($ssisProjectName,[System.IO.File]::ReadAllBytes($ProjectFilePath))
}

#cd..
Set-Location $MyWorkSpace

Write-Host "All done." -ForegroundColor Green
<#
write-host "Enumerating all folders in the project code"

$folders = ls -Path $ProjectFilePath -File
write-host "The folders in the project code are:" $folders

# If we have some folders to treat
if ($folders.Count -gt 0)
{
	#Treat one by one them
    foreach ($filefolder in $folders)
    {
		write-host "File folder:" $filefolder
        $projects = ls -Path $filefolder.FullName -File -Filter *.ispac
		write-host "Projects:" $projects
        if ($projects.Count -gt 0)
        {
            foreach($projectfile in $projects)
            {
				write-host "Project File:" $projectfile
				write-host "ISPAC File ==> "$projectfile.Name.Replace(".ispac", "")
                write-host "Project File Name Fullname ==> "$projectfile.FullName

				$projectfilename = $projectfile.Name.Replace(".ispac", "")
				$ssisProject = $ssisFolder.Projects.Item($projectfilename)
                write-host "-------------SSIS project:" $ssisProject, "pfn", $projectfilename
                # Dropping old project
                if(![string]::IsNullOrEmpty($ssisProject))
                {
                    write-host "Drop Old SSIS Project ==> "$ssisProject.Name
                    $ssisProject.Drop()
                }

                Write-Host "Deploying " $projectfilename " project ..."

                # Read the project file, and deploy it to the folder
                [byte[]] $projectFileContent = [System.IO.File]::ReadAllBytes($projectfile.FullName)
				write-host "Project File Content:" $projectfile.FullName, $projectfilename, $ssisFolder
                $ssisFolder.DeployProject($projectfilename, $projectFileContent)
            }
        }
    }
}

###############   SCRIPT to run a SQL Script ####################

# $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
# $connection.Open()

# $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
# $dataset = New-Object System.Data.DataSet
# $adapter.Fill($dataSet) | Out-Null

# $connection.Close()
# $dataSet.Tables

Write-Host "All done."

Set-Location -Path $MyWorkSpace

###############   SCRIPT for DROP Folder ####################

# $folder = $catalog.Folders[$FolderName]

# if($folder.Environments.Contains($EnvironmentName)) {
#     $folder.Environments[$EnvironmentName].Drop()
# }

# if($folder.Projects.Contains($ProjectName)) {
#     $folder.Projects[$ProjectName].Drop()
# }

# $folder.Drop()
#>

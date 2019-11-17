
# git clone https://user:token@dev.azure.com/proj/test/_git/test 

# & cd test

# git checkout branchname

param(
    # [Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$false)]
    [string]$GitURL="https://user:token@dev.azure.com/proj/test/_git/test",
    # [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$false)]
    [string]$ProjectFolderName="life",
    # [Parameter(Mandatory=$True, Position=2, ValueFromPipeline=$false)]
    [string]$EnvType="sit"
)

$GitFolder = $GitURL.split("/")[$GitURL.split("/").length -1]
$MyWorkSpace = $PSScriptRoot

Write-Host "**********************************************************"
Write-Host ("Project - ",$ProjectFolderName, "`nEnv - ",$EnvType)
Write-Host "**********************************************************"


#[xml]$configFile = Get-Content .\Config.xml
$configFile = Get-Content -Raw -Path .\Config.json | ConvertFrom-Json

Write-Host $configFile.configuration.env.$EnvType.SSISDBServerEndpoint


# git clone $GitURL

# Set-Location $GitFolder

Write-Host "Changed Directory to Git Folder $GitFolder"

# git checkout branchname.
Write-Host "Git checked to branch"

$SSISProjFolder = Get-ChildItem "$MyWorkSpace\$GitFolder\source" -Filter "*$ProjectFolderName*" -Directory
$SSISProjName = $SSISProjFolder.FullName
$SSISDBProjName = $SSISProjFolder.Name
$SSISProjETL = "$SSISProjName\ETL"
$SSISProjETLdtproj = "$SSISProjETL\ETL.dtproj"

Write-Host $SSISProjETLdtproj

& "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\IDE\devenv.com" $SSISProjETLdtproj  /Rebuild

$ispacFile = Get-ChildItem "$SSISProjETL\bin\Development" -Filter "*.ispac"
$ProjectFilePath = $ispacFile.FullName
Write-Host $ProjectFilePath

$SSISDBServerEndpoint = $configFile.configuration.env.$EnvType.SSISDBServerEndpoint
$SSISDBServerAdminUserName = $configFile.configuration.env.$EnvType.SSISDBServerAdminUserName
$SSISDBServerAdminPassword = $configFile.configuration.env.$EnvType.SSISDBServerAdminPassword
$SSISFolderName = $SSISDBProjName
$SSISDescription = $SSISDBProjName
Write-Host $SSISDBServerEndpoint
Write-Host "**********************************************************"
Write-Host "*******************  Script starts  **********************"
Write-Host "**********************************************************"

# Load the IntegrationServices Assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices") | Out-Null;

# Store the IntegrationServices Assembly namespace to avoid typing it every time
$ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

Write-Host "Connecting to SSIS Instance server ..."

# Create a connection to the server
# $sqlConnectionString = "Data Source=" + $SSISDBServerEndpoint + ";User ID="+ $SSISDBServerAdminUserName +";Password="+ $SSISDBServerAdminPassword + ";Initial Catalog=$SSISFolderName"
$sqlConnectionString = "Data Source=$SSISDBServerEndpoint;Initial Catalog=SSISDB; Integrated Security=SSPI;"
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection $sqlConnectionString

Write-Host "slq connection set:" $sqlConnection

# Create the Integration Services object
$integrationServices = New-Object $ISNamespace".IntegrationServices" $sqlConnection

Write-Host "Integration Services object set:" $integrationServices

# Get the catalog
$catalog = $integrationServices.Catalogs['SSISDB']
Write-Host "The catalog is:" $catalog

$ssisFolder = $catalog.Folders.Item($SSISFolderName)
Write-Host "SSIS Folder is:" $ssisFolder

# Verify if we have already this folder
if (!$ssisFolder)
{
    write-host "Create folder on Catalog SSIS instance"
    $folder = New-Object Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder($catalog, $SSISFolderName, $SSISDescription) 
	write-host "New folder on catalog:" $folder
    $folder.Create()
    $ssisFolder = $catalog.Folders.Item($SSISFolderName)
	write-host "Newly created SSIS folder:" $ssisFolder
}

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
                write-host "SSIS project:" $ssisProject
                # Dropping old project
                if(![string]::IsNullOrEmpty($ssisProject))
                {
                    write-host "Drop Old SSIS Project ==> "$ssisProject.Name
                    $ssisProject.Drop()
                }

                Write-Host "Deploying " $projectfilename " project ..."

                # Read the project file, and deploy it to the folder
                [byte[]] $projectFileContent = [System.IO.File]::ReadAllBytes($projectfile.FullName)
				write-host "Project File Content:" $projectfile.FullName
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

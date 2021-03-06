<# .SYNOPSIS Script Settings File Demo #>

#[CmdletBinding()]
#param ()

#-------------------------------------------------
#  Load Settings
#-------------------------------------------------

#$MyDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$MyDir = "C:\Scripts"

# Import settings from config file
[xml]$ConfigFile = Get-Content "$MyDir\bfbk.xml"

$bkSettings = @{
    localPath = $ConfigFile.Settings.bkSettings.localPath
    remotePath = $ConfigFile.Settings.bkSettings.remotePath
    numBksToKeep = $ConfigFile.Settings.bkSettings.numBksToKeep
    pathToBES = $ConfigFile.Settings.bkSettings.pathToBES
}

$bkList = $ConfigFile.Settings.bkList.item

Write-Host "Backup items specified in settings:"
$bkList | % { Write-Host ( "`t" + $_ ) }
Write-Host ( "Total items specified in settings: " + $bkList.count )


#-------------------------------------------------
#  Validate Script Settings
#-------------------------------------------------

$localPathWorks = $false
$remotePathWorks = $false

if ( Test-Path $bkSettings.localPath ) {
    $localPathWorks = $true
    Write-Host "OK!`t`tPath to local BK dir is valid" 
} else {
    Write-Host "WARN!`tPath to local BK dir is invalid" 
}
if ( Test-Path $bkSettings.remotePath ) {
    $remotePathWorks = $true
    Write-Host "OK!`t`tPath to remote BK dir is valid" 
} else {
    Write-Host "WARN!`tPath to remote BK dir is invalid" 
}
if (!( $localPathWorks -or $remotePathWorks )) {
   Write-Host "ERROR!`tLocal and remote BK dirs are invalid"
    exit
}
if ( ( $bkSettings.numBksToKeep -as [int] ) -is [int] ) {
    Write-Host ( "OK!`t`t" + $bkSettings.numBksToKeep + " is a valid number of backups to keep" )
} else {
    $bkSettings.numDailyToKeep = 2
    Write-Host ( "WARN!`tdefaulting to " + $bkSettings.numBksToKeep + " for backups to keep" )
}
if (Test-Path $bkSettings.pathToBES) {
    Write-Host "OK!`t`tPath to BES is valid" 
} else {
    Write-Host "ERROR!`tPath to BES is invalid"
    exit
}

#-------------------------------------------------
#  Pre-Backup Stuff
#-------------------------------------------------

cd $bkSettings.pathToBES

$command = @'
.\ServerKeyTool.exe decrypt .\UnencryptedServerKey.pvk
'@
Invoke-Expression -Command $command

[string]$newTimestamp = $(get-date -f yyyyMMddHHmmss)

$serverBkDir = $($bkSettings.localPath+$newTimestamp+'\BES Server\')

mkdir ($serverBkDir)

#-------------------------------------------------
#  Stop le services
#-------------------------------------------------

Stop-Service -Name BESClient
Stop-Service -Name BESRootServer
Stop-Service -Name BESGather
Stop-Service -Name GatherDB
Stop-Service -Name FillDB

#-------------------------------------------------
#  Ok, time to back up le files!
#-------------------------------------------------

Write-Host "Backup items specified in settings:"

foreach ($bkItem in $bkList) {
    Write-Host ( "`t" + $bkItem )
    Copy-Item -Path ($bkSettings.pathToBES+$bkItem) -Recurse -Destination ($serverBkDir+$bkItem) -ErrorAction SilentlyContinue
}

Write-Host ( "Total items specified in settings: " + $bkList.count )

Remove-Item .\UnencryptedServerKey.pvk

#-------------------------------------------------
#  Ok, time to back up le DBs!
#-------------------------------------------------

$ServerName = "DOTHQNWAS130"
$dbBkDir = $($bkSettings.localPath+$newTimestamp+'\BES DBs\')
mkdir $dbBkDir
$BackupDirectory = $dbBkDir

#[System.Reflection.Assembly]::Load("Microsoft.SqlServer.SMO, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91") | out-null
#[System.Reflection.Assembly]::Load('Microsoft.SqlServer.SMOExtended, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91')
Add-Type -AssemblyName "Microsoft.SqlServer.SMOExtended, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
Add-Type -AssemblyName "Microsoft.SqlServer.SMO, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"

$ServerSMO = new-object ("Microsoft.SqlServer.Management.Smo.Server") $ServerName
$ServerSMO.ConnectionContext.StatementTimeout = 0

Write-Host "Starting backup of BFEnterprise"
$DatabaseName = "BFEnterprise"
$DatabaseBackup1 = new-object ("Microsoft.SqlServer.Management.Smo.Backup")
$DatabaseBackup1.Action = "Database"
$DatabaseBackup1.Database = $DatabaseName
$DatabaseBackup1.Devices.AddDevice($BackupDirectory + $DatabaseName + ".BAK", "File")
$DatabaseBackup1.SqlBackup($ServerSMO)
Write-Host "Ending backup of BFEnterprise"

Write-Host "Starting backup of BESReporting"
$DatabaseName = "BESReporting"
$DatabaseBackup2 = new-object ("Microsoft.SqlServer.Management.Smo.Backup")
$DatabaseBackup2.Action = "Database"
$DatabaseBackup2.Database = $DatabaseName
$DatabaseBackup2.Devices.AddDevice($BackupDirectory + $DatabaseName + ".BAK", "File")
$DatabaseBackup2.SqlBackup($ServerSMO)
Write-Host "Ending backup of BESReprorting"


#-------------------------------------------------
#  Start le services
#-------------------------------------------------

Start-Service -Name BESClient
Start-Service -Name GatherDB
Start-Service -Name FillDB
Start-Service -Name BESRootServer
Start-Service -Name BESGather

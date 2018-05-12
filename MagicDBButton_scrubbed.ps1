####################################################
# Magic Database Button
# Author:  Kyle Wagner
# Version 3.1 - 2018.05.01
####################################################
# Change Log

####################################################

Clear-Host

####################################################
# Environment variables
####################################################

# LAB BUILD SERVER
$labMainDir = 'LOCAL PATH OF SUB FILES'
$labBuildBackupFilePath = "LOCAL SHARED BACKUP DIRECTORY"
$labBuildInstance = 'LOCAL SERVER\INSTANCE'

# LAB BI SERVER
$labBIBackupFilePath = 'REMOTE LAB SERVER BACKUP DIRECTORY'
$labBIInstance = 'REMOTE LAB SERVER\INSTANCE'

# PROD BUILD SERVER
$prodBuildInstance = 'REMOTE PROD SERVER\INSTANCE'

#	PROD BI SERVER
$prodBIFilePath = 'REMOTE PROD SERVER BACKUP DIRECTORY'
$prodBIInstance = 'REMOTE PROD SERVER\INSTANCE'

####################################################
# Request Variables
####################################################

# REACHES OUT TO STAGE TABLE TO GRAB NEEDED VALUES
$employee = $sqlCmd.ExecuteScalar()
$email = $sqlCmd.ExecuteScalar()
$devTicket = $sqlCmd.ExecuteScalar()
$newUIConversion = $sqlCmd.ExecuteScalar()
$emailDomainChange = $sqlCmd.ExecuteScalar()
$reason = $sqlCmd.ExecuteScalar()
$companyName = $sqlCmd.ExecuteScalar()
$adminRequired = $sqlCmd.ExecuteScalar()
$admindb = $sqlCmd.ExecuteScalar()
$builddb = $sqlCmd.ExecuteScalar()
$bidb = $sqlCmd.ExecuteScalar()

####################################################
# Email variables
####################################################

$smtpServer = ''
$emailTo = "$employee <$email>"
#$emailCC = "$employee <$email>"
#$emailAdminCC = "$employee <$email>"
$emailCC = @('DBA Team<>')
$emailAdminCC = @('DBA Team <>', 'Customer Support <>')
$emailFrom = "Production Lab <>"
$emailSubjectStart = "Database Request Started"
$emailSubjectFinish = "Database Request Completed"
$emailAdminWarning = "ADMIN IS BEING REPLACED AS A PART OF THIS REQUEST AND THIS CAN CAUSE A SITE INTERUPTION. <br/><br/>"
$emailBodyStart = "Hello $employee,<br /><br />Your database request for $devTicket is now being processed. You will receive an email when the process is complete and available for your use. <br /><br />"
$emailBodyFinish = "Hello $employee,<br /><br />Your database request for $devTicket has been processed. The databases are now available for use. Please see below for request details and any errors encountered. <br /><br />"
$emailRequestInfo = "Developer: $employee <br />Developer Email: $email <br />Ticket Number: $devTicket <br />Reason for Restore: $reason <br /><br />Company Name: $companyName <br />Admin Requested?: $adminRequired <br />Transaction Database: $builddb<br />BI Database: $bidb"
	
$date = get-date -format MMddyyyy

####################################################
# Email User Function
####################################################

Function SendUserEmail ($adminRequired)
{
	$status = $sqlCmd.ExecuteScalar()
	IF ($status -eq "Started") #Send start email
	{
		IF ($adminRequired -eq "True") #Send email to customer support if admin is getting replaced
		{
			Try #attempt email
			{
				$emailBody = $emailAdminWarning + $emailBodyStart + $emailRequestInfo
				send-mailmessage -SmtpServer $smtpServer -to $emailTo -cc $emailAdminCC -from $emailFrom -subject $emailSubjectStart -BodyAsHtml $emailBody 
				Write-Warning "Email notication was sent to: $email"
			}
			Catch #write to error column if failed
			{
				UpdateStatus "Error" "True" "There was an error sending start email for admin replacement.<br/>" $companyName
			}
		}
		ELSE #don't send to customer support if admin isn't getting touched
		{
			Try #attempt email
			{
				$emailBody = $emailBodyStart + $emailRequestInfo
				send-mailmessage -SmtpServer $smtpServer -to $emailTo -cc $emailCC -from $emailFrom -subject $emailSubjectStart -BodyAsHtml $emailBody 
				Write-Warning "Email notication was sent to: $email"
			}
			Catch #write to error column if failed
			{
				UpdateStatus "Error" "True" "There was an error sending start email for no admin replacement.<br/>" $companyName
			}
		}
	}
	ELSEIF ($status -eq "Send Finish Email") #send complete email
	{
		IF ($adminRequired -eq "True") #Send email to customer support if admin is getting replaced
		{
			Try #attempt email
			{
				$emailErrorBody = $sqlCmd.ExecuteScalar()
				$emailErrorBody = "Error Messages received during restore: <br/>$emailErrorBody <br/><br/>"
				$emailBody = $emailBodyFinish + $emailErrorBody + $emailRequestInfo
				send-mailmessage -SmtpServer $smtpServer -to $emailTo -cc $emailAdminCC -from $emailFrom -subject $emailSubjectFinish -BodyAsHtml $emailBody
				Write-Warning "Email notication was sent to: $email"
			}
			Catch #write to error column if failed
			{
				UpdateStatus "Error" "True" "There was an error sending complete email for admin replacement.<br/>" $companyName
			}
		}
		ELSE #don't send to customer support if admin isn't getting touched
		{
			Try #attempt email
			{
				$emailErrorBody = $sqlCmd.ExecuteScalar()
				$emailErrorBody = "Error Messages received during restore: <br/>$emailErrorBody <br/><br/>"
				$emailBody = $emailBodyFinish + $emailErrorBody+ $emailRequestInfo
				send-mailmessage -SmtpServer $smtpServer -to $emailTo -cc $emailCC -from $emailFrom -subject $emailSubjectFinish -BodyAsHtml $emailBody
				Write-Warning "Email notication was sent to: $email"
			}
			Catch #write to error column if failed
			{
				UpdateStatus "Error" "True" "There was an error sending complete email for no admin replacement.<br/>" $companyName
			}
		}
	}
	ELSE
	{
		UpdateStatus "Error" "True" "There was an error sending complete email for reading the status $status .<br/>" $companyName
	}
}

####################################################
# UpdateStatus Function
####################################################

Function UpdateStatus ($status, $active, $errorMessage, $companyName)
{
	Invoke-Sqlcmd -Query "exec SCRATCHDB.dbo.usp_UpdateStatus @status = '$status', @active = '$active', @errorMessage = '$errorMessage', @companyName = '$companyName'" -ServerInstance $labBuildInstance
}

####################################################
# Backup Database Function
####################################################

Function BackupDatabase ($dbType, $db, $adminRequired)
{	
	IF ($dbType -eq "ADMIN" -and $adminRequired -eq "True") #build the filename for admin
	{
		$dbFilename = $admindb + "_" + $builddb + "_" + $date + ".bak"
	}
	ELSE #build the filename for build or BI
	{
		$dbFilename = $db + "_" + $date + ".bak"
	}
	
	IF ($dbType -eq "ADMIN" -or $dbType -eq "BUILD") #backup admin or build database
	{
		Try #attempt backup
		{
			$dbPathFile = $labBuildBackupFilePath+$dbFilename
			Backup-SqlDatabase -ServerInstance $prodBuildInstance -Database $db -BackupFile $dbPathFile -CopyOnly
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error backing up Admin or Build.<br/>" $companyName
		}
	}
	ELSEIF ($dbType -eq "BI") #backup BI database
	{
		Try #attempt backup
		{
			$dbPathFile1 = $prodBIFilePath+$dbFilename
			$dbPathFile = $labBIBackupFilePath+$dbFilename
			Backup-SqlDatabase -ServerInstance $prodBIInstance -Database $db -BackupFile $dbPathFile1 -CopyOnly
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error backing up BI.<br/>" $companyName
		}
		Try #attempt copy from prod to lab
		{
			Copy-Item -Path Microsoft.PowerShell.Core\FileSystem::$dbPathFile1 -Destination Microsoft.PowerShell.Core\FileSystem::$dbPathFile
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error copying BI to the lab.<br/>" $companyName
		}
	}  
}

####################################################
# Restore Database Function
####################################################

Function RestoreDatabase ($dbType, $db, $adminRequired)
{
	IF ($dbType -eq "ADMIN" -and $adminRequired -eq "True") #admin db restore
	{
		Try #attempt admin restore
		{
            $dbFilename = $admindb + "_" + $builddb + "_" + $date + ".bak"
			$adminfile = Get-ChildItem $labMainDir\"TEMPLATE_Admin.sql"
			$content = Get-Content ($adminfile)
			$content 	-replace "xx_FILENAME_xx", "$dbFilename" `
						-replace "xx_Path_xx", "$labBuildBackupFilePath" `
						-replace "xx_ADMINDB_xx", "$db" |
			Set-Content $labMainDir\'Admin.sql'
			$sql = "sqlcmd -S $labBuildInstance -E -i $labMainDir\Admin.sql"
			Invoke-Expression $sql
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error restoring admin.<br/>" $companyName
		}
	}
	ELSEIF ($dbType -eq "BUILD") #build db restore
	{
		Try #attempt build restore
		{
			$dbFilename = $db + "_" + $date + ".bak"
			$buildfile = Get-ChildItem $labMainDir\"TEMPLATE_Build.sql"
			$content = Get-Content ($buildfile)
			$content 	-replace "xx_FILENAME_xx", "$dbFilename" `
						-replace "xx_Path_xx", "$labBuildBackupFilePath" `
						-replace "xx_BUILD_xx", "$db" |
			Set-Content $labMainDir\'Build.sql'
			$sql = "sqlcmd -S $labBuildInstance -E -i $labMainDir\Build.sql"
			Invoke-Expression $sql
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error restoring build.<br/>" $companyName
		}
	}
	ELSEIF ($dbType -eq "BI") #BI db restore
	{
		Try #attempt to drop existing BI db if existing
		{
			$ifExists = Get-ChildItem $labMainDir\"TEMPLATE_DropBIIfExists.sql"
			$content = Get-Content ($ifExists)
			$content 	-replace "xx_BI_xx", "$db" |
			Set-Content $labMainDir\'DropBIIfExists.sql'
			$sql = "sqlcmd -S $labBIInstance -E -i $labMainDir\DropBIIfExists.sql"
			Invoke-Expression $sql
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error dropping the existing BI.<br/>" $companyName
		}
		Try #attempt to find logical file names for restore with move
		{
			$logicalName = $sqlCmd.ExecuteScalar()
			$logicalDataName = $logicalName
			$logicalLogName = $logicalName+"_log"
			$phyicalDataFileName = "LOCAL DATA DRIVE\"+$db+".mdf"
			$phyicalLogFileName = "LOCAL LOG DRIVE\"+$db+".ldf"
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error finding the logical file names.<br/>" $companyName
		}
		Try #attempt BI restore
		{
			$dbFilename = $db + "_" + $date + ".bak"
			$labBIPathFile = $labBIBackupFilePath + $dbFilename
			$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($logicalDataName, $phyicalDataFileName)
			$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($logicalLogName, $phyicalLogFileName)
			Restore-SqlDatabase -ServerInstance $labBIInstance -Database $db -BackupFile $labBIPathFile -RelocateFile @($RelocateData,$RelocateLog)
		}
		Catch #write to error column if failed
		{
			UpdateStatus "Error" "True" "There was an error restoring BI.<br/>" $companyName
		}
	}
}

####################################################
# Execution
####################################################
$IsThereAnActiveRecord = $sqlCmd.ExecuteScalar()
IF ($IsThereAnActiveRecord -eq 0)
{
	EXIT
}
ELSE
{
	UpdateStatus 'Started' 'True' '' $companyName
	SendUserEmail $adminRequired
	UpdateStatus 'Backup Admin' 'True' '' $companyName
	BackupDatabase 'ADMIN' $admindb $adminRequired
	UpdateStatus 'Backup Build' 'True' '' $companyName
	BackupDatabase 'BUILD' $builddb $adminRequired
	UpdateStatus 'Backup BI' 'True' '' $companyName
	BackupDatabase 'BI' $bidb $adminRequired
	UpdateStatus 'Restore Build' 'True' '' $companyName
	RestoreDatabase 'BUILD' $builddb $adminRequired
	UpdateStatus 'Restore BI' 'True' '' $companyName
	RestoreDatabase 'BI' $bidb $adminRequired
	UpdateStatus 'Restore Admin' 'True' '' $companyName
	RestoreDatabase 'ADMIN' $admindb $adminRequired
	UpdateStatus 'Send Finish Email' 'True' '' $companyName
	SendUserEmail $adminRequired
	UpdateStatus 'Complete' 'False' '' $companyName
}

# Modifications 05/2016 Matthias Henze mahescho@gmail.com
# * Default Values for all parameters
# * Added logging
# * Added debug switch
# * Added dry run switch
# * Added rule name parameter
# * Change data display from attachment to in line html
#
# Modifications 05/2016 Matthias Henze mahescho@gmail.com
# * Bug fixes
# * Added debug address parameter 
# * Added recipient ingore pattern parameter
# * Added output of parameters for debugging

Param

    (
	[Parameter(Mandatory=$false)][string] $SMTPHost = "your.smtp.host",
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 1,
	[Parameter(Mandatory=$false)][string] $ReportSender = "No Reply <NoReply@your-domain.de>",
	[Parameter(Mandatory=$false)][string] $ReportSubject = "Auswertung der abgewiesenen E-Mails an Sie",
	[Parameter(Mandatory=$false)][string] $RuleName = "eingehende Mail",
	[Parameter(Mandatory=$false)][string] [string]$LogFile = "c:\path\to\your\logfile.log",
    [Parameter(Mandatory=$false)][switch] $d = $false,
	[Parameter(Mandatory=$false)][string] $DebugAddress = "",
	[Parameter(Mandatory=$false)][string] $RecipientIgnorePatter = "",
    [Parameter(Mandatory=$false)][int] $LOGLEVEL = 0,
    [Parameter(Mandatory=$false)][switch] $DryRun = $false
	)

$LOG_INFO  = 4
$LOG_WARN  = 3
$LOG_ERROR = 2
$LOG_DEBUG = 1

if ( $d )
{
    Write-Host "Debug: Console DEBUG output enabled"
    $LOGLEVEL=$LOG_DEBUG
    Write-Host "# Start Parameters"
    Write-Host "# SMTP Hosst: $($SMTPHost)"
    Write-Host "# Number of Days to report: $($NumberOfDaysToReport)"
    Write-Host "# Report sender: $($ReportSender)"
    Write-Host "# Report subject: $($ReportSubject)"
    Write-Host "# Rule name: $($RuleName)"
    Write-Host "# Log file: $($LogFile)"
    Write-Host "# Debug: $($d)"
    Write-Host "# Debug address: $($DebugAddress)"
    Write-Host "# Recipien ignore pattern: $($RecipientIgnorePatter)"
    Write-Host "# Log level: $($LOGLEVEL)"
    Write-Host "# Dry run $($DryRun)"
}

function MyLog
{
    param ([int]$level, [string]$msg)
    
    if ( $d ) # Debug-Commandline-Switch loggt immer auf die Console
    {
        Write-Host $msg
    }

    if ( $level -ge $LOGLEVEL ) # Nur loggen wenn der Level grösser gleich der Vorgabe ist
    {
        $date = get-date -format yyyy:MM:dd-HH:mm:ss

        switch( $level )
        {
            $LOG_INFO  { Write-Output "$date INFO: $msg"    | Out-File $LogFile -append }
            $LOG_WARN  { Write-Output "$date WARNING: $msg" | Out-File $LogFile -append }
            $LOG_ERROR { Write-Output "$date ERROR: $msg"   | Out-File $LogFile -append }
            $LOG_DEBUG { Write-Output "$date DEBUG: $msg"   | Out-File $LogFile -append }
        }
    }
}

	
MyLog $LOG_INFO "Script starts"
	
$dateStart = (Get-Date).AddDays(-$NumberOfDaysToReport)
$reportAddresses = $null

MyLog $LOG_INFO "Getting MessageTrackInformation"

if ( $DebugAddress -eq "" )
{
    $messageTracks = Get-NSPMessageTrack -Status PermanentlyBlocked -From $dateStart -Rule $RuleName | Get-NSPMessageTrackdetails
}
else
{
    $messageTracks = Get-NSPMessageTrack -Status PermanentlyBlocked -From $dateStart -Rule $RuleName -Between1 $DebugAddress | Get-NSPMessageTrackdetails
}

MyLog $LOG_INFO "Done"

MyLog $LOG_DEBUG "Number of Message Tracks: $($messageTracks.Count)"

MyLog $LOG_INFO "Getting Reportaddresses"

[String[]] $existingAddresses = @()

foreach ($messageTrack in $messageTracks)
	{
	    $CryptoOpInformations = $messageTrack.Details.CryptographicOperationInfos.Operations
        MyLog $LOG_DEBUG "Crypto OP Informations in Track: $($CryptoOpInformations.Count)"
		foreach ($cryptoOperation in $CryptoOpInformations)
			{
            MyLog $LOG_DEBUG "ID: $($cryptoOperation.ID)  Blocked: $($cryptoOperation.MailWasBlocked)"
			if ($cryptoOperation.Id -eq "Netatwork.NoSpamProxy.MessageTracking.AttachmentManagementValidationEntry" -and $cryptoOperation.MailWasBlocked -eq "True")
					{
					    $messageRecipients = $messageTrack.Recipients
                        MyLog $LOG_DEBUG "Message Recipients: $($messageRecipients.Count)"
						foreach ($messageRecipient in $messageRecipients)
							{
								$messageRecipientAddress = ($messageRecipient.Address).trim()
                                MyLog $LOG_DEBUG "Seeking for: |$($RecipientIgnorePatter)| in Address: |$($messageRecipientAddress)|"
                                if ($messageRecipientAddress -match $RecipientIgnorePatter)
                                {
                                    MyLog $LOG_INFO "Skipping $($messageRecipientAddress) as matching $($RecipientIgnorePatter)"
                                }
                                else
                                {
                                    $messageRecipientAddress = ($messageRecipient.Address).trim()
								    if ($existingAddresses -notcontains $messageRecipientAddress) {
									    $existingAddresses = $existingAddresses + $messageRecipientAddress
                                        MyLog $LOG_DEBUG $messageRecipientAddress
								    }
                                }
							}
					}
			}
	}

MyLog $LOG_INFO "Done"

MyLog $LOG_DEBUG "Number of found addresses: $($existingAddresses.Count)"

MyLog $LOG_INFO "Generating and sending reports for the following e-mail addresses:"

$existingAddresses | ForEach-Object {
    $target = $_
    MyLog $LOG_DEBUG "Working on: $($target)"
	$dateStart = (Get-Date).AddDays(-$NumberOfDaysToReport)
	$reportFileName = $Env:TEMP + "\reject-analysis.html"

	$htmlbody1 ="
			<head>
				<title>Abgewiesene E-Mails an Sie während der vergangen 24 Stunden</title>
				<style>
	      			table, td, th { border: 1px solid black; border-collapse: collapse; }
					#headerzeile         {background-color: #DDDDDD;}
	    		</style>
			</head>
		<body style=font-family:arial>
			<h2>Abgewiesene E-Mails an Sie</h2>
			<br>
            <h3>Zeitraum: 24 Stunden</h3>
            <br>
            <br>
			<table>
				<tr id=headerzeile>
					<td><h3>Uhrzeit</h3></td><td><h3>Absender</h3></td><td><h3>Betreff</h3></td><td><h3>Dateiname</h3></td>
				</tr>
				"
	$MTracks = Get-NSPMessageTrack -Between1 $target -Status PermanentlyBlocked -From $dateStart -Rule $RuleName | Get-NSPMessageTrackdetails
	$htmlbody2 =@()
	foreach ($validationItem in $MTracks) 
	{
		$CryptoOpInformations = $validationItem.Details.CryptographicOperationInfos.Operations
		foreach ($cryptoOperation in $CryptoOpInformations)
			{
				if ($cryptoOperation.Id -eq "Netatwork.NoSpamProxy.MessageTracking.AttachmentManagementValidationEntry" -and $cryptoOperation.MailWasBlocked -eq "True")
				{
					$cryptoActionFiles = $cryptoOperation.Actions
					foreach ($cryptoActionFile in $cryptoActionFiles)
						{
						$cryptoActionFilename = $cryptoActionFile.Filename
						$NSPStartTime = $validationItem.DeliveryStartTime
						$NSPSender = $validationItem.Sender
						$NSPSubject = $validationItem.Subject
						$htmlbody2 +=("<tr><td width=150px>" +$NSPStartTime + "</td><td>" +$NSPSender +"</td><td>" +$NSPSubject + "</td><td>" +$cryptoActionFilename + "</td></tr>")
						}
				}
			
			}
	}
	$htmlbody3="</table>
		</body>"
	$htmlout=$htmlbody1+$htmlbody2+$htmlbody3
    if ( $DryRun )
    {
        MyLog $LOG_DEBUG "DryRun - nothing sent to $($target)"
    }
    else
    {
	    $htmlout | Out-File $reportFileName
	    Send-MailMessage -SmtpServer $SmtpHost -From $ReportSender -To $target -Subject $ReportSubject -Body $htmlout -BodyAsHtml
	    Remove-Item $reportFileName

        MyLog $LOG_DEBUG "Mail sent to $($target) via  $($SmtpHost)"
    }
}

MyLog $LOG_INFO "Done"

MyLog $LOG_INFO "Script ends"


# SIG # Begin signature block
# MIIMNAYJKoZIhvcNAQcCoIIMJTCCDCECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQqfR5/FqdjuOK9lTR7fqH9Q0
# 8oygggmdMIIEmTCCA4GgAwIBAgIQcaC3NpXdsa/COyuaGO5UyzANBgkqhkiG9w0B
# AQsFADCBqTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDHRoYXd0ZSwgSW5jLjEoMCYG
# A1UECxMfQ2VydGlmaWNhdGlvbiBTZXJ2aWNlcyBEaXZpc2lvbjE4MDYGA1UECxMv
# KGMpIDIwMDYgdGhhd3RlLCBJbmMuIC0gRm9yIGF1dGhvcml6ZWQgdXNlIG9ubHkx
# HzAdBgNVBAMTFnRoYXd0ZSBQcmltYXJ5IFJvb3QgQ0EwHhcNMTMxMjEwMDAwMDAw
# WhcNMjMxMjA5MjM1OTU5WjBMMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMdGhhd3Rl
# LCBJbmMuMSYwJAYDVQQDEx10aGF3dGUgU0hBMjU2IENvZGUgU2lnbmluZyBDQTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJtVAkwXBenQZsP8KK3TwP7v
# 4Ol+1B72qhuRRv31Fu2YB1P6uocbfZ4fASerudJnyrcQJVP0476bkLjtI1xC72Ql
# WOWIIhq+9ceu9b6KsRERkxoiqXRpwXS2aIengzD5ZPGx4zg+9NbB/BL+c1cXNVeK
# 3VCNA/hmzcp2gxPI1w5xHeRjyboX+NG55IjSLCjIISANQbcL4i/CgOaIe1Nsw0Rj
# gX9oR4wrKs9b9IxJYbpphf1rAHgFJmkTMIA4TvFaVcnFUNaqOIlHQ1z+TXOlScWT
# af53lpqv84wOV7oz2Q7GQtMDd8S7Oa2R+fP3llw6ZKbtJ1fB6EDzU/K+KTT+X/kC
# AwEAAaOCARcwggETMC8GCCsGAQUFBwEBBCMwITAfBggrBgEFBQcwAYYTaHR0cDov
# L3QyLnN5bWNiLmNvbTASBgNVHRMBAf8ECDAGAQH/AgEAMDIGA1UdHwQrMCkwJ6Al
# oCOGIWh0dHA6Ly90MS5zeW1jYi5jb20vVGhhd3RlUENBLmNybDAdBgNVHSUEFjAU
# BggrBgEFBQcDAgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgEGMCkGA1UdEQQiMCCk
# HjAcMRowGAYDVQQDExFTeW1hbnRlY1BLSS0xLTU2ODAdBgNVHQ4EFgQUV4abVLi+
# pimK5PbC4hMYiYXN3LcwHwYDVR0jBBgwFoAUe1tFz6/Oy3r9MZIaarbzRutXSFAw
# DQYJKoZIhvcNAQELBQADggEBACQ79degNhPHQ/7wCYdo0ZgxbhLkPx4flntrTB6H
# novFbKOxDHtQktWBnLGPLCm37vmRBbmOQfEs9tBZLZjgueqAAUdAlbg9nQO9ebs1
# tq2cTCf2Z0UQycW8h05Ve9KHu93cMO/G1GzMmTVtHOBg081ojylZS4mWCEbJjvx1
# T8XcCcxOJ4tEzQe8rATgtTOlh5/03XMMkeoSgW/jdfAetZNsRBfVPpfJvQcsVncf
# hd1G6L/eLIGUo/flt6fBN591ylV3TV42KcqF2EVBcld1wHlb+jQQBm1kIEK3Osgf
# HUZkAl/GR77wxDooVNr2Hk+aohlDpG9J+PxeQiAohItHIG4wggT8MIID5KADAgEC
# AhAh36cYPt9rQMtVY5K+Zf5LMA0GCSqGSIb3DQEBCwUAMEwxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwx0aGF3dGUsIEluYy4xJjAkBgNVBAMTHXRoYXd0ZSBTSEEyNTYg
# Q29kZSBTaWduaW5nIENBMB4XDTE1MDkyMTAwMDAwMFoXDTE2MDkyMDIzNTk1OVow
# gZUxCzAJBgNVBAYTAkRFMRwwGgYDVQQIExNOb3JkcmhlaW4gV2VzdGZhbGVuMRIw
# EAYDVQQHFAlQYWRlcmJvcm4xKTAnBgNVBAoUIE5ldCBhdCBXb3JrIE5ldHp3ZXJr
# c3lzdGVtZSBHbWJIMSkwJwYDVQQDFCBOZXQgYXQgV29yayBOZXR6d2Vya3N5c3Rl
# bWUgR21iSDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMIsja4vgLIG
# rpdvUkdCsS8HCjLwaFXt8TIXG8NYIed1aaG+tV0cmScVlsVRUSRfdKVlaTrg7ZDa
# v17t5rFle0fI8XlaMTt86mp8ujdo+svKpHSXiWL51LiADwRETzqIQfUXkdZqgXGg
# wBrTu0zzIH6NvRm7o7o43sSw5rHTHyKPJUDNEE+gAfPsH/69xDmMuH/2r6iMe5GZ
# dRyAmEtB+sEOdhCIX45gXCEGtc3lPeUDCi4I0P6+oqwHzmgfh3IIBF/PCda4V8yP
# lk65x3+6X1eNox3hWQxNQX2cOx1Yd8yaH9ZYdY8y+RwYauaiGOhzf5XvQtfuka6P
# GR270YqN7/ECAwEAAaOCAY4wggGKMAkGA1UdEwQCMAAwHwYDVR0jBBgwFoAUV4ab
# VLi+pimK5PbC4hMYiYXN3LcwHQYDVR0OBBYEFH3SkQBtD02UoOt/MNcKFgvst2+/
# MCsGA1UdHwQkMCIwIKAeoByGGmh0dHA6Ly90bC5zeW1jYi5jb20vdGwuY3JsMA4G
# A1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzBzBgNVHSAEbDBqMGgG
# C2CGSAGG+EUBBzACMFkwJgYIKwYBBQUHAgEWGmh0dHBzOi8vd3d3LnRoYXd0ZS5j
# b20vY3BzMC8GCCsGAQUFBwICMCMMIWh0dHBzOi8vd3d3LnRoYXd0ZS5jb20vcmVw
# b3NpdG9yeTAdBgNVHQQEFjAUMA4wDAYKKwYBBAGCNwIBFgMCB4AwVwYIKwYBBQUH
# AQEESzBJMB8GCCsGAQUFBzABhhNodHRwOi8vdGwuc3ltY2QuY29tMCYGCCsGAQUF
# BzAChhpodHRwOi8vdGwuc3ltY2IuY29tL3RsLmNydDANBgkqhkiG9w0BAQsFAAOC
# AQEAjQCSIdnnJcXUpByMElfYuBh0o66Z9D0teIP7tstExgFpUEdV2i1QgftYTod9
# kflbJWL+kreYq0v3Ibi70X2+o46cbKMncZpkuPNgUN91mn5V0B3DONgrE7FYZ2Ts
# JP5PR+wOunVtIaKn3SbOqTocbDx3SLBaGly+bPnh5FqsudhRWqiMKzQHxy3Lh03c
# PYYRkGUjjZekS6s3cYFZremd8TZyZgiU6ifCI8e3wNK1GFv8M7DFYHa0ta27jofc
# DtJW6f0U+8GY99R3HP3B99Lw96Gf3RMjH4ItbpT0vImZLPoA5FyigphBdYnAiZ9N
# Pd0LwA/vo00NG6ZHXUliXjH4UjGCAgEwggH9AgEBMGAwTDELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDHRoYXd0ZSwgSW5jLjEmMCQGA1UEAxMddGhhd3RlIFNIQTI1NiBD
# b2RlIFNpZ25pbmcgQ0ECECHfpxg+32tAy1Vjkr5l/kswCQYFKw4DAhoFAKB4MBgG
# CisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcC
# AQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARYwIwYJKoZIhvcNAQkEMRYE
# FB2gT3BgtAtQJAq/wISBzFd1K0f1MA0GCSqGSIb3DQEBAQUABIIBAGGWsS/m5/ft
# UrQFuQrG70hdiZ/85D0PokCYHUZGQ6OOXOCctHXZmr54dv5EvLvazJL8TAerSPPD
# iVTnbFMU62uNntO8mUH79PTsa6Zi027gIOaXSgR7XyFTmhYVgUI594osfvG5MjpK
# jdLSN15eWH1uxGgkeadg7ihqebDHl+nFM0pZQb8mjN7kq5AILeDQ1ZQgguOLVRul
# Rz8/nQc5l7jG8w5fUtsRhFSYNBQ9AEtVpjqJAxrzqHJa2LYMR201rtG1hHEQEDCq
# 7pS5GzjP3DbRvFp3AYyOG9C+57olYFL1x5TthrA2u9T+kpzrJ33SgYfbxzLSWSik
# cnNVRI9HhOo=
# SIG # End signature block

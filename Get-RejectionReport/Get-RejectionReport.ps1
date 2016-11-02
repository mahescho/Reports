# Modifications 05/2016 Matthias Henze mahescho@gmail.com
# * Default Values for all parameters
# * Added logging
# * Added debug switch
# * Added dry run switch
# * Added rule name parameter
# * Change data display from attachment to in line html
# * Removed temporary rejected
# * Better output with % calculations

# 31.10.2016 - bug fixes

Param
    (
	[Parameter(Mandatory=$false)][string] $SMTPHost = "sbaas330.kliniken.ssb.local",
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 1,
	[Parameter(Mandatory=$false)][string] $ReportSender = "No Reply <NoReply-SSB@sozialstiftung-bamberg.de>",
	[Parameter(Mandatory=$false)][string] $ReportSubject = "Auswertung der abgewiesenen E-Mails an Sie",
	[Parameter(Mandatory=$false)][string] $RuleName = "eingehende Mail",
	[Parameter(Mandatory=$false)][string] [string]$LogFile = "C:\_SSB-Scripts\Logs\Tst-Send-Reports.log",
    [Parameter(Mandatory=$false)][switch] $d = $false,
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

# $messageTracks = Get-NSPMessageTrack -Status PermanentlyBlocked -From $dateStart -Rule $RuleName
$messageTracks = Get-NSPMessageTrack -Status PermanentlyBlocked -From $dateStart -Rule $RuleName | Get-NSPMessageTrackdetails

MyLog $LOG_INFO "Done"

MyLog $LOG_INFO "Getting Reportaddresses"

[String[]] $existingAddresses = @()

MyLog $LOG_DEBUG "Number of Message Tracks: $($messageTracks.Count)"

foreach ($messageTrack in $messageTracks)
	{
	$CryptoOpInformations = $messageTrack.Details.CryptographicOperationInfos.Operations
		foreach ($cryptoOperation in $CryptoOpInformations)
			{
			if ($cryptoOperation.Id -eq "Netatwork.NoSpamProxy.MessageTracking.AttachmentManagementValidationEntry" -and $cryptoOperation.MailWasBlocked -eq "True")
					{
					$messageRecipients = $messageTrack.Recipients
						foreach ($messageRecipient in $messageRecipients)
							{
								$messageRecipientAddress = ($messageRecipient.Address).trim()
                                if ($messageRecipientAddress -match "^rechnung-")
                                {
                                    MyLog $LOG_INFO "Skipping - rechnung-"
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

MyLog $LOG_INFO "Generating and sending reports for the following e-mail addresses:"

MyLog $LOG_DEBUG "Number of found addresses: $($existingAddresses.Count)"

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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUs9bA+shdJ5TdKD+MJfT/9YNe
# ubOgggmdMIIEmTCCA4GgAwIBAgIQcaC3NpXdsa/COyuaGO5UyzANBgkqhkiG9w0B
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
# FKzmTWqqI8TUOpylcGPwBG4ssMtZMA0GCSqGSIb3DQEBAQUABIIBALQ7SCYMW94v
# NhNmxsX7BwZIQTZsnNUN32m4dsYsLvfB/jz8JzBOeB6SUYvuqrGwlashVqJkB+fI
# XKG8sPIhXj80zE2jaWt2A2w/fGR2RP8C/ef1rbWr5nBYeuohPPMqi9oC4OgUdEVP
# jmZ7OXT8A7ZF0FmH4rVSV5mi+znKH00Z6iD5Xt3XChHQ6gt19/m+j05AfWvpnsFh
# GjlZnkcnWq0yiqcDs3lFhhUJv5nBo6RyPaC2FIRg1fyT6Ws60fzzRANXv87sfMHY
# RiEnCsSWbbCJuUbhjVP+b6BU/ajAgiAbCVP8BpFhiXt37OPB/yAz0nzMJr3jC71H
# PvLDI5V9LFI=
# SIG # End signature block


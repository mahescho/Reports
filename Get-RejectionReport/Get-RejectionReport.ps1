# Modifications 05/2016 Matthias Henze mahescho@gmail.com
# * Default Values for all parameters
# * Added logging
# * Added debug switch
# * Added dry run switch
# * Added rule name parameter
# * Change data display from attachment to in line html
# * Removed temporary rejected
# * Better output with % calculations
# * Addes List of found viruses


Param
(
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 8,
	[Parameter(Mandatory=$false)][string] $SMTPHost = "your.smtp.host",
	[Parameter(Mandatory=$false)][string] $ReportSender = "NoSpamProxy Report Sender <no-reply@your-domain.de>",
	[Parameter(Mandatory=$false)][string[]] $ReportRecipient = @("recipient1@your-domain.de","recipient2@your-domain.de"),
	[Parameter(Mandatory=$false)][string] $ReportSubject = "NoSpamProxy Auswertung",
	[Parameter(Mandatory=$false)][string] [string]$LogFile = "c:\Path\To\Logs\RejectionReport.log",
    [Parameter(Mandatory=$false)][switch] $d = $false,
    [Parameter(Mandatory=$false)][int] $LOGLEVEL = $LOG_INFO,
    [Parameter(Mandatory=$false)][switch] $DryRun = $false
)

$reportFileName = $Env:TEMP + "\reject-analysis.html"
$totalMessagesRecive = 0
$totalRejected = 0
$tempRejected = 0
$permanentRejected = 0
$rdnsTempRejected = 0
$rblRejected = 0
$cyrenSpamRejected = 0
$cyrenAVRejected = 0
$surblRejected = 0
$characterSetRejected = 0
$headerFromRejected = 0
$wordRejected = 0
$rdnsPermanentRejected = 0
$decryptPolicyRejected = 0
$onBodyRejected = 0
$onEnvelopeRejected = 0
$ContentFilterRejected = 0
$dateStart = (Get-Date).AddDays(-$NumberOfDaysToReport)
$states = @{}

$arrVirus = @()

if ( $d )
{
    Write-Host "Debug: Console output enabled"
}

function MyLog
{
    param ([int]$level, [string]$msg)
    
    if ( $d ) # Debug-Commandline-Switch loggt immer auf die Console
    {
        Write-Host $msg
    }

    if ( $level -ge $LOGLEVELL ) # Nur loggen wenn der Level grösser gleich der Vorgabe ist
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

MyLog $LOG_INFO "Getting MessageTracks from NoSpamProxy..."

$messageTracks = Get-NSPMessageTrack -From $dateStart -Status All -Directions FromExternal
foreach ($item in $messageTracks)
{
	$totalMessagesRecive++
}

$messageTracks = Get-NSPMessageTrack -From $dateStart -Status TemporarilyBlocked -Directions FromExternal

foreach ($item in $messageTracks)
{
	$totalRejected++
	$tempRejected++
	$tempvalidationentries = $item.Details.ValidationResult.ValidationEntries
	foreach ($tempvalidationentry in $tempvalidationentries)
	{
		if (($tempvalidationentry.Id -eq "reverseDnsLookup") -and ($tempvalidationentry.Decision -eq "RejectTemporarily" ))
		{
			$rdnsTempRejected++
			$onEnvelopeRejected++
		}
	}
}
$messageTracks = Get-NSPMessageTrack -From $dateStart -Status PermanentlyBlocked -Directions FromExternal |Get-NSPMessageTrackdetails

foreach ($item in $messageTracks)
{
	$totalRejected++
	$permanentRejected++
	$permanentvalidationentries = $item.Details.ValidationResult.ValidationEntries
	foreach ($permanentvalidationentry in $permanentvalidationentries)
	{
        $states[$permanentvalidationentry.Id]++

        
		if ($permanentvalidationentry.Id -eq "ContentFilter")
		{
			$ContentFilterRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "realtimeBlocklist" -and $permanentvalidationentry.Scl -gt 0)
		{
			$rblRejected++
			$onEnvelopeRejected++
		}
		if ($permanentvalidationentry.Id -eq "cyrenAction" -and $permanentvalidationentry.Decision -notcontains "Pass")
		{
			$cyrenAVRejected++
			$onBodyRejected++
            # VIRUS !
            $messageRecipients = $item.Recipients
            MyLog $LOG_DEBUG "Message Recipients: $($messageRecipients.Count)"
            $r = ""
			foreach ($messageRecipient in $messageRecipients)
			{
					$messageRecipientAddress = ($messageRecipient.Address).trim() + " "
                    $r += $messageRecipientAddress
            }
            $arrVirus += @{ date=$item.DeliveryStartTime; virus=$permanentvalidationentries.Message; rcpt=$r; from=$item.Sender; subject=$item.Subject }

		}
		if ($permanentvalidationentry.Id -eq "surblFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$surblRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "cyrenFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$cyrenSpamRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "characterSetFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$characterSetRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "ensureHeaderFromIsExternal" -and $permanentvalidationentry.Scl -gt 0)
		{
			$headerFromRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "wordFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$wordRejected++
			$onBodyRejected++
		}
		if (($permanentvalidationentry.Id -eq "reverseDnsLookup") -and ($permanentvalidationentry.Decision -eq "RejectPermanent" ))
		{
			$rdnsPermanentRejected++
			$onEnvelopeRejected++
		}
		if (($permanentvalidationentry.Id -eq "validateSignatureAndDecrypt") -and ($permanentvalidationentry.Decision -notcontains "Pass" ))
		{
			$decryptPolicyRejected++
			$onBodyRejected++
		}
	}
}

$str = $states | Out-String

MyLog $LOG_DEBUG $str

MyLog $LOG_INFO "TemporaryReject Total:" $tempRejected
MyLog $LOG_INFO "PermanentReject Total:" $permanentRejected
MyLog $LOG_INFO "TotalReject:" $totalRejected
MyLog $LOG_INFO "Sending E-Mail to " $ReportRecipient "..."

if ($NumberOfDaysToReport -gt 1)
{
    $zrt = "Tage"
}
else
{
    $zrt = "Tag"
}

$htmlout = "
		<head>
			<title>Auswertung der abgewiesenen E-Mails</title>
			<style>
      			table, td, th { border: 1px solid black; border-collapse: collapse; }
				#headerzeile         {background-color: #DDDDDD;}
    		</style>
		</head>
	<body style=font-family:arial>
		<h2>Auswertung der abgewiesenen E-Mails</h2>
        <h3>Zeitraum: " + $NumberOfDaysToReport +  " " + $zrt + "</h3>
		<table>
   			<tr id=headerzeile><td><b>Mails insgesamt:</b></td><td align=right><b>&nbsp;"+$totalMessagesRecive +"&nbsp;</b></td><td align=right>" + "&nbsp;100.00" + " %&nbsp;</td></tr>
			<tr><td colspan=3>&nbsp;</td></tr>
			<tr id=headerzeile><td><b>On Envelope Level:</b></td><td align=right><b>&nbsp;" +$onEnvelopeRejected +"&nbsp;</b></td><td align=right>&nbsp;" + [math]::Round($onEnvelopeRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr id=headerzeile><td colspan=3><b>Filter</b></tr>
			<tr><td>RDNS PermanentReject</td><td align=right>&nbsp;" + $rdnsPermanentRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($rdnsPermanentRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>RDNS TempReject</td><td align=right>&nbsp;" + $rdnsTempRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($rdnsTempRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Realtime Blocklists</td><td align=right>&nbsp;" + $rblRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($rblRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td colspan=3>&nbsp;</td></tr>
			<tr id=headerzeile><td><b>On Body Level:</b></td><td align=right><b>&nbsp;" +$onBodyRejected +"&nbsp;<b></td><td align=right>&nbsp;" + [math]::Round($onBodyRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr id=headerzeile><td colspan=3><b>Filter</b></td></tr>
			<tr><td>Cyren AntiSpam</td><td align=right>&nbsp;" + $cyrenSpamRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($cyrenSpamRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Cyren Premium AntiVirus</td><td align=right>&nbsp;" + $cyrenAVRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($cyrenAVRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Spam URI Realtime Blocklists</td><td align=right>&nbsp;" + $surblRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($surblRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Allowed Unicode Character Sets</td><td align=right>&nbsp;" + $characterSetRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($characterSetRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Prevent Owned Domains in HeaderFrom</td><td align=right>&nbsp;" + $headerFromRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($headerFromRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>Word Matching</td><td align=right>&nbsp;" + $wordRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($wordRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>DecryptPolicy Reject</td><td align=right>&nbsp;" + $decryptPolicyRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($decryptPolicyRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td>ContentFilter Reject</td><td align=right>&nbsp;" + $ContentFilterRejected +"&nbsp;</td><td align=right>&nbsp;" + [math]::Round($ContentFilterRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td colspan=3>&nbsp;</td></tr>
			<tr><td><h3>PermanentReject Total</h3></td><td align=right><h3>&nbsp;" + $permanentRejected +"&nbsp;</h3></td><td align=right>&nbsp;" + [math]::Round($permanentRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
			<tr><td><h3>Reject Total</h3></td><td align=right><h3>&nbsp;" + $totalRejected +"&nbsp;</h3></td><td align=right>&nbsp;" + [math]::Round($totalRejected*100/$totalMessagesRecive,2) + " %&nbsp;</td></tr>
		</table>
"


if ( $cyrenAVRejected -gt 0 )
{
    $htmlout += "
		<h2>Auswertung der gefundenen Viren</h2>
		<table>
   			<tr id=headerzeile><td><b>Zeitpunkt</b></td><td><b>Virus</b></td><td>Absender</td><td>Empfaenger</td><td>Betreff</td></tr>"

    foreach ( $v in $arrVirus )
    {
        $htmlout += "<tr><td>" + $v.date + "</td><td>" + $v.virus + "</td><td>" + $v.from + "</td><td>" + $v.rcpt + "</td><td>" + $v.subject + "</td></tr>"
    }


    $htmlout += "		</table>"
}

$htmlout += "	</body>"

#$htmlout | Out-File $reportFileName

if ( $DryRun )
{
    MyLog $LOG_DEBUG "DryRun - nothing sent"
}
else
{
    Send-MailMessage -SmtpServer $SmtpHost -From $ReportSender -To $ReportRecipient -Subject $ReportSubject -Body $htmlout -BodyAsHtml
}

MyLog $LOG_INFO "Doing some cleanup.."
#Remove-Item $reportFileName
MyLog $LOG_INFO "Done."

# SIG # Begin signature block
# MIIMNAYJKoZIhvcNAQcCoIIMJTCCDCECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9J08NgxAbgr5HzSnlMU0S/Ki
# cDmgggmdMIIEmTCCA4GgAwIBAgIQcaC3NpXdsa/COyuaGO5UyzANBgkqhkiG9w0B
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
# FBh/4c0YrVYw5Ds/Qpgr29beanzLMA0GCSqGSIb3DQEBAQUABIIBAInR/N3zKc/j
# kcTwHE1RHj7VPN3K6eSRREOkzxU5siDEmul4BCYisG7x+Mgup4162JvqPq4p9c/C
# yezIOMQ9dvOLnidsbCYp2cnQBQBYuVxRmGmsOwHlubjObowJxitjd3WzBAsCOILc
# xumb40jD/PKJP4n0ymt2yu/u9+Jqj/VPpZhoKsfNqdMCL2j4RzhOO27D0ZxBpH/z
# 6BEEHH/JLArGfjWRBszGH3etghDbs7OEcrPcsj888SSBuxTafuqF9j3uyJyvCujN
# ofcagKT52h1NXm2l4AarkwIsYWVSPerJBRwn5Oqw3tNQp6a+v+x04GYMH3AA0REo
# V7tmNywsrpU=
# SIG # End signature block

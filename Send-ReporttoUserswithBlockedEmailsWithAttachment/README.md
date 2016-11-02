# Send-ReporttoUserswithBlockedEmailsWithAttachment.ps1
Sends a report to every E-Mail address that contains all permanently blocked E-Mails in a specific period of time that have been blocked because of an attachment. The report contains:
 - DeliveryStartTime
 - Sender address
 - Subject
 - Name of blocked file


###Usage
`Send-ReporttoUserswithBlockedEmailsWithAttachment`

Defaults for all parameters could be set in the script.
`
	[Parameter(Mandatory=$false)][string] $SMTPHost = "sbaas330.kliniken.ssb.local",
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 1,
	[Parameter(Mandatory=$false)][string] $ReportSender = "No Reply <NoReply-SSB@sozialstiftung-bamberg.de>",
	[Parameter(Mandatory=$false)][string] $ReportSubject = "Auswertung der abgewiesenen E-Mails an Sie",
	[Parameter(Mandatory=$false)][string] $RuleName = "eingehende Mail",
	[Parameter(Mandatory=$false)][string] [string]$LogFile = "C:\_SSB-Scripts\Logs\Tst-Send-Reports.log",
    [Parameter(Mandatory=$false)][switch] $d = $false,
	[Parameter(Mandatory=$false)][string] $DebugAddress = "",
	[Parameter(Mandatory=$false)][string] $RecipientIgnorePatter = "^rechnung-",
    [Parameter(Mandatory=$false)][int] $LOGLEVEL = 0,
    [Parameter(Mandatory=$false)][switch] $DryRun = $false
`

- SMTPHost: Specifies the SMTP Host which will be used to send the email.
- NumberOfDaysToReport: Specifies the Number of days to report.
- ReportSender: Specifies the Sender of the email.
- ReportSubject: Specifies the Subject of generated the emails.
- RuleName: Name of the NoSpamProxy rule for incoming mail.
- LogFile: Absolute path to log file.
- d: Debug switch. Debugging is enabled when set.
- DebugAddress: Only look at this email address.
- RecipientIgnorePatter: Regexp Pattern for email addresses to ignore.
- LOGLEVEL: INFO = 4, WARN = 3, ERROR = 2, DEBUG = 1
- DryRun: Do not send any message.

###Task Scheduler
To run this by task scheduler the user used to run this script has to be member of the local NoSpamProxy groups.

###Supported NoSpamProxy Versions
Tested with 11.X

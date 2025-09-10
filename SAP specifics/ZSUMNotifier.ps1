# param (
#     [Parameter(Mandatory = $true)][string]$SID,
# 	[Parameter(Mandatory = $true)][string]$DRIVE
# )

Start-Transcript -Path "C:\Windows\Temp\ZSUMNotifier.log" -Append

# --- MODIFICATION SECTION ---

# $email_sender = "<sender email>"
# $email_recipient = "<recipient email>"
# $customer_name = "<customer name>"
# $use_tls = "<yes,no>"
# $smtp_tls_user = "<smtp TLS user>"
# $smtp_tls_password = "<smtp TLS user password>"
# $smtp_tls_port = "<TLS port, normally 587>"
# $smtp_server = "<smtp server>"
# $smtp_port = "<smtp port, normally 25>"

# --- END OF MODIFICATION SECTION ---

# Custom modified fields
$SID="<SID>"
$DRIVE="<SUM directory drive>"
$email_sender = "sum@lawter.com"
$email_recipient = "daniel.munoz@global.ntt", "sergio.gonzalez@global.ntt"
$customer_name = "LAWTER"
$use_tls = "no"
$smtp_server = "smtp.lawter.com"
$smtp_port = "25"


# Fixed variables
$hostname = $env:COMPUTERNAME
$email_subject_sum_died = "$customer_name - $SID - $hostname - SUM process has stopped running"
$email_subject = "$customer_name - $SID - $hostname - SUM process requires your input"

# Paths to the files
$file_to_check = "${DRIVE}:\usr\sap\${SID}\SUM\abap\tmp\upalert.log"
$file_to_send = "${DRIVE}:\usr\sap\${SID}\SUM\abap\tmp\SAPupDialog.txt"
$last_sent_file_identifier = "C:\Windows\Temp\zsumnotifier_last_sent_identifier.txt"
$status_timestamp_file = "C:\Windows\Temp\zsumnotifier_last_status_check.txt"

function Cleanup {
    Remove-Item -Path $last_sent_file_identifier,$status_timestamp_file -ErrorAction SilentlyContinue
    Write-Host "Temporary files cleaned up."
}

# Argument/config check
if ($email_recipient -eq "<recipient email>" -or $email_sender -eq "<sender email>" -or $customer_name -eq "<customer name>") {
    Write-Host "$(Get-Date): Please, edit the script and configure the required settings in MODIFICATION SECTION for email_recipient, email_sender or customer_name"
    Write-Host "$(Get-Date): Exiting..."
    exit 1
}
if ($use_tls -eq "yes") {
    if ($smtp_tls_user -eq "<smtp TLS user>" -or $smtp_tls_password -eq "<smtp TLS user password>" -or $smtp_tls_port -eq "<TLS port, normally 587>") {
        Write-Host "$(Get-Date): Please, edit the script and configure the required settings in MODIFICATION SECTION for TLS"
        Write-Host "$(Get-Date): Exiting..."
        exit 1
    }
}
if ($use_tls -eq "no") {
    if ($smtp_port -eq "<smtp port, normally 25>") {
        Write-Host "$(Get-Date): Please, edit the script and configure the required settings in MODIFICATION SECTION for SMTP without TLS"
        Write-Host "$(Get-Date): Exiting..."
        exit 1
    }
}
if ($use_tls -eq "<yes,no>") {
    Write-Host "$(Get-Date): Please, edit the script and configure the required settings in MODIFICATION SECTION for use_tls"
    Write-Host "$(Get-Date): Exiting..."
    exit 1
}


Write-Host "$(Get-Date): Script started at $(Get-Date)"
Write-Host "$(Get-Date): Monitoring file: $file_to_check"
Write-Host "$(Get-Date): Email recipient: $email_recipient"
Write-Host "$(Get-Date): Email sender: $email_sender"
Write-Host "$(Get-Date): SMTP server: $smtp_server"
Write-Host "$(Get-Date): Using TLS: $use_tls"
if ($use_tls -eq "yes") {
    Write-Host "$(Get-Date): SMTP TLS user: $smtp_tls_user"
    Write-Host "$(Get-Date): SMTP TLS port: $smtp_tls_port"
} else {
    Write-Host "$(Get-Date): SMTP port: $smtp_port"
}

function Get-FileMD5([string]$filePath) {
    if (Test-Path $filePath) {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($filePath)
        $hash = $md5.ComputeHash($stream)
        $stream.Close()
        return ([BitConverter]::ToString($hash) -replace "-","").ToLower()
    } else {
        return ""
    }
}

function Is-SAPupRunning {
    return @(Get-Process -Name "SAPup" -ErrorAction SilentlyContinue).Count -gt 0
    # return @(Get-Process -Name "PowerShell" -ErrorAction SilentlyContinue).Count -gt 0
}



# Main loop
try {
while ($true) {
    $current_time = [int][double]::Parse((Get-Date -UFormat %s))
    
    # Check and display status every hour
    # If status file exists, it means there were previous executions
    if (Test-Path $status_timestamp_file) {
        $last_status_time = Get-Content $status_timestamp_file | Select-Object -First 1 
        if (-not $last_status_time) { $last_status_time = 0 }
    } else {
        $last_status_time = 0
    }
    if (($current_time - $last_status_time) -ge 3600) {
        Write-Host "$(Get-Date): ==> Update Loop"
        if (Test-Path $last_sent_file_identifier) {
            $last_sent_time = (Get-Content $last_sent_file_identifier | Select-Object -Skip 1 -First 1)
            if ($last_sent_time) {
                $dt = [System.DateTimeOffset]::FromUnixTimeSeconds([int]$last_sent_time).ToLocalTime()
                Write-Host "$(Get-Date): Last email sent at $dt"
            }
        } else {
            Write-Host "$(Get-Date): No email has been sent yet."
        }
        if (Test-Path $file_to_check) {
            Write-Host "$(Get-Date): File $file_to_check exists."
        } else {
            Write-Host "$(Get-Date): File $file_to_check does not exist."
        }
        Set-Content $status_timestamp_file $current_time
    }

    # Check for the file and send email if necessary
    if (Test-Path $file_to_check) {
        $current_hash = Get-FileMD5 $file_to_check
        if (Test-Path $last_sent_file_identifier) {
            $last_hash = Get-Content $last_sent_file_identifier | Select-Object -First 1
        } else {
            $last_hash = ""
        }
        if ($current_hash -ne $last_hash) {
            $email_body = Get-Content $file_to_send -Raw
            Write-Host "$(Get-Date): ==> File found. Sending email to $email_recipient"

            if ($use_tls -eq "yes") {
                Send-MailMessage -To $email_recipient -From $email_sender -Subject $email_subject `
                    -Body $email_body -SmtpServer $smtp_server -Port $smtp_tls_port `
                    -Credential (New-Object System.Management.Automation.PSCredential($smtp_tls_user, (ConvertTo-SecureString $smtp_tls_password -AsPlainText -Force))) `
                    -UseSsl
            } else {
                Send-MailMessage -To $email_recipient -From $email_sender -Subject $email_subject `
                    -Body $email_body -SmtpServer $smtp_server -Port $smtp_port
            }
            Set-Content $last_sent_file_identifier "$current_hash","$current_time"
        }
    }

    # Check if any SAPup process is running
    if (-not (Is-SAPupRunning)) {
        Write-Host "$(Get-Date): SUM is not running, it has probably died or cancelled manually. Sending email to $email_recipient"
        $body = "SUM is not running, it has probably died or cancelled manually"
        if ($use_tls -eq "yes") {
            Send-MailMessage -To $email_recipient -From $email_sender -Subject $email_subject_sum_died `
                -Body $body -SmtpServer $smtp_server -Port $smtp_tls_port `
                -Credential (New-Object System.Management.Automation.PSCredential($smtp_tls_user, (ConvertTo-SecureString $smtp_tls_password -AsPlainText -Force))) `
                -UseSsl
        } else {
            Send-MailMessage -To $email_recipient -From $email_sender -Subject $email_subject_sum_died `
                -Body $body -SmtpServer $smtp_server -Port $smtp_port
        }
        Cleanup
        exit 1
    }
    Start-Sleep -Seconds 60
}
}
finally {
    Cleanup
}

Stop-Transcript
#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <SID>"
    exit 1
fi

# Assign the argument to a variable
SID=$1

## MODIFICATION SECTION
email_recipient="<recipient email>"
email_sender="<sender email>"
customer_name="<customer name>"
smtp_tls_user="<smtp TLS user>"
smtp_tls_password="<smtp TLS user password>"
use_tls="<yes,no>"
smtp_server="<smtp server>"
smtp_port="<smtp port, normally 25>"
smtp_tls_port="<TLS port, normally 587>"
## END OF MODIFICATION SECTION

# Fixed variables
hostname=$(hostname)
email_subject_sum_died="$customer_name - $SID - $hostname - SUM process has stopped running"
email_subject="$customer_name - $SID - $hostname - SUM process requires your input"

# Paths to the files
file_to_check="/usr/sap/$SID/SUM/abap/tmp/upalert.log"
file_to_send="/usr/sap/$SID/SUM/abap/tmp/SAPupDialog.txt"


if [ "$email_recipient" == "<recipient email>" ] || [ "$email_sender" == "<email_sender>" ] || [ "$customer_name" == "<customer_name>" ]; then
    echo "$(date): Please, edit the script and configure the required settings in MODIFICATION SECTION for email_recipient, email_sender or customer_name"
    echo "$(date): Exiting..."
    exit 1
fi

if [ "$use_tls" == "yes" ]; then
    if [ "$smtp_tls_user" == "<yes,no>" ] || [ "$smtp_tls_password" == "<smtp TLS user password>" ] || [ "$smtp_tls_port" == "<TLS port, normally 587>" ]; then
        echo "$(date): Please, edit the script and configure the required settings in MODIFICATION SECTION for TLS"
        echo "$(date): Exiting..."
        exit 1
    fi
fi
if [ "$use_tls" == "no" ]; then
    if [ "$smtp_port" == "<smtp port, normally 25>"  ]; then
        echo "$(date): Please, edit the script and configure the required settings in MODIFICATION SECTION for SMTP without TLS"
        echo "$(date): Exiting..."
        exit 1
    fi
fi
if [ "$use_tls" == "<yes,no>" ]; then
    echo "$(date): Please, edit the script and configure the required settings in MODIFICATION SECTION for use_tls"
    echo "$(date): Exiting..."
    exit 1
fi

# Function to clean up temporary files
cleanup() {
    rm -f "$last_sent_file" "$status_timestamp_file"
    echo "Temporary files cleaned up."
}

# Function to handle SIGINT (Ctrl+C)
handle_sigint() {
    echo -e "\n$(date): SIGINT received. Do you want to cancel the execution and clean up? (yes/no)"
    read answer
    if [ "$answer" == "yes" ]; then
        cleanup
        exit 0
    fi
    echo "$(date): Continuing execution..."
}

# Trap SIGINT (Ctrl+C)
trap handle_sigint SIGINT

# Check if any SAPup process is running
if ! pgrep -f SAPup > /dev/null; then
    echo "$(date): SUM is not running. Exiting."
    cleanup
    exit 1
fi

# File to store the last sent email identifier and timestamp
last_sent_file="/tmp/zsumnotifier_last_sent"
# File to store the timestamp of the last status check
status_timestamp_file="/tmp/zsumnotifier_last_status_check"


# Print summary on first execution
echo "$(date): Script started at $(date)"
echo "$(date): Monitoring file: $file_to_check"
echo "$(date): Email recipient: $email_recipient"
echo "$(date): Email sender: $email_sender"
echo "$(date): SMTP server: $smtp_server"
echo "$(date): Using TLS: $use_tls"
if [ "$use_tls" == "yes" ]; then
    echo "$(date): SMTP TLS user: $smtp_tls_user"
    echo "$(date): SMTP TLS port: $smtp_tls_port"
else
    echo "$(date): SMTP port: $smtp_port"
fi

while true; do
    current_time=$(date +%s)

    # Check and display status every hour
    if [ -f "$status_timestamp_file" ]; then
        last_status_time=$(cat "$status_timestamp_file")
    else
        last_status_time=0
    fi

    if (( current_time - last_status_time >= 3600 )); then
        echo "$(date): ==> Update Loop"
        if [ -f "$last_sent_file" ]; then
            last_sent_time=$(awk 'NR==2' "$last_sent_file")
            echo "$(date): Last email sent at $(date -d @$last_sent_time)"
        else
            echo "$(date): No email has been sent yet."
        fi
        if [ -f "$file_to_check" ]; then
            echo "$(date): File $file_to_check exists."
        else
            echo "$(date): File $file_to_check does not exist."
        fi
        echo "$current_time" > "$status_timestamp_file"
    fi

    # Check for the file and send email if necessary
    if [ -f "$file_to_check" ]; then

        # Create identifier with md5sum + timestamp
        md5_identifier=$(md5sum "$file_to_send" | awk '{ print $1 }')
        timestamp_identifier=$(stat -c %Y "$file_to_send")
        current_identifier="${md5_identifier}_${timestamp_identifier}"


        if [ -f "$last_sent_file" ]; then
            last_sent_identifier=$(awk 'NR==1' "$last_sent_file")
        else
            last_sent_identifier=""
        fi

        if [ "$current_identifier" != "$last_sent_identifier" ]; then
            email_body=$(cat "$file_to_send")
            echo "$(date): ==> File found. Sending email to $email_recipient"
            if [ "$use_tls" == "yes" ]; then
                echo "$email_body" | mailx -v -s "$email_subject" -r "$email_sender" \
                    -S smtp-use-starttls \
                    -S smtp="smtp://$smtp_server:$smtp_tls_port" \
                    -S smtp-auth=login \
                    -S smtp-auth-user="$smtp_tls_user" \
                    -S smtp-auth-password="$smtp_tls_password" \
                    -S ssl-verify=ignore \
                    $email_recipient
            else
                echo "$email_body" | mailx -s "$email_subject" -r "$email_sender" -S smtp="$smtp_server:$smtp_port" $email_recipient
            fi
            echo "$current_identifier" > "$last_sent_file"
            echo "$current_time" >> "$last_sent_file"
            last_sent_time=$current_time
        fi
    fi

    # Check if any SAPup process is running
    if ! pgrep -f SAPup > /dev/null; then
        echo "$(date): SUM is not running, it has probably died or cancelled manually. Sending email to $email_recipient"
            if [ "$use_tls" == "yes" ]; then
                echo "SUM is not running, it has probably died or cancelled manually" | mailx -v -s "$email_subject_sum_died" -r "$email_sender" \
                    -S smtp-use-starttls \
                    -S smtp="smtp://$smtp_server:$smtp_tls_port" \
                    -S smtp-auth=login \
                    -S smtp-auth-user="$smtp_tls_user" \
                    -S smtp-auth-password="$smtp_tls_password" \
                    -S ssl-verify=ignore \
                    $email_recipient
            else
                echo "SUM is not running, it has probably died or cancelled manually" | mailx -s "$email_subject_sum_died" -r "$email_sender" -S smtp="$smtp_server:$smtp_port" $email_recipient
            fi
        cleanup
        exit 1
    fi
    # Wait 1 minute before checking again
    sleep 60
done

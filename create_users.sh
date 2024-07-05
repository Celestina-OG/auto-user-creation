#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

USER_FILE=$1
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"

# Create the log and password files if they do not exist
mkdir -p /var/secure /var/log
touch $PASSWORD_FILE
touch $LOG_FILE
# make password file secure (read and write permissions for file owner only)
chmod 600 $PASSWORD_FILE

# function to log actions to log file
log() {
    echo "$(date) - $1" >> $LOG_FILE
}

create_user() {
    local user="$1"
    local groups="$2"
    local password

    # Check if user already exists
    if id "$user" &>/dev/null; then
        log "User $user already exists."
    else
        # Create personal group for the user
        groupadd "$user"

        # Create user with home directory and shell, primary group set to the personal group
        useradd -m -s /bin/bash -g "$user" "$user"
        if [ $? -eq 0 ]; then
            log "User $user created with primary group: $user"
        else
            log "Failed to create user $user."
            return
        fi

        # Generate a random password for the user
        password=$(openssl rand -base64 15)

        # Set user's password using chpasswd
        echo "$user:$password" | chpasswd

        # Store user and password securely in a file
        echo "$user,$password" >> $PASSWORD_FILE

        # Set permissions and ownership for user home directory
        if [ ! -d "/home/$user" ]; then
            mkdir -p "/home/$user"
            chown -R "$user:$user" "/home/$user"
            chmod 700 "/home/$user"
            log "Created home directory for $user"
        fi

        log "Password for user $user created and stored securely."
    fi

    # Create additional groups if they do not exist
    IFS=' ' read -ra group_array <<< "$groups"

    # Log the group array
    log "User $user will be added to groups: ${group_array[*]}"

    for group in "${group_array[@]}"; do
        group=$(echo "$group" | xargs)  # Trim whitespace
        if ! getent group "$group" &>/dev/null; then
            groupadd "$group"
            log "Group $group created."
        fi
        usermod -aG "$group" "$user"
        log "User $user added to group $group."
    done
    log "User $user added to groups: ${group_array[*]}"
}

# Check if user list file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <user_list_file>"
    exit 1
fi

filename="$1"

if [ ! -f "$filename" ]; then
    echo "Users list file $filename not found."
    exit 1
fi

# Read user list file and create users
while IFS=';' read -r user groups; do
    user=$(echo "$user" | xargs)
    groups=$(echo "$groups" | xargs | tr -d ' ')

    # Replace commas with spaces for usermod group format
    groups=$(echo "$groups" | tr ',' ' ')
    create_user "$user" "$groups"
done < "$filename"

echo "Done. Check /var/log/user_management.log for details."

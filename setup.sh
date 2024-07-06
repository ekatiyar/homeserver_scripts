#!/bin/bash

# Get the directory of the setup script
SCRIPTS_DIR="$PWD"
# Define the interval for running the scripts (e.g., "0 4 * * *" for every day at 4 AM)
INTERVAL="0 4 * * *"

# Array of scripts to run
SCRIPTS=(
    "series_cleanup.sh"
#    "backup.sh"
)

# Temporary file to store existing crontab entries
CRONTAB_TMP="/tmp/crontab.tmp"

# Check if there is an existing crontab
if crontab -l &> /dev/null; then
    # If crontab exists, store current crontab in a temporary file
    crontab -l > "$CRONTAB_TMP"
else
    # If crontab doesn't exist, create an empty temporary file
    touch "$CRONTAB_TMP"
fi

# Add each script to cron with the specified interval if it's not already in the crontab
for script in "${SCRIPTS[@]}"; do
    # Check if the script is already present in the crontab
    if ! grep -q "$SCRIPTS_DIR/$script" "$CRONTAB_TMP"; then
        # Append the script and interval to the crontab
        echo "$INTERVAL $SCRIPTS_DIR/$script" >> "$CRONTAB_TMP"
    fi
done

# Load the modified crontab
crontab "$CRONTAB_TMP"

# Clean up temporary file
rm "$CRONTAB_TMP"

echo "Cron setup complete."


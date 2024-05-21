#!/bin/bash

# Directories
SOURCE_DIR="/mnt/usb/config"
OUTPUT_DIR="/home/pi/backup"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)

# Backup file names
FULL_BACKUP="$OUTPUT_DIR/full_backup.7z"
INCREMENTAL_BACKUP="$OUTPUT_DIR/incremental_backup_$TIMESTAMP.7z"

# Exclusion patterns
EXCLUDES="-x!config/docker -x!config/Jellyfin/config/data/transcod*/* -x!config/qbittorent/qBittorrent/ipc-socket"

# Non-solid archive option
NON_SOLID_OPTION="-ms=off"

# Check if the full backup exists
if [ ! -f "$FULL_BACKUP" ]; then
    # Create a full backup since it doesn't exist
    7z a -mx=9 -mmt=on $EXCLUDES $NON_SOLID_OPTION "$FULL_BACKUP" "$SOURCE_DIR"
    echo "Full backup created at $FULL_BACKUP"
else
    # Create a decremental (incremental) backup
    7z u $EXCLUDES $NON_SOLID_OPTION "$FULL_BACKUP" "$SOURCE_DIR" -u- -up1q1r3x1y1z0w1!"$INCREMENTAL_BACKUP"

    # Update the full backup to the current state
    7z u $EXCLUDES $NON_SOLID_OPTION "$FULL_BACKUP" "$SOURCE_DIR" -up0q0r2x2y2z1w2

    echo "Incremental backup created at $INCREMENTAL_BACKUP"
    echo "Full backup updated."
fi



# Backup retention logic for incremental backups
max_backups=10

# Navigate to the backup directory
cd "$OUTPUT_DIR" || exit

# Count the number of incremental backup files
incremental_files_count=$(ls -1 incremental_backup_*.7z 2>/dev/null | wc -l)

# Check if the number of backups exceeded the limit
if (( incremental_files_count > max_backups )); then
    # Calculate how many files to delete
    files_to_delete=$((incremental_files_count - max_backups))

    # Delete the oldest incremental backup files
    ls -1t incremental_backup_*.7z | tail -n "$files_to_delete" | xargs rm -f

    echo "$files_to_delete old incremental backup(s) removed."
fi

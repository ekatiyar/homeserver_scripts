#!/bin/bash

# Define the path to your TV shows folder
TV_FOLDER="/mnt/usb/tv"

# Define the maximum size in MB
MAX_SIZE_MB=15


# Loop through each series folder
for series_folder in "$TV_FOLDER"/*; do
    # Check if it's a directory
    if [ -d "$series_folder" ]; then
        # Check if there are no season folders
        if ! ls -d "$series_folder"/*/ &> /dev/null; then
            # Check if the size of the series folder is less than MAX_SIZE_MB
            series_size=$(du -s "$series_folder" | awk '{print $1}')
            if [ "$series_size" -lt "$((MAX_SIZE_MB * 1024))" ]; then
                echo "Deleting $series_folder"
                rm -rf "$series_folder"
            fi
        fi
    fi
done


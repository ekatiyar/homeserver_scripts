#!/bin/bash

echo "Running kill_monitor"

# Define the configuration file path
config_file="./config/counters"

# Function to initialize or modify the configuration file variables
initialize_or_modify_config() {
    local new_failed_run_count="$1"
    local new_restart_count="$2"

    echo "failed_run_count=$new_failed_run_count" > "$config_file"
    echo "restart_count=$new_restart_count" >> "$config_file"
    sleep 1
}

# Check if the config file exists
if [ -e "$config_file" ]; then
    # Source the config file to load variables
    source "$config_file"

    # Check if 'failed_run_count' variable is equal to 2 and 'restart_count' is less than 5
    if [ "$failed_run_count" -eq 2 ] && [ "$restart_count" -lt 5 ]; then
        # Reset the config file to the initial state and increment restart count
        initialize_or_modify_config 0 $((restart_count + 1))

        # Kill all PIDs
        # exit 0
        kill -s 15 -1 && (sleep 10; kill -s 9 -1)
    elif [ "$restart_count" -eq 5 ]; then
        echo "Restart count is 5. Will not reset again."
    fi
    initialize_or_modify_config $((failed_run_count + 1)) $restart_count

    # Access restart_count variable if needed
    echo "Failed Run Count: $failed_run_count"
    echo "Restart count: $restart_count"
else
    # Initialize the config file with default values
    initialize_or_modify_config 0 0
    echo "Config file initialized with default values."
fi

exit 1
#!/bin/bash

USERNAME="$QBIT_USERNAME"
PASSWORD="$QBIT_PASSWORD"
QB_API="http://localhost:$WEBUI_PORT"
COOKIE=""
HEALTHY=false

# Function to authenticate and store the session cookie
login_qbittorrent() {
    local LOGIN_RESPONSE=$(curl -s -i --header "Referer: $QB_API" --data "username=$USERNAME&password=$PASSWORD" "$QB_API/api/v2/auth/login")
    COOKIE=$(echo "$LOGIN_RESPONSE" | awk '/set-cookie: SID=/{gsub(/.*SID=/, "", $0); sub(/;.*/, "", $0); print $0}')
}

# Function to get the tracker info for a specific torrent
get_torrent_tracker_info() {
    local TORRENT_HASH="$1"
    local TRACKER_INFO=$(curl -s --location --request GET "$QB_API/api/v2/torrents/trackers?hash=$TORRENT_HASH" \
        --header "Cookie: SID=$COOKIE")
    echo "$TRACKER_INFO"
}

# Function to check if any trackers have a status of not working and msg is "No such device"
check_tracker_status() {
    local TORRENT_LIST=$(curl -s --location --request GET "$QB_API/api/v2/torrents/info?filter=resumed" \
        --header "Cookie: SID=$COOKIE" | jq -r '.[] | .hash')

    for TORRENT_HASH in $TORRENT_LIST; do
        local TRACKER_INFO=$(get_torrent_tracker_info "$TORRENT_HASH" | jq -c '.[]')

        while IFS= read -r line; do
            status=$(echo "$line" | jq -r '.status')
            msg=$(echo "$line" | jq -r '.msg')

            if [ "$status" -ne 2 ] && [ "$msg" = "No such device" ]; then
                HEALTHY=false
                return
            elif [ "$status" -eq 2 ]; then
                HEALTHY=true
            fi
        done <<< "$TRACKER_INFO"
    done
}

# Function to logout and invalidate the session
logout_qbittorrent() {
    COOKIE=$(curl -s -i --location --request POST "$QB_API/api/v2/auth/logout" --header "Cookie: SID=$COOKIE" | grep -i '^set-cookie:' | awk '{print $2}')

    # Check if SID=; is present in set-cookie
    if [[ $COOKIE == "SID=;" ]]; then
        echo "Successfully Logged Out"
    else
        echo "Error while logging out"
    fi
}

# Example usage:
login_qbittorrent
check_tracker_status
logout_qbittorrent

# Define the configuration file path
config_file="./config/counters"

# Function to initialize or modify the configuration file variables
initialize_or_modify_config() {
    local new_failed_run_count="$1"
    local new_restart_count="$2"

    echo "failed_run_count=$new_failed_run_count" > "$config_file"
    echo "restart_count=$new_restart_count" >> "$config_file"
}

if [ "$HEALTHY" = true ]; then
    echo "qBittorrent is healthy."
    source $config_file
    initialize_or_modify_config 0 $restart_count
    exit 0  # Exit with 0 status for healthy
else
    echo "qBittorrent is unhealthy."
    exit 1  # Exit with 1 status for unhealthy
fi


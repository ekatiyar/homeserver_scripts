#!/bin/bash

USERNAME="$QBIT_USERNAME"
PASSWORD="$QBIT_PASSWORD"
QB_API="http://localhost:$WEBUI_PORT"
COOKIE=""

# Function to authenticate and store the session cookie
login_qbittorrent() {
    local LOGIN_RESPONSE=$(curl -s -i --header "Referer: $QB_API" --data "username=$USERNAME&password=$PASSWORD" "$QB_API/api/v2/auth/login")
    COOKIE=$(echo "$LOGIN_RESPONSE" | awk '/set-cookie: SID=/{gsub(/.*SID=/, "", $0); sub(/;.*/, "", $0); print $0}')
}

# Function to get the category of a torrent
get_qbittorrent_category() {
    local TORRENT_HASH="$1"

    local TORRENT_CATEGORY=$(curl -s --location --request GET "$QB_API/api/v2/torrents/info?hashes=$TORRENT_HASH" \
        --header "Cookie: SID=$COOKIE" | jq -r '.[0].category')

    echo "$TORRENT_CATEGORY"
}

post_cross_seed() {
    curl -XPOST http://192.168.0.7:2468/api/webhook?apikey=5a8cd86f1bd3d8d04a5d636c720be69afe12ffa56d31de6d --data-urlencode "infoHash=$1"
}

# Function to check seeding status with a maximum of 10 iterations
check_seeding_status() {
    local TORRENT_HASH="$1"
    local MAX_ITERATIONS=10

    for ((iteration = 0; iteration < MAX_ITERATIONS; iteration++)); do
        local TORRENT_CATEGORY=$(get_qbittorrent_category "$TORRENT_HASH")

        if [ "$TORRENT_CATEGORY" = "seeding" ]; then
            echo "Torrent is seeding. Calling cross-seed and exiting the loop."
            post_cross_seed $TORRENT_HASH
            break
        elif [ -z "$TORRENT_CATEGORY" ] || [ "$TORRENT_CATEGORY" = "null" ]; then
            echo "Unsupported: Torrent has no category"
            break
        else
            echo "Torrent is not seeding. Sleeping for 30 seconds."
            sleep 30
        fi
    done
}

# Function to logout and invalidate the session
logout_qbittorrent() {
    curl -s --location --request POST "$QB_API/api/v2/auth/logout" --header "Cookie: SID=$COOKIE"
}

# Example usage:
login_qbittorrent
check_seeding_status "${1}"
logout_qbittorrent




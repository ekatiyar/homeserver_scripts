#!/bin/bash
#
# Upload a file or a directory (recursively, preserving structure) to
# gofile.io anonymously and print a single shareable link.
#
# Usage: ./gofile_upload.sh <file-or-directory>
#
# Known limitations:
# - Empty subdirectories are dropped (gofile folders are only created for
#   files that need them).
# - Internal symlinks inside a directory tree are skipped with a warning,
#   never followed.
# - Recreating subfolders relies on gofile's createFolder endpoint working
#   with a guest token, which is not officially documented. If it fails,
#   the run aborts with a clear message instead of silently flattening.

set -euo pipefail

UPLOAD_URL="https://upload.gofile.io/uploadfile"
API_URL="https://api.gofile.io"

die() {
    echo "Error: $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
(( BASH_VERSINFO[0] >= 4 )) || die "bash >= 4 is required (associative arrays)"

target="${1:-}"
[[ -n "$target" ]] || die "usage: $0 <file-or-directory>"
[[ -e "$target" ]] || die "no such file or directory: $target"

# Strip trailing slash so relative-path stripping below is exact.
target="${target%/}"

# api_call METHOD URL [curl-args...]
# Retries a couple of times on HTTP 429, checks status=="ok", prints the
# response body and dies on any other failure.
api_call() {
    local method="$1" url="$2"
    shift 2
    local attempt body http_code

    for attempt in 1 2 3; do
        body=$(curl -sS -X "$method" -w '\n%{http_code}' "$url" "$@")
        http_code="${body##*$'\n'}"
        body="${body%$'\n'*}"

        if [[ "$http_code" == "429" ]]; then
            sleep "$(( attempt * 3 - 1 ))"
            continue
        fi

        if ! jq -e '.status == "ok"' >/dev/null 2>&1 <<<"$body"; then
            echo "gofile API call failed (HTTP $http_code): $body" >&2
            return 1
        fi

        echo "$body"
        return 0
    done

    echo "gofile API call rate-limited after retries: $url" >&2
    return 1
}

upload_file() {
    local path="$1" folder_id="${2:-}" token="${3:-}"
    local args=(-F "file=@\"$path\"")
    [[ -n "$folder_id" ]] && args+=(-F "folderId=$folder_id")
    [[ -n "$token" ]] && args+=(-F "token=$token")
    api_call POST "$UPLOAD_URL" "${args[@]}"
}

create_folder() {
    local parent_id="$1" name="$2" token="$3"
    local payload
    payload=$(jq -n --arg parentFolderId "$parent_id" --arg folderName "$name" \
        '{parentFolderId: $parentFolderId, folderName: $folderName}')
    api_call POST "$API_URL/contents/createFolder" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$payload"
}

delete_content() {
    local content_id="$1" token="$2"
    local payload
    payload=$(jq -n --arg contentsId "$content_id" '{contentsId: $contentsId}')
    api_call DELETE "$API_URL/contents" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$payload" || true
}

update_attribute() {
    local content_id="$1" token="$2" attribute="$3" value="$4"
    local payload
    payload=$(jq -n --arg attribute "$attribute" --arg attributeValue "$value" \
        '{attribute: $attribute, attributeValue: $attributeValue}')
    api_call PUT "$API_URL/contents/$content_id/update" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$payload" || true
}

if [[ -f "$target" ]]; then
    response=$(upload_file "$target") || die "upload failed"
    echo "$response" | jq -r '.data.downloadPage'
    exit 0
fi

[[ -d "$target" ]] || die "not a file or directory: $target"

# --- Directory upload: recursive, structure-preserving ---

# Collect all files up front (NUL-delimited for filename safety).
mapfile -d '' -t all_files < <(find -H "$target" -type f -print0 | LC_ALL=C sort -z)
[[ "${#all_files[@]}" -gt 0 ]] || die "no files found under $target"

# Warn about internal symlinks, which -type f silently skips.
while IFS= read -r -d '' link; do
    echo "Warning: skipping symlink (not followed): $link" >&2
done < <(find -H "$target" -mindepth 1 -type l -print0)

# Bootstrap: prefer a top-level file so no fix-up upload/delete is needed.
mapfile -d '' -t top_level_files < <(find -H "$target" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)

if [[ "${#top_level_files[@]}" -gt 0 ]]; then
    bootstrap_file="${top_level_files[0]}"
else
    bootstrap_file="${all_files[0]}"
fi

echo "Uploading $(basename "$bootstrap_file") (initializing guest folder)..." >&2
response=$(upload_file "$bootstrap_file") || die "bootstrap upload failed"
guest_token=$(jq -r '.data.guestToken' <<<"$response")
root_folder_id=$(jq -r '.data.parentFolder' <<<"$response")
root_code=$(jq -r '.data.parentFolderCode' <<<"$response")
bootstrap_file_id=$(jq -r '.data.id' <<<"$response")

declare -A folder_ids
folder_ids["."]="$root_folder_id"

bootstrap_rel="${bootstrap_file#"$target"/}"
bootstrap_reuploaded=false
if [[ "$bootstrap_rel" != "$(basename "$bootstrap_file")" ]]; then
    # Bootstrap file was nested but got placed at the root; delete it here
    # and let the main loop re-upload it into its correct subfolder.
    echo "Removing misplaced bootstrap file to re-upload it into its subfolder..." >&2
    if ! delete_content "$bootstrap_file_id" "$guest_token" >/dev/null; then
        echo "Warning: could not delete misplaced bootstrap file; a stray duplicate of $(basename "$bootstrap_file") may remain at the gofile root" >&2
    fi
    bootstrap_reuploaded=true
fi

sleep 0.2

for f in "${all_files[@]}"; do
    if [[ "$f" == "$bootstrap_file" && "$bootstrap_reuploaded" == false ]]; then
        continue
    fi

    rel="${f#"$target"/}"
    rel_dir=$(dirname "$rel")

    folder_id="${folder_ids["."]}"
    if [[ "$rel_dir" != "." ]]; then
        cum_path=""
        IFS='/' read -ra components <<<"$rel_dir"
        for component in "${components[@]}"; do
            cum_path="${cum_path:+$cum_path/}$component"
            if [[ -z "${folder_ids[$cum_path]+set}" ]]; then
                parent_path=$(dirname "$cum_path")
                parent_id="${folder_ids["$parent_path"]}"
                echo "Creating folder $cum_path..." >&2
                folder_response=$(create_folder "$parent_id" "$component" "$guest_token") || \
                    die "createFolder failed for '$cum_path'. Link so far: https://gofile.io/d/$root_code (incomplete; guest tokens may not have folder-creation rights on gofile)"
                sleep 0.2
                folder_ids["$cum_path"]=$(jq -r '.data.id' <<<"$folder_response")
            fi
        done
        folder_id="${folder_ids[$rel_dir]}"
    fi

    echo "Uploading $rel..." >&2
    upload_file "$f" "$folder_id" "$guest_token" >/dev/null || die "upload failed for '$rel'"
    sleep 0.2
done

update_attribute "$root_folder_id" "$guest_token" "name" "$(basename "$target")" >/dev/null

echo "https://gofile.io/d/$root_code"

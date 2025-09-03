#!/bin/bash

# Flickr Photo Downloader with Metadata - Version 21
# Usage: ./flickr_downloader.sh [user_id] [output_root_dir] [max_pages]
# Defaults: user_id=46658241@N06, output_root_dir=current directory, pages=all
# Uses default API key for convenience
#
# This script outputs the following structure to either the provided output dir or the current dir by default:
# flickr_[userid]_[timestamp]/
# ├── photos/           # Downloaded images
# ├── metadata/         # Individual JSON files with complete metadata
# ├── all_photos.json   # List of all photos with basic info
# └── user_info.json    # User account information
#
# Usage examples:
#
# 1. All defaults:
#    ./flickr_downloader.sh
#    # user_id=46658241@N06, output=current directory, pages=all
#
# 2. Custom user, default output and pages:
#    ./flickr_downloader.sh some_user@N00
#    # output=current directory, pages=all
#
# 3. Custom user and output directory:
#    ./flickr_downloader.sh some_user@N00 /path/to/downloads
#    # pages=all
#
# 4. All three parameters:
#    ./flickr_downloader.sh some_user@N00 /path/to/downloads 5
#    # Specific user, specific output dir, limit to 5 pages
#
# 5. Use defaults but specify pages:
#    ./flickr_downloader.sh "" "" 3
#    # Default user and current directory, but limit to 3 pages
#
# Parameter order:
# 1. Flickr username (default: 46658241@N06)
# 2. Output root directory (default: . = current directory)
# 3. Number of pages (default: empty = all pages)
#
# The output directory will be created as [output_root]/flickr_[userid]_[timestamp]

set -e

# Configuration - Default values set

API_KEY="${API_KEY:-676e1e1eecab1d1e66dfda7517fe9ba2}"
BASE_URL="https://api.flickr.com/services/rest/"

# Parse command line arguments with defaults
USER_ID="${1:-46658241@N06}"
OUTPUT_ROOT="${2:-.}"
MAX_PAGES="${3:-}"

echo "Using user ID: $USER_ID"
echo "Output root directory: $OUTPUT_ROOT"
if [ -n "$MAX_PAGES" ]; then
    echo "Will fetch maximum $MAX_PAGES pages"
else
    echo "Will fetch all pages"
fi
# Global variable to store photo count
total_photos=0

# Create output directory
OUTPUT_DIR="$OUTPUT_ROOT/flickr_${USER_ID}_$(date +%Y%m%d_%H%M%S)"

# Create output directories
mkdir -p "$OUTPUT_DIR/photos"
mkdir -p "$OUTPUT_DIR/metadata"

echo "Starting download for user: $USER_ID"
echo "Output directory: $OUTPUT_DIR"

# Function to make API calls
flickr_api_call() {
    local method="$1"
    local params="$2"
    local url="${BASE_URL}?method=${method}&api_key=${API_KEY}&format=json&nojsoncallback=1&${params}"
    echo $url
    curl -s "$url"
}

# Function to get user info
get_user_info() {
    echo "Fetching user information..."
    local user_info=$(flickr_api_call "flickr.people.getInfo" "user_id=${USER_ID}")
    echo "$user_info" > "$OUTPUT_DIR/user_info.json"
    
    local username=$(echo "$user_info" | jq -r '.person.username._content // "unknown"')
    echo "User: $username"
}

# Function to get all photos for a user
get_all_photos() {
    echo "Fetching photo list..."
    local page=1
    local per_page=500
    local total_pages=1
    local photo_count=0
    
    > "$OUTPUT_DIR/all_photos.json"
    
    while [ $page -le $total_pages ]; do
        # Check if we've hit the max pages limit
        if [ -n "$MAX_PAGES" ] && [ $page -gt $MAX_PAGES ]; then
            echo "Reached maximum pages limit ($MAX_PAGES), stopping..."
            break
        fi
        
        echo "Fetching page $page of $total_pages..."
        
        local response=$(flickr_api_call "flickr.people.getPhotos" "user_id=${USER_ID}&page=${page}&per_page=${per_page}&extras=description,license,date_upload,date_taken,owner_name,icon_server,original_format,last_update,geo,tags,machine_tags,o_dims,views,media,path_alias,url_sq,url_t,url_s,url_q,url_m,url_n,url_z,url_c,url_l,url_o")
        
        # Check for API errors
        if echo "$response" | jq -e '.stat == "fail"' > /dev/null; then
            echo "API Error: $(echo "$response" | jq -r '.message')"
            exit 1
        fi
        
        # Extract pagination info
        total_pages=$(echo "$response" | jq -r '.photos.pages')
        local current_photos=$(echo "$response" | jq -r '.photos.photo | length')
        photo_count=$((photo_count + current_photos))
        
        # Show progress with page limits
        if [ -n "$MAX_PAGES" ]; then
            local limit_pages=$MAX_PAGES
            if [ $total_pages -lt $MAX_PAGES ]; then
                limit_pages=$total_pages
            fi
            echo "Fetching page $page of $limit_pages (limited from $total_pages total pages)..."
        else
            echo "Fetching page $page of $total_pages..."
        fi
        
        # Append photos to master list - ensure each JSON object is on its own line
        echo "$response" | jq -c '.photos.photo[]' >> "$OUTPUT_DIR/all_photos.json"
        
        page=$((page + 1))
    done
    
    if [ -n "$MAX_PAGES" ]; then
        echo "Found $photo_count photos (limited to first $MAX_PAGES pages)"
    else
        echo "Found $photo_count photos (all pages)"
    fi
    
    # Set global variable instead of return
    total_photos=$photo_count
    return 0
}

# Function to get detailed metadata for a photo
get_photo_metadata() {
    local photo_id="$1"
    local photo_secret="$2"
    
    # Get photo info (includes EXIF, comments, etc.)
    local info=$(flickr_api_call "flickr.photos.getInfo" "photo_id=${photo_id}&secret=${photo_secret}")
    
    # Check for errors in photo info
    if echo "$info" | jq -e '.stat == "fail"' > /dev/null; then
        echo "  Warning: Could not get photo info: $(echo "$info" | jq -r '.message // "Unknown error"')"
        info='{"stat":"fail"}'
    fi
    
    # Get EXIF data (may fail for some photos)
    local exif=$(flickr_api_call "flickr.photos.getExif" "photo_id=${photo_id}&secret=${photo_secret}")
    if echo "$exif" | jq -e '.stat == "fail"' > /dev/null; then
        echo "  Note: No EXIF data available"
        exif='{"stat":"fail","message":"No EXIF data"}'
    fi
    
    # Get photo sizes
    local sizes=$(flickr_api_call "flickr.photos.getSizes" "photo_id=${photo_id}")
    if echo "$sizes" | jq -e '.stat == "fail"' > /dev/null; then
        echo "  Warning: Could not get photo sizes: $(echo "$sizes" | jq -r '.message // "Unknown error"')"
        sizes='{"stat":"fail"}'
    fi
    
    # Combine all metadata
    local combined_metadata=$(jq -n \
        --argjson info "$info" \
        --argjson exif "$exif" \
        --argjson sizes "$sizes" \
        '{info: $info, exif: $exif, sizes: $sizes}')
    
    echo "$combined_metadata" > "$OUTPUT_DIR/metadata/${photo_id}.json"
    return 0
}

# Function to download a photo
download_photo() {
    local photo_id="$1"
    local photo_url="$2"
    local title="$3"
    
    if [ "$photo_url" != "null" ] && [ -n "$photo_url" ]; then
        # Clean title for filename
        local clean_title=$(echo "$title" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-50)
        local extension="${photo_url##*.}"
        local filename="${photo_id}_${clean_title}.${extension}"
        
        echo "  Downloading: $filename"
        if curl -s -L "$photo_url" -o "$OUTPUT_DIR/photos/$filename"; then
            return 0
        else
            echo "  Error: Download failed for $filename"
            return 1
        fi
    else
        echo "  Note: No download URL available for photo $photo_id"
        return 0
    fi
}

# Main execution
echo "========================================="
echo "Flickr Photo Downloader Starting"
echo "========================================="

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

# Get user information
get_user_info

# Get all photos
get_all_photos

# Process each photo
echo "Processing photos and downloading metadata..."
echo "Reading from: $OUTPUT_DIR/all_photos.json"

# Check if the file exists and has content
if [ ! -f "$OUTPUT_DIR/all_photos.json" ]; then
    echo "Error: Photo list file not found!"
    exit 1
fi

photo_count=$(wc -l < "$OUTPUT_DIR/all_photos.json")
echo "Photo list file contains $photo_count lines"

if [ $photo_count -eq 0 ]; then
    echo "Error: Photo list file is empty!"
    exit 1
fi

photo_num=0

while IFS= read -r photo_json; do
    # Skip empty lines
    if [ -z "$photo_json" ]; then
        continue
    fi
    
    photo_num=$((photo_num + 1))
    
    # Parse photo data with error checking
    photo_id=$(echo "$photo_json" | jq -r '.id // empty')
    photo_secret=$(echo "$photo_json" | jq -r '.secret // empty')
    photo_title=$(echo "$photo_json" | jq -r '.title // "untitled"')
    
    if [ -z "$photo_id" ]; then
        echo "Warning: Skipping invalid photo entry at line $photo_num"
        continue
    fi
    
    # Try to get the largest available image URL
    photo_url=$(echo "$photo_json" | jq -r '.url_o // .url_l // .url_c // .url_z // .url_m // .url_n // .url_s // .url_t // .url_sq // null')
    
    echo "[$photo_num/$photo_count] Processing: $photo_title (ID: $photo_id)"
    
    # Get detailed metadata with error handling
    if ! get_photo_metadata "$photo_id" "$photo_secret"; then
        echo "Warning: Failed to get metadata for photo $photo_id"
    fi
    
    # Download the photo with error handling
    if ! download_photo "$photo_id" "$photo_url" "$photo_title"; then
        echo "Warning: Failed to download photo $photo_id"
    fi
    
    # Rate limiting - be nice to Flickr's servers
    sleep 0.5
    
    # Show progress every 100 photos
    if [ $((photo_num % 100)) -eq 0 ]; then
        echo "Progress: $photo_num/$photo_count photos processed"
    fi
    
done < "$OUTPUT_DIR/all_photos.json"

echo "========================================="
echo "Download Complete!"
echo "Photos saved to: $OUTPUT_DIR/photos/"
echo "Metadata saved to: $OUTPUT_DIR/metadata/"
echo "Total photos processed: $total_photos"
echo "========================================="

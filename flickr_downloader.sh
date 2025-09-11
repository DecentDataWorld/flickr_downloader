#!/bin/bash

# Flickr Photo Downloader with Metadata - Version 23 (Fixed)
# Now includes retry logic for HTTP 429 errors and named parameters
# Usage: ./flickr_downloader.sh [options]

set -e

# Default values
API_KEY="5ae791bbb3bc847bf6e68e6fd1956f59"
USER_ID="46658241@N06"
OUTPUT_ROOT="."
MAX_PAGES=""
FORCE_REDOWNLOAD=false
RESUME_DIR=""

BASE_URL="https://api.flickr.com/services/rest/"

# Function to show help
show_help() {
    cat << EOF
Flickr Photo Downloader with Metadata - Version 23

DESCRIPTION:
    Downloads photos and metadata from a Flickr user account with robust retry logic
    for handling rate limiting (HTTP 429 errors). Includes exponential backoff and
    comprehensive error handling.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --api-key KEY        Flickr API key (default: 5ae791bbb3bc847bf6e68e6fd1956f59)
    --user-id ID         Flickr user ID (default: 46658241@N06)  
    --output-dir DIR     Output root directory (default: current directory)
    --max-pages NUM      Maximum pages to fetch (default: all pages)
    --force-redownload   Force redownload of existing files
    --help               Show this help message

EXAMPLES:
    # Use all defaults
    $0
    
    # Download specific user's photos
    $0 --user-id some_user@N00
    
    # Custom output directory
    $0 --user-id some_user@N00 --output-dir ~/Downloads
    
    # Limit to first 5 pages with custom API key
    $0 --api-key YOUR_KEY --user-id some_user@N00 --max-pages 5
    
    # Force redownload all files
    $0 --force-redownload
    
    # All parameters
    $0 --api-key YOUR_KEY --user-id some_user@N00 --output-dir ~/flickr --max-pages 10

OUTPUT STRUCTURE:
    flickr_[userid]_[timestamp]/
    ├── photos/           # Downloaded images
    ├── metadata/         # Individual JSON files with complete metadata  
    ├── all_photos.json   # List of all photos with basic info
    └── user_info.json    # User account information

RETRY LOGIC:
    - Automatically detects HTTP 429 (Too Many Requests) errors
    - Waits 30 seconds initially, doubles wait time for each retry
    - Maximum 3 retry attempts per request
    - Continues processing even if some photos fail
    - Reports success/failure statistics at completion

REQUIREMENTS:
    - curl (for API calls and downloads)
    - jq (for JSON processing)
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --user-id)
            USER_ID="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --resume-dir)
            RESUME_DIR="$2"
            shift 2
            ;;
        --max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        --force-redownload)
            FORCE_REDOWNLOAD=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Use --help to see available options"
            exit 1
            ;;
    esac
done

echo "Configuration:"
echo "  API Key: ${API_KEY:0:10}..."
echo "  User ID: $USER_ID"
echo "  Output root directory: $OUTPUT_ROOT"
if [ -n "$RESUME_DIR" ]; then
    echo "  Resume directory: $RESUME_DIR"
fi
if [ -n "$MAX_PAGES" ]; then
    echo "  Will fetch maximum $MAX_PAGES pages"
else
    echo "  Will fetch all pages"
fi
if [ "$FORCE_REDOWNLOAD" = true ]; then
    echo "  Force redownload: enabled"
fi

# Global variable to store photo count
total_photos=0

# Create output directory
if [ -n "$RESUME_DIR" ]; then
    OUTPUT_DIR="$RESUME_DIR"
    echo "Resuming download in existing directory: $OUTPUT_DIR"
    
    # Validate the resume directory exists and has the expected structure
    if [ ! -d "$OUTPUT_DIR" ]; then
        echo "Error: Resume directory '$OUTPUT_DIR' does not exist!"
        exit 1
    fi
    
    # Create subdirectories if they don't exist
    mkdir -p "$OUTPUT_DIR/photos"
    mkdir -p "$OUTPUT_DIR/metadata"
    
    # Extract user ID from existing directory if not specified
    if [ "$USER_ID" = "46658241@N06" ]; then  # Only if using default
        extracted_user_id=$(basename "$OUTPUT_DIR" | sed 's/flickr_\([^_]*\)_.*/\1/')
        if [ -n "$extracted_user_id" ] && [ "$extracted_user_id" != "flickr" ]; then
            USER_ID="$extracted_user_id"
            echo "Extracted User ID from directory: $USER_ID"
        fi
    fi
else
    OUTPUT_DIR="$OUTPUT_ROOT/flickr_${USER_ID}_$(date +%Y%m%d_%H%M%S)"
    # Create output directories
    mkdir -p "$OUTPUT_DIR/photos"
    mkdir -p "$OUTPUT_DIR/metadata"
fi

echo "Starting download for user: $USER_ID"
echo "Output directory: $OUTPUT_DIR"

# Function to check if metadata already exists
metadata_already_exists() {
    local photo_id="$1"
    [ "$FORCE_REDOWNLOAD" != true ] && [ -f "$OUTPUT_DIR/metadata/${photo_id}.json" ]
}

# Function to check if photo already exists
photo_already_exists() {
    local photo_id="$1"
    if [ "$FORCE_REDOWNLOAD" = true ]; then
        return 1  # Always download if forcing redownload
    fi
    
    # Check for any file starting with the photo ID
    local photo_files=$(find "$OUTPUT_DIR/photos" -name "${photo_id}_*" 2>/dev/null | wc -l)
    [ "$photo_files" -gt 0 ]
}

# Function to get existing photo IDs for resume capability
get_existing_photo_ids() {
    # This function was referenced but not needed for basic functionality
    # Could be used to build a list of existing photos for more efficient resume
    echo "Checking for existing photos in $OUTPUT_DIR..."
    
    if [ -d "$OUTPUT_DIR/photos" ]; then
        local existing_count=$(find "$OUTPUT_DIR/photos" -name "*.jpg" -o -name "*.png" -o -name "*.gif" 2>/dev/null | wc -l)
        echo "Found $existing_count existing photo files"
    fi
    
    if [ -d "$OUTPUT_DIR/metadata" ]; then
        local existing_metadata=$(find "$OUTPUT_DIR/metadata" -name "*.json" 2>/dev/null | wc -l)
        echo "Found $existing_metadata existing metadata files"
    fi
}

# Function to make API calls with retry logic
flickr_api_call() {
    local method="$1"
    local params="$2"
    local url="${BASE_URL}?method=${method}&api_key=${API_KEY}&format=json&nojsoncallback=1&${params}"
    local max_retries=3
    local retry_count=0
    local wait_time=30
    
    while [ $retry_count -lt $max_retries ]; do
        local response=$(curl -s "$url")
        
        # Check if response contains HTML (indicating 429 or other HTTP error)
        if echo "$response" | grep -q "<html>"; then
            echo "  HTTP error detected (likely 429 - Too Many Requests)" >&2
            echo "  Response: $(echo "$response" | head -1)" >&2
            
            retry_count=$((retry_count + 1))
            
            if [ $retry_count -lt $max_retries ]; then
                echo "  Waiting $wait_time seconds before retry $retry_count/$max_retries..." >&2
                sleep $wait_time
                # Exponential backoff - double the wait time for next retry
                wait_time=$((wait_time * 2))
                continue
            else
                echo "  Max retries reached for $method. Skipping..." >&2
                echo '{"stat":"fail","message":"Max retries exceeded due to rate limiting"}'
                return 1
            fi
        fi
        
        # Check for valid JSON response
        if ! echo "$response" | jq . > /dev/null 2>&1; then
            echo "  Invalid JSON response received" >&2
            retry_count=$((retry_count + 1))
            
            if [ $retry_count -lt $max_retries ]; then
                echo "  Waiting $wait_time seconds before retry $retry_count/$max_retries..." >&2
                sleep $wait_time
                wait_time=$((wait_time * 2))
                continue
            else
                echo "  Max retries reached for $method. Skipping..." >&2
                echo '{"stat":"fail","message":"Invalid JSON response"}'
                return 1
            fi
        fi
        
        # Successful response - return it
        echo "$response"
        return 0
    done
}

# Function to download a photo with retry logic
download_photo_with_retry() {
    local photo_id="$1"
    local photo_url="$2"
    local title="$3"
    local max_retries=3
    local retry_count=0
    local wait_time=30
    
    if [ "$photo_url" = "null" ] || [ -z "$photo_url" ]; then
        echo "  Note: No download URL available for photo $photo_id"
        return 0
    fi
    
    # Clean title for filename
    local clean_title=$(echo "$title" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-50)
    local extension="${photo_url##*.}"
    # Handle URLs with query parameters
    extension=$(echo "$extension" | cut -d'?' -f1)
    if [ -z "$extension" ] || [ ${#extension} -gt 4 ]; then
        extension="jpg"  # Default extension
    fi
    local filename="${photo_id}_${clean_title}.${extension}"
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Downloading: $filename"
        
        # Download to temporary file first, then check status
        local temp_file="$OUTPUT_DIR/photos/${filename}.tmp"
        local http_code=$(curl -s -L -w "%{http_code}" "$photo_url" -o "$temp_file")
        
        if [ "$http_code" = "200" ]; then
            # Success - move temp file to final location
            mv "$temp_file" "$OUTPUT_DIR/photos/$filename"
            echo "  Download successful"
            return 0
        elif [ "$http_code" = "429" ]; then
            echo "  HTTP 429 - Too Many Requests"
            rm -f "$temp_file" # Remove failed download
            
            retry_count=$((retry_count + 1))
            
            if [ $retry_count -lt $max_retries ]; then
                echo "  Waiting $wait_time seconds before retry $retry_count/$max_retries..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
                continue
            else
                echo "  Max retries reached due to rate limiting. Skipping $filename..."
                return 1
            fi
        else
            # Any other HTTP error - don't retry, just fail and continue
            echo "  HTTP error $http_code for $filename - marking as failed"
            rm -f "$temp_file" # Remove failed download
            return 1
        fi
    done
    
    # If we get here, we've exhausted retries
    echo "  Max retries reached for photo download. Skipping $filename..."
    return 1
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

local response=$(flickr_api_call "flickr.people.getPhotos" "user_id=${USER_ID}&page=${page}&per_page=${per_page}&extras=description,license,date_upload,date_taken,owner_name,icon_server,original_format,last_update,geo,tags,machine_tags,o_dims,views,media,path_alias,url_s,url_n,url_w,url_m,url_z,url_c,url_l,url_h,url_k,url_3k,url_4k,url_5k,url_6k,url_o")
        
        # Check for API errors
        if echo "$response" | jq -e '.stat == "fail"' > /dev/null; then
            echo "API Error: $(echo "$response" | jq -r '.message')"
            echo "Continuing to next page..."
            page=$((page + 1))
            continue
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

# Get existing photo IDs for resume capability
get_existing_photo_ids

# Get user information (skip if resuming and file exists)
if [[ -f "$OUTPUT_DIR/user_info.json" && "$FORCE_REDOWNLOAD" != true ]]; then
    echo "User info already exists, skipping..."
    username=$(jq -r '.person.username._content // "unknown"' "$OUTPUT_DIR/user_info.json" 2>/dev/null || echo "unknown")
    echo "User: $username"
else
    get_user_info
fi

# Get all photos (skip if resuming and file exists)
if [[ -f "$OUTPUT_DIR/all_photos.json" && "$FORCE_REDOWNLOAD" != true ]]; then
    echo "Photo list already exists, reading existing file..."
    total_photos=$(wc -l < "$OUTPUT_DIR/all_photos.json" 2>/dev/null || echo 0)
    echo "Found existing photo list with $total_photos photos"
else
    get_all_photos
fi

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
successful_downloads=0
failed_downloads=0
skipped_photos=0
skipped_metadata=0

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
    
    echo "[$photo_num/$photo_count] Processing: $photo_title (ID: $photo_id)"
    
    # Check if metadata already exists
    if metadata_already_exists "$photo_id"; then
        echo "  Skipping metadata - already exists"
        skipped_metadata=$((skipped_metadata + 1))
    else
        # Get detailed metadata with error handling
        if ! get_photo_metadata "$photo_id" "$photo_secret"; then
            echo "Warning: Failed to get metadata for photo $photo_id"
        fi
    fi
    
    # Check if photo already exists
    if photo_already_exists "$photo_id"; then
        echo "  Skipping photo download - already exists"
        skipped_photos=$((skipped_photos + 1))
    else
        # Try to get the largest available image URL

   photo_url=$(echo "$photo_json" | jq -r '.url_o // .url_6k // .url_5k // .url_4k // .url_3k // .url_k // .url_h // .url_l // .url_c // .url_z // .url_m // .url_w // .url_n // .url_s // null')

        # Download the photo with retry logic
        if download_photo_with_retry "$photo_id" "$photo_url" "$photo_title"; then
            successful_downloads=$((successful_downloads + 1))
        else
            failed_downloads=$((failed_downloads + 1))
            echo "Warning: Failed to download photo $photo_id after retries"
        fi
    fi
    
    # Rate limiting - be nice to Flickr's servers
    sleep 0.5
    
    # Show progress every 100 photos
    if [ $((photo_num % 100)) -eq 0 ]; then
        echo "Progress: $photo_num/$photo_count photos processed (New: $successful_downloads, Skipped: $skipped_photos, Failed: $failed_downloads)"
    fi
    
done < "$OUTPUT_DIR/all_photos.json"

echo "========================================="
echo "Download Complete!"
echo "Photos saved to: $OUTPUT_DIR/photos/"
echo "Metadata saved to: $OUTPUT_DIR/metadata/"
echo "========================================="
echo "STATISTICS:"
echo "  Total photos processed: $total_photos"
echo "  New successful downloads: $successful_downloads"
echo "  Skipped photos (already existed): $skipped_photos"
echo "  Skipped metadata (already existed): $skipped_metadata"
echo "  Failed downloads: $failed_downloads"
echo "========================================="
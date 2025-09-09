#!/bin/bash

# Flickr 429 Error Recovery Script - Version 1.0
# Scans download directories for 429 error files and retries downloading them
# Usage: ./flickr_retry_429.sh [options]

set -e

# Default values
DOWNLOAD_DIR=""
API_KEY="5ae791bbb3bc847bf6e68e6fd1956f59"
DRY_RUN=false
VERBOSE=false

# Function to show help
show_help() {
    cat << EOF
Flickr 429 Error Recovery Script - Version 1.0

DESCRIPTION:
    Scans Flickr download directories for files that contain HTTP 429 error messages
    (117-byte HTML files) and attempts to re-download them with proper retry logic.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --download-dir DIR   Directory containing flickr download (photos/ and metadata/ subdirs)
    --api-key KEY        Flickr API key (default: 5ae791bbb3bc847bf6e68e6fd1956f59)
    --dry-run           Show what would be retried without actually downloading
    --verbose           Show detailed progress information
    --help              Show this help message

EXAMPLES:
    # Scan and retry 429 errors in download directory
    $0 --download-dir ./flickr_46658241@N06_20250909_124242
    
    # Dry run to see what would be retried
    $0 --download-dir ./flickr_downloads --dry-run
    
    # Verbose mode with custom API key
    $0 --download-dir ./downloads --api-key YOUR_KEY --verbose

WHAT IT DOES:
    1. Scans photos/ directory for 117-byte files containing 429 error HTML
    2. Extracts photo IDs from the filenames
    3. Looks up photo URLs from metadata files
    4. Re-downloads photos with exponential backoff retry logic
    5. Replaces error files with actual photo content on success

REQUIREMENTS:
    - curl (for downloads)
    - jq (for JSON processing)
    - Original metadata files must exist in metadata/ subdirectory
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --download-dir)
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Validate required parameters
if [[ -z "$DOWNLOAD_DIR" ]]; then
    echo "Error: --download-dir is required"
    echo "Use --help to see usage information"
    exit 1
fi

if [[ ! -d "$DOWNLOAD_DIR" ]]; then
    echo "Error: Download directory '$DOWNLOAD_DIR' does not exist"
    exit 1
fi

if [[ ! -d "$DOWNLOAD_DIR/photos" ]]; then
    echo "Error: Photos directory '$DOWNLOAD_DIR/photos' does not exist"
    exit 1
fi

if [[ ! -d "$DOWNLOAD_DIR/metadata" ]]; then
    echo "Error: Metadata directory '$DOWNLOAD_DIR/metadata' does not exist"
    exit 1
fi

echo "Configuration:"
echo "  Download directory: $DOWNLOAD_DIR"
echo "  API Key: ${API_KEY:0:10}..."
echo "  Dry run: $DRY_RUN"
echo "  Verbose: $VERBOSE"
echo ""

# Function to check if file contains 429 error
is_429_error_file() {
    local file="$1"
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    
    # Check if file is exactly 117 bytes
    if [[ "$file_size" -eq 117 ]]; then
        # Check if it contains the 429 error message
        if grep -q "429 Too Many Requests" "$file" 2>/dev/null; then
            return 0  # Is a 429 error file
        fi
    fi
    
    return 1  # Not a 429 error file
}

# Function to extract photo ID from filename
extract_photo_id() {
    local filename="$1"
    local basename=$(basename "$filename")
    echo "${basename%%_*}"  # Extract everything before first underscore
}

# Function to get photo URL from metadata
get_photo_url_from_metadata() {
    local photo_id="$1"
    local metadata_file="$DOWNLOAD_DIR/metadata/${photo_id}.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        echo "Error: Metadata file not found: $metadata_file" >&2
        return 1
    fi
    
    # Try to extract URL from sizes data (prefer larger sizes)
    local photo_url=$(jq -r '
        .sizes.sizes.size[]? | 
        select(.label == "Original" or .label == "Large" or .label == "Medium 640" or .label == "Medium") |
        .source
    ' "$metadata_file" 2>/dev/null | head -1)
    
    if [[ -n "$photo_url" && "$photo_url" != "null" ]]; then
        echo "$photo_url"
        return 0
    fi
    
    # Fallback: try to extract from info data
    photo_url=$(jq -r '.info.photo.urls.url[]?.content // empty' "$metadata_file" 2>/dev/null | head -1)
    
    if [[ -n "$photo_url" && "$photo_url" != "null" ]]; then
        echo "$photo_url"
        return 0
    fi
    
    return 1
}

# Function to download photo with retry logic
download_photo_with_retry() {
    local photo_url="$1"
    local output_file="$2"
    local photo_id="$3"
    local max_retries=5
    local retry_count=0
    local wait_time=30
    
    [[ "$VERBOSE" == true ]] && echo "    Attempting download from: $photo_url"
    
    while [[ $retry_count -lt $max_retries ]]; do
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [DRY RUN] Would download: $photo_url"
            return 0
        fi
        
        # Create temporary file for download
        local temp_file="${output_file}.tmp"
        
        # Download with HTTP status check
        local http_code=$(curl -s -L -w "%{http_code}" "$photo_url" -o "$temp_file")
        
        if [[ "$http_code" == "200" ]]; then
            # Verify we didn't get another 429 error
            if is_429_error_file "$temp_file"; then
                echo "    Still getting 429 error, retrying..."
                rm -f "$temp_file"
                retry_count=$((retry_count + 1))
            else
                # Success - replace original file
                mv "$temp_file" "$output_file"
                [[ "$VERBOSE" == true ]] && echo "    Successfully downloaded and replaced file"
                return 0
            fi
        elif [[ "$http_code" == "429" ]]; then
            echo "    HTTP 429 - Too Many Requests"
            rm -f "$temp_file"
            retry_count=$((retry_count + 1))
        else
            echo "    HTTP error $http_code"
            rm -f "$temp_file"
            retry_count=$((retry_count + 1))
        fi
        
        if [[ $retry_count -lt $max_retries ]]; then
            echo "    Waiting $wait_time seconds before retry $retry_count/$max_retries..."
            sleep $wait_time
            # Exponential backoff with some jitter
            wait_time=$((wait_time * 2 + RANDOM % 30))
        fi
    done
    
    echo "    Max retries reached for photo $photo_id"
    return 1
}

# Main execution
echo "========================================="
echo "Flickr 429 Error Recovery Starting"
echo "========================================="

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Scan for 429 error files
echo "Scanning for 429 error files in: $DOWNLOAD_DIR/photos/"
error_files=()

for file in "$DOWNLOAD_DIR/photos"/*; do
    if [[ -f "$file" ]] && is_429_error_file "$file"; then
        error_files+=("$file")
        [[ "$VERBOSE" == true ]] && echo "Found 429 error file: $(basename "$file")"
    fi
done

echo "Found ${#error_files[@]} files with 429 errors"

if [[ ${#error_files[@]} -eq 0 ]]; then
    echo "No 429 error files found. Nothing to retry."
    exit 0
fi

echo ""
echo "Processing 429 error files..."

successful_retries=0
failed_retries=0
file_count=0

for error_file in "${error_files[@]}"; do
    file_count=$((file_count + 1))
    photo_id=$(extract_photo_id "$error_file")
    filename=$(basename "$error_file")
    
    echo "[$file_count/${#error_files[@]}] Processing: $filename (ID: $photo_id)"
    
    # Get photo URL from metadata
    if ! photo_url=$(get_photo_url_from_metadata "$photo_id"); then
        echo "  Error: Could not find photo URL in metadata for $photo_id"
        failed_retries=$((failed_retries + 1))
        continue
    fi
    
    [[ "$VERBOSE" == true ]] && echo "  Found photo URL in metadata"
    
    # Attempt to download
    if download_photo_with_retry "$photo_url" "$error_file" "$photo_id"; then
        echo "  Successfully retried: $filename"
        successful_retries=$((successful_retries + 1))
    else
        echo "  Failed to retry: $filename"
        failed_retries=$((failed_retries + 1))
    fi
    
    # Rate limiting between files
    sleep 2
    
    echo ""
done

echo "========================================="
echo "429 Error Recovery Complete!"
echo "========================================="
echo "STATISTICS:"
echo "  Total 429 error files found: ${#error_files[@]}"
echo "  Successful retries: $successful_retries"
echo "  Failed retries: $failed_retries"
if [[ "$DRY_RUN" == true ]]; then
    echo "  (Dry run mode - no files were actually modified)"
fi
echo "========================================="
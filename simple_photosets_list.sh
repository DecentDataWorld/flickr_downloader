#!/bin/bash

# Flickr Photosets with Photo IDs Extractor (with pagination support)
# Usage: ./simple_photosets_list.sh --api-key KEY --user-id ID [--output-file FILE]

set -e

# Default values
API_KEY=""
USER_ID=""
OUTPUT_FILE="photosets_with_photos.json"

# Parse arguments
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
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --api-key KEY --user-id ID [--output-file FILE]"
            echo "Example: $0 --api-key 5ae791bbb3bc847bf6e68e6fd1956f59 --user-id 99758990@N08"
            echo "         $0 --api-key KEY --user-id ID --output-file my_photosets.json"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

OUTPUT_FILE="photosets_with_photos_$USER_ID.json"

# Validate required parameters
if [[ -z "$API_KEY" || -z "$USER_ID" ]]; then
    echo "Error: Both --api-key and --user-id are required"
    exit 1
fi

echo "Fetching photosets for user: $USER_ID"

# Initialize variables for pagination
all_photosets="[]"
current_page=1
total_pages=1

# Fetch all pages of photosets
while [[ $current_page -le $total_pages ]]; do
    echo "Fetching photosets page $current_page..."
    
    # Make the API call for photosets with pagination
    URL="https://api.flickr.com/services/rest/?method=flickr.photosets.getList&api_key=${API_KEY}&user_id=${USER_ID}&format=json&nojsoncallback=1&page=${current_page}&per_page=500"
    photosets_response=$(curl -s "$URL")
    
    # Check if the API call was successful
    if [[ $(echo "$photosets_response" | jq -r '.stat') != "ok" ]]; then
        echo "Error: API call failed"
        echo "$photosets_response" | jq -r '.message // "Unknown error"'
        exit 1
    fi
    
    # Update total pages from first response
    if [[ $current_page -eq 1 ]]; then
        total_pages=$(echo "$photosets_response" | jq -r '.photosets.pages')
        total_photosets=$(echo "$photosets_response" | jq -r '.photosets.total')
        echo "Found $total_photosets total photosets across $total_pages pages"
    fi
    
    # Get photosets from current page
    current_photosets=$(echo "$photosets_response" | jq '.photosets.photoset')
    
    # Merge with all photosets
    all_photosets=$(echo "$all_photosets" "$current_photosets" | jq -s '.[0] + .[1]')
    
    current_page=$((current_page + 1))
    
    # Rate limiting between pages
    sleep 0.5
done

echo "Total photosets collected: $(echo "$all_photosets" | jq 'length')"
echo "Now fetching photo IDs for each photoset..."

# Create the enhanced JSON structure with metadata from the last response
enhanced_json=$(echo "$photosets_response" | jq --argjson all_sets "$all_photosets" '{
    photosets: {
        page: 1,
        pages: .photosets.pages,
        perpage: ($all_sets | length),
        total: .photosets.total,
        photoset: []
    },
    stat: .stat
}')

# Process each photoset
photoset_count=0
total_photos=0

echo "$all_photosets" | jq -c '.[]' | while IFS= read -r photoset; do
    photoset_count=$((photoset_count + 1))
    
    photoset_id=$(echo "$photoset" | jq -r '.id')
    photoset_title=$(echo "$photoset" | jq -r '.title._content')
    
    echo "[$photoset_count/$(echo "$all_photosets" | jq 'length')] Processing: $photoset_title"
    
    # Get photos for this photoset
    photos_url="https://api.flickr.com/services/rest/?method=flickr.photosets.getPhotos&api_key=${API_KEY}&photoset_id=${photoset_id}&format=json&nojsoncallback=1"
    photos_response=$(curl -s "$photos_url")
    
    # Check if the API call was successful
    if [[ $(echo "$photos_response" | jq -r '.stat') != "ok" ]]; then
        echo "  Error fetching photos for photoset $photoset_id: $(echo "$photos_response" | jq -r '.message // "Unknown error"')"
        # Create empty photo_ids array for failed requests
        photo_ids_array="[]"
        photo_count=0
    else
        # Extract photo IDs
        photo_ids_array=$(echo "$photos_response" | jq '[.photoset.photo[].id]')
        photo_count=$(echo "$photo_ids_array" | jq 'length')
        
        echo "  Found $photo_count photos"
        total_photos=$((total_photos + photo_count))
    fi
    
    # Add photo_ids to the photoset and append to enhanced JSON
    enhanced_photoset=$(echo "$photoset" | jq --argjson photo_ids "$photo_ids_array" '. + {photo_ids: $photo_ids}')
    
    # Save to temporary file (since we're in a while loop subshell)
    echo "$enhanced_photoset" >> "temp_enhanced_photosets.jsonl"
    
    # Rate limiting
    sleep 0.5
done

# Rebuild the final JSON structure
if [[ -f "temp_enhanced_photosets.jsonl" ]]; then
    echo "Rebuilding final JSON structure..."
    
    # Create array from all enhanced photosets
    enhanced_photosets_array=$(cat "temp_enhanced_photosets.jsonl" | jq -s '.')
    
    # Create final JSON with correct metadata
    final_json=$(echo "$enhanced_json" | jq --argjson enhanced_sets "$enhanced_photosets_array" '
        .photosets.photoset = $enhanced_sets |
        .photosets.perpage = ($enhanced_sets | length)
    ')
    
    # Clean up temp file
    rm -f "temp_enhanced_photosets.jsonl"
    
    # Output results
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$final_json" > "$OUTPUT_FILE"
        echo "Enhanced photosets data saved to: $OUTPUT_FILE"
    else
        echo "Enhanced photosets data:"
        echo "$final_json"
    fi
    
    echo ""
    echo "Summary:"
    echo "  Total photosets: $(echo "$final_json" | jq '.photosets.photoset | length')"
    echo "  Total photos: $(echo "$final_json" | jq '[.photosets.photoset[].photo_ids | length] | add')"
    
    echo ""
    echo "Photosets with photo counts:"
    echo "$final_json" | jq -r '.photosets.photoset[] | "\(.id): \(.title._content) (\(.photo_ids | length) photos)"'
    
else
    echo "Error: No photosets were processed"
    exit 1
fi
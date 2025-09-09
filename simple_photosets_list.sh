#!/bin/bash

# Flickr Photosets with Photo IDs Extractor
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

        --help|-h)
            echo "Usage: $0 --api-key KEY --user-id ID"
            echo "Example: $0 --api-key 5ae791bbb3bc847bf6e68e6fd1956f59 --user-id 99758990@N08"
            echo "         $0 --api-key KEY --user-id ID"
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

# Make the API call for photosets
URL="https://api.flickr.com/services/rest/?method=flickr.photosets.getList&api_key=${API_KEY}&user_id=${USER_ID}&format=json&nojsoncallback=1"
photosets_response=$(curl -s "$URL")

echo "Found $(echo "$photosets_response" | jq '.photosets.photoset | length') photosets"
echo "Now fetching photo IDs for each photoset..."

# Create the enhanced JSON structure
enhanced_json=$(echo "$photosets_response" | jq '{
    photosets: {
        page: .photosets.page,
        pages: .photosets.pages,
        perpage: .photosets.perpage,
        total: .photosets.total,
        photoset: []
    },
    stat: .stat
}')

# Process each photoset
photoset_count=0
total_photos=0

echo "$photosets_response" | jq -c '.photosets.photoset[]' | while IFS= read -r photoset; do
    photoset_count=$((photoset_count + 1))
    
    photoset_id=$(echo "$photoset" | jq -r '.id')
    photoset_title=$(echo "$photoset" | jq -r '.title._content')
    
    echo "[$photoset_count/22] Processing: $photoset_title"
    
    # Get photos for this photoset
    photos_url="https://api.flickr.com/services/rest/?method=flickr.photosets.getPhotos&api_key=${API_KEY}&photoset_id=${photoset_id}&format=json&nojsoncallback=1"
    photos_response=$(curl -s "$photos_url")
    
    # Extract photo IDs
    photo_ids=$(echo "$photos_response" | jq -r '.photoset.photo[].id')
    photo_count=$(echo "$photo_ids" | wc -l)
    
    echo "  Found $photo_count photos"
    total_photos=$((total_photos + photo_count))
    
    # Create photo IDs array
    photo_ids_array=$(echo "$photos_response" | jq '[.photoset.photo[].id]')
    
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
    
    # Create final JSON
    final_json=$(echo "$photosets_response" | jq --argjson enhanced_sets "$enhanced_photosets_array" '
        .photosets.photoset = $enhanced_sets
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

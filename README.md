# Flickr Photo Downloader with Metadata
Given a Flickr userID, this bash script will download the contents and their metadata to a local directory. Built by Chip Temm with help from Claude.ai (Sonnet4)  See https://www.flickr.com/services/api/ 

# Installation
Requires: jq (for JSON processing), curl (for API calls)  
apt-get install jq  
chmod +x flickr_downloader.sh

Flickr Photo Downloader with Metadata - Version 23

#DESCRIPTION:
    Downloads photos and metadata from a Flickr user account with robust retry logic
    for handling rate limiting (HTTP 429 errors). Includes exponential backoff and
    comprehensive error handling. 

#USAGE:
    ./flickr_downloader.sh [OPTIONS]

#OPTIONS:
    --api-key KEY        Flickr API key (default: 5ae791bbb3bc847bf6e68e6fd1956f59)
    --user-id ID         Flickr user ID (default: 46658241@N06)  
    --output-dir DIR     Output root directory (default: current directory)
    --max-pages NUM      Maximum pages to fetch (default: all pages)
    --help               Show this help message

#EXAMPLES:
    Use all defaults
    ./flickr_downloader.sh
    
    Download specific user's photos
    ./flickr_downloader.sh --user-id some_user@N00
    
    Custom output directory
    ./flickr_downloader.sh --user-id some_user@N00 --output-dir ~/Downloads
    
    Limit to first 5 pages with custom API key
    ./flickr_downloader.sh --api-key YOUR_KEY --user-id some_user@N00 --max-pages 5
    
    All parameters
    ./flickr_downloader.sh --api-key YOUR_KEY --user-id some_user@N00 --output-dir ~/flickr --max-pages 10

#OUTPUT STRUCTURE:
+ flickr_\[userid\]\_\[timestamp\]/  
	├── photos/			**Downloaded images**  
	├── metadata/		**Individual JSON files with complete metadata**   
	├── all_photos.json	**List of all photos with basic info**   
	└── user_info.json	**User account information**  
	
#RETRY LOGIC:
    - Automatically detects HTTP 429 (Too Many Requests) errors
    - Waits 30 seconds initially, doubles wait time for each retry
    - Maximum 3 retry attempts per request
    - Continues processing even if some photos fail
    - Reports success/failure statistics at completion

#REQUIREMENTS:
- curl (for API calls and downloads)
- jq (for JSON processing)
- Flickr API https://www.flickr.com/services/api/

# Flickr Photo Downloader with Metadata
Given a Flickr userID, this bash script will download the contents and their metadata to a local directory. Built by Chip Temm with help from Claude.ai (Sonnet4)  

# Installation
Requires: jq (for JSON processing), curl (for API calls)  
apt-get install jq  
chmod +x flickr_downloader.sh

# Usage: ./flickr_downloader.sh [flickr_user_id] [output_root_dir] [max_pages]  
 Defaults: user_id=46658241@N06, output_root_dir=current directory, max_pages=all    
 Parameter order:
 1. Flickr username *optional* (default: 46658241@N06 *USAID public photo stream*)
 2. Output root directory *optional* (default: . = current directory)
 3. Number of pages *optional* (default: empty = all pages)  *the api returns 500 photos per page, so set this to 1 when testing*  

 Uses default API key for convenience (Flickr readonly API key)

 This script outputs the following structure to either the provided output dir or the current dir by default:
 
 flickr_[userid]_[timestamp]/  
 ├── photos/           *Downloaded images*  
 ├── metadata/         *Individual JSON files with complete metadata*   
 ├── all_photos.json   *List of all photos with basic info*   
 └── user_info.json    *User account information*  
 

 Usage examples:

 1. All defaults:
    ./flickr_downloader.sh  
    *user_id=46658241@N06, output=current directory, pages=all*

 2. Custom user, default output and pages:
    ./flickr_downloader.sh some_user@N00  
    *output=current directory, pages=all*

 3. Custom user and output directory:
    ./flickr_downloader.sh some_user@N00 /path/to/downloads  
    *pages=all*

 4. All three parameters:
    ./flickr_downloader.sh some_user@N00 /path/to/downloads 5  
    *Specific user, specific output dir, limit to 5 pages*

 5. Use defaults but specify pages:
    ./flickr_downloader.sh "" "" 3  
    *Default user and current directory, but limit to 3 pages*

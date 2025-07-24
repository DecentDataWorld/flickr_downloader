* flickr_downloader
Given a Flickr userID, this bash script will download the contents and their metadata to a local directory. Built by Chip Temm with help from Claude.ai (Sonnet4)

 Flickr Photo Downloader with Metadata - Version 21
 Usage: ./flickr_downloader.sh [user_id] [output_root_dir] [max_pages]
 Defaults: user_id=46658241@N06, output_root_dir=current directory, max_pages=all
 Uses default API key for convenience

 This script outputs the following structure to either the provided output dir or the current dir by default:
 flickr_[userid]_[timestamp]/
 ├── photos/           * Downloaded images*
 ├── metadata/         * Individual JSON files with complete metadata*
 ├── all_photos.json   * List of all photos with basic info*
 └── user_info.json    * User account information*

 Usage examples:

 1. All defaults:
    ./flickr_downloader.sh
    * user_id=46658241@N06, output=current directory, pages=all*

 2. Custom user, default output and pages:
    ./flickr_downloader.sh some_user@N00
    * output=current directory, pages=all*

 3. Custom user and output directory:
    ./flickr_downloader.sh some_user@N00 /path/to/downloads
    * pages=all*

 4. All three parameters:
    ./flickr_downloader.sh some_user@N00 /path/to/downloads 5
    * Specific user, specific output dir, limit to 5 pages*

 5. Use defaults but specify pages:
    ./flickr_downloader.sh "" "" 3
    * Default user and current directory, but limit to 3 pages*

 Parameter order:
 1. Flickr username (default: 46658241@N06 *free, readonly API key*)
 2. Output root directory (default: . = current directory)
 3. Number of pages (default: empty = all pages)

 The output directory will be created as [output_root]/flickr_[userid]_[timestamp]


#call this script from inside a directroy containing failed 429 phot downloads to delte them all. Then rerun the flickr_downloader to retry them with the --rerun flag
find . -maxdepth 1 -type f -exec sh -c 'size=$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0); [ "$size" -eq 117 ] && grep -q "429 Too Many Requests" "$1" 2>/dev/null && echo "Deleting $1" && rm "$1"' _ {} \;


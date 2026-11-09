#!/bin/bash

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "This script will download country and location information required by the extract_ena_sample_metadata.py script."
   echo
   echo "Syntax download_country_and_location_info.sh [-o]"
   echo "options:"
   echo "-o / --output_dir     Directory to store the downloaded information"
   echo
}

############################################################
# Main                                                     #
############################################################

SHORT=o:,h
LONG=output_dir:,help
OPTS=$(getopt --options $SHORT --longoptions $LONG -- "$@")

VALID_ARGUMENTS=$# # Returns the count of arguments that are in short or long options

if [ "$VALID_ARGUMENTS" -eq 0 ]; then
  Help
fi

eval set -- "$OPTS"

while :
do
    case $1 in
        -o | --output_dir ) 
        output_dir="$2" 
        shift 2 
        ;;
        -h | --help ) 
        Help
        exit 2
        ;;
        --)
        shift;
        break
        ;;
        *)
        echo "Unexpected option: $1"
        Help
        exit 2
        ;;
  esac
done

set -e
mkdir -p "$output_dir"
cd "$output_dir"

echo "Downloading Natural Earth admin-0 country boundaries (land)..."
curl -L -o ne_admin0.zip "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip"
unzip -o -q ne_admin0.zip -d ne_admin0

echo "Downloading Natural Earth admin-1 state/province boundaries..."
curl -L -o ne_admin1.zip "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_1_states_provinces.zip"
unzip -o -q ne_admin1.zip -d ne_admin1

echo "Downloading GeoNames global cities/towns gazetteer (population >= 500)..."
curl -L -o cities500.zip "https://download.geonames.org/export/dump/cities500.zip"
unzip -o -q cities500.zip

echo "Downloading Marine Regions World EEZ boundaries (via Marine Regions WFS service)..."
EEZ_URL="https://geo.vliz.be/geoserver/MarineRegions/wfs?service=WFS&version=1.0.0&request=GetFeature&typeNames=eez&outputFormat=SHAPE-ZIP"
curl -fL --retry 3 --max-time 1800 -o world_eez.zip "$EEZ_URL" || true
if unzip -tq world_eez.zip > /dev/null 2>&1; then
    unzip -o -q world_eez.zip -d world_eez
    echo "World EEZ downloaded successfully."
else
    echo "WARNING: World EEZ auto-download failed or returned a non-zip file."
    echo "Manual fallback (the site requires a short form):"
    echo "1. Go to https://www.marineregions.org/downloads.php"
    echo "2. Download 'World EEZ' (latest version), Shapefile format"
    echo "3. Unzip it into ${output_dir}/world_eez/"
    rm -f world_eez.zip
fi

echo ""
echo "Done. Reference data is in ${output_dir}"
echo "ne_admin0/  - country boundaries"
echo "ne_admin1/  - state/province boundaries"
echo "cities500.txt (or similar) - GeoNames cities/towns"
echo "world_eez/  - marine exclusive economic zones"
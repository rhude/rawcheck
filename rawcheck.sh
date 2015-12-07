#!/bin/sh

#  rawcheck.sh
#  
#
#  Created by Jeff Rhude on 2015-12-03.
#

# Setup
logfile="/var/log/rawcheck.log"

if [ -z "$1" ]; then
    echo "rawcheck"
    echo "Usage: rawcheck.sh filename"
    exit -1
fi

if [ ! -f "$logfile" ]; then
    touch "$logfile"
fi

if [ ! -w "$logfile" ]; then
    echo "Unable to write to log: $logfile"
    exit -1
fi

# Checking for necessary tools:
# dcraw
dcraw="dcraw"
# exiftool
exiftool="exiftool"
#xmllint
xmllint="xmllint"
#md5sum
md5sum="md5sum"
#ufraw-batch
ufrawbatch="ufraw-batch"


datestamp=$(date +"%m-%d-%y %T")


if [ ! -f $1 ]; then
    echo "Unable to find: $1"
    exit -1
fi

echo "rawcheck"
echo "Checking file: $1"

filewithpath=$1
filepath=$(dirname "${1}")
filename=$(basename "${1}")
filebasename="${filename%.*}"
realpath=$(realpath -q $1)


# Function definitions.

hash_create () {
    # Function to create an MD5 hash.
    echo "Processing hash for: $filewithpath"
    raw_hash=$(md5sum $filewithpath | cut -f1 -d' ')
    echo "Writing hash to: $filepath/$filebasename.md5"
    echo $raw_hash > $filepath/$filebasename.md5
    echo "Wrote: $raw_hash to $filepath/$filebasename.md5"
}

hash_check () {
    # Check a hash, returns 0 if they are the same, 1 if they are different.
    raw_hash_from_file=$(cat $filepath/$filebasename.md5 | cut -f1 -d' ')
    echo "Processing hash for: $filewithpath"
    raw_hash=$(md5sum $filewithpath | cut -f1 -d' ')
    if [ "$raw_hash" == "$raw_hash_from_file" ]; then
        return 0
    else
        return 1
    fi
}

function ufraw_extract {
    # Use ufraw-batch to extract the embedded preview image and verify. Return 0 if success, 1 if failure.
    echo "Extracting preview file..."
    $ufrawbatch --embedded-image --out-path="/tmp" --overwrite --output="/tmp/rawcheck_ufraw_jpeg.tmp" --silent $filewithpath
    ufraw_error_code=$?
    echo "ufraw-batch returned $ufraw_error_code"
    rm -f "/tmp/rawcheck_ufraw_jpeg.tmp"

    if [ $ufraw_error_code -ne 0 ] ; then
        # There was an error with the preview file, this could be corruption.
        echo "Error found while dumping preview file."
        return 1
    else
        # The export completed successfully, return 0.
        echo "Success."
        return 0
    fi
}

logit () {
    # Logging function to keep a log file.
    echo "[$datestamp] $1" >> $logfile
}


exiftool_ident () {
    # Use Exiftool and verify there were no errors during processing. Returns xml if clean, 1 if there is an error.
    echo "Dumping metadata with ExifTool."
    exiftool_output=$($exiftool -X $filewithpath)
    exiftool_exit=$?
    echo "EXIFTool Exited with: $exiftool_exit"
    #Check EXIFTool XML for an error message, contained in the ExifTool::Error tag.
    exiftool_xml_errorcount=$(echo $exiftool_output | $xmllint --xpath "count(//*[local-name()='Error'])" -)
    echo "Counted $exiftool_xml_errorcount error(s)."
    if [ "$exiftool_exit" -eq "0" ] && [ "$exiftool_xml_errorcount" -eq "0" ]; then
        echo "Wrote XML: $filepath/$filebasename.xml"
        echo "XML:"
        echo $exiftool_output | $xmllint --format - >$filepath/$filebasename.xml
    else
        #An error was reported by EXIFTool. Possible file issue.
        exiftool_xml_error_text=$(echo $exiftool_output | $xmllint --xpath "//*[local-name()='Error']/text()" -)
        if [ -z "$exiftool_xml_error_text" ]; then
            exiftool_xml_error_text="Additional error information was not provided."
        fi
        echo "EXIFTool reported an error with: $realpath"
        echo "Error code: $exiftool_exit"
        echo "Error information: $exiftool_xml_error_text"
        return 1
    fi

}

dcraw_tiff () {
    # Process the raw file as a tiff, success returns 0, fail returns 1. Document mode only is black and white for speed.
    echo "Processing file as TIFF..."
    dcraw_output=$($dcraw -T -d -T -c $filewithpath >/tmp/dcraw_output.tiff)
    dcraw_error_code=$?
    rm -f /tmp/dcraw_output.tiff
    if [ "$dcraw_error_code" -ne "0" ]; then
        echo "DCRaw: Error decoding file."
        return 1
    else
        echo "DCRaw: File decode success..."
        return 0
    fi
}



#Dump JPEG preview contained in RAW.


#Check for hash, if its found verify the file hasn't changed.

if [ -f $filepath/$filebasename.md5 ]; then
    #Found md5 file, checking hash.
    hash_check
    hash_check_error=$?
    if [ "$hash_check_error" -eq "0" ]; then
        #Hashes match, thats good, we can exit.
        echo "Verified hashes match, skipping..."
        exit 0
    else
        #Looks like the file has changed
        echo "File does not match hash, maybe file has changed."
        logit "$realpath - FAIL - TEST:md5_checksum"
    fi
else
    #Hash file not found, need to verify file and create one, first we need to check the file for corruption.

    #ExifTool check. Dump metadata.
    echo "Verifying file: $filewithpath"
    exiftool_ident
    exiftool_ident_output=$?
    echo "exiftool returned $exiftool_ident_output"
    if [ "$exiftool_ident_output" == "1" ]; then
        #Caught an error with the exif data, likely file corruption.
        echo "Error processing exif data."
        logit "$realpath - FAIL - TEST:exiftool_exifdata"
        exit 1

    fi

    # Check if we can dump the jpeg preview from the raw file.

    ufraw_extract
    ufraw_extract_error=$?
    echo "Ufraw returned: $ufraw_extract_error"

    if [ "$ufraw_extract_error" -ne "0" ]; then
        echo "Test failed: Extract Preview for $filename."
        logit "$realpath - FAIL - TEST:extract_preview"
        exit 1
    else
        echo "Extract preview success."
    fi

    # Test if we can create a tiff file from the raw image data.
    dcraw_tiff
    dcraw_tiff_error=$?
    echo "dcraw_tiff returned $dcraw_tiff_error"
    if [ "$dcraw_tiff_error" -ne "0" ]; then
        #There was an error processing the raw file, log and exit.
        logit "$realpath - FAIL - TEST:dcraw_tiff"
        exit 1
    fi

    #Finally create the md5 hash since we are fairly certian this file is ok.
    hash_create

fi




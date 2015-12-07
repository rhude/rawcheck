# rawcheck
Bash shell script to verify raw image file integrity.
Jeff Rhude

A simple bash script to perform the following tests on a raw image file:
-Check for an existing md5 hash, if found verify nothing has changed.
-Check for EXIF data using exiftool. If so, save the output as XML.
-Check for a preview image and dump it to disk, jpeg previews are contained in some raw image files.
-Check if we can convert the actual raw image data to a tiff file.

If these tests check out, write a new md5 checksum to disk.

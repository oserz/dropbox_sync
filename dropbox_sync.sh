#!/bin/sh

#Default values, edit these
BASE_DIR="/tmp/storage/mmcblk0/SiteBase"
SYN_DIR="/dropmd/"
OAUTH_ACCESS_TOKEN=""
SITE_BASE="/hugoSite/"
THEME_NAME="hugo-oser"

############
TMP_DIR="$BASE_DIR/tmp"
CURL_PARAMETERS="-L --progress-bar"
LINE_CR="\n"
RESPONSE_FILE="$TMP_DIR/du_resp_a"
TEMP_FILE="$TMP_DIR/du_tmp_a"
CURL_BIN="/usr/bin/curl"
HUGO_BIN="hugo-mips"
HUGO_POST="post"
HUGO_CONTENT_POST="$BASE_DIR$SITE_BASE""content/$HUGO_POST"

#Don't edit these
API_DOWNLOAD_URL="https://content.dropboxapi.com/2/files/download"
API_LIST_FOLDER_URL="https://api.dropboxapi.com/2/files/list_folder"
API_LIST_FOLDER_CONTINUE_URL="https://api.dropboxapi.com/2/files/list_folder/continue"

db_list_outfile() {

    local DIR_DST="$1"
    local HAS_MORE="false"
    local CURSOR=""

    if [[ -n "$2" ]]; then
        CURSOR="$2"
        HAS_MORE="true"
    fi

    OUT_FILE="$TMP_DIR/du_tmp_out_a"

    while (true); do

        if [[ $HAS_MORE == "true" ]]; then
            $CURL_BIN -k -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"cursor\": \"$CURSOR\"}" "$API_LIST_FOLDER_CONTINUE_URL"
        else
            $CURL_BIN -k -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$DIR_DST\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}" "$API_LIST_FOLDER_URL"
        fi

        #check_http_response

        HAS_MORE=$(sed -n 's/.*"has_more": *\([a-z]*\).*/\1/p' "$RESPONSE_FILE")
        CURSOR=$(sed -n 's/.*"cursor": *"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

            #Extracting directory content [...]
            #and replacing "}, {" with "}\n{"
            #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
            local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
    {/g')

            #Converting escaped quotes to unicode format
            echo "$DIR_CONTENT" | sed 's/\\"/\\u0022/' > "$TEMP_FILE"

            #Extracting files and subfolders
            while read -r line; do

                local FILE=$(echo "$line" | sed -n 's/.*"path_display": *"\([^"]*\)".*/\1/p')
                local TYPE=$(echo "$line" | sed -n 's/.*".tag": *"\([^"]*\).*/\1/p')
                local SIZE=$(echo "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p')

                echo -e "$FILE:$TYPE;$SIZE" >> "$OUT_FILE"

            done < "$TEMP_FILE"

            if [[ $HAS_MORE == "false" ]]; then
                break
            fi

        else
            return
        fi

    done

    echo $OUT_FILE
}

db_download_drop_dir() {
    local SRC=$SYN_DIR
    local basedir=$(basename "$SRC")
    local DEST_DIR=$BASE_DIR"/"$basedir

	cd $BASE_DIR
	
    if [[ ! -d "$DEST_DIR" ]]; then
       echo -e " > Creating local directory \"$DEST_DIR\"... "
       mkdir -p "$DEST_DIR"

       #Check
       if [[ $? == 0 ]]; then
         echo -e "DONE\n"
       else
         echo -e "FAILED\n"
         return
       fi
    fi

    if [[ ! -d "$TMP_DIR" ]]; then
       echo -e " > Creating local directory \"$TMP_DIR\"... "
       mkdir -p "$TMP_DIR"

       #Check
       if [[ $? == 0 ]]; then
         echo -e "DONE\n"
       else
         echo -e "FAILED\n"
         return
       fi
    fi

    if [[ $SRC == "/" ]]; then
       SRC_REQ=""
    else
       SRC_REQ="$SRC"
    fi

    echo -e "dest directory is "$DEST_DIR"\n"

    OUT_FILE=$(db_list_outfile "$SRC_REQ")
    
    #For each entry...
    while read -r line; do

       local FILE=${line%:*}
       local META=${line##*:}
       local TYPE=${META%;*}
       local SIZE=${META#*;}

       #Removing unneeded /
       FILE=${FILE##*/}

       if [[ $TYPE == "file" ]]; then
         db_download_file "$SRC$FILE" "$basedir/$FILE"
       fi

    done < $OUT_FILE
    rm -fr $OUT_FILE
    remove_temp_files

}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
db_download_file() {
    local FILE_SRC=$1
    local FILE_DST=$2

    #Checking if the file already exists
    if [[ -e $FILE_DST ]]; then
        echo -e " > Skipping already existing file \"$FILE_DST\"\n"
        return
    fi

    echo -e " > Downloading \"$FILE_SRC\" to \"$FILE_DST\"... $LINE_CR"
    $CURL_BIN -k $CURL_PARAMETERS -X POST --globoff -D "$RESPONSE_FILE" -o "$FILE_DST" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"path\": \"$FILE_SRC\"}" "$API_DOWNLOAD_URL"
    #check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        echo -e "DONE\n"
    else
        echo -e "FAILED\n"
        rm -fr "$FILE_DST"
        return
    fi
}

remove_temp_files() {
    rm -fr "$RESPONSE_FILE"
    rm -fr "$TEMP_FILE"
}

sync_download_file() {
	local basedir=$(basename "$SYN_DIR")
	local SRC_MD_DIR=$BASE_DIR"/"$basedir
	FILES_SRC=$(ls $SRC_MD_DIR/*.md)
	for FILE in $FILES_SRC
	do
		FILE_NAME=$(basename $FILE)
		if [[ -e $HUGO_CONTENT_POST/$FILE_NAME ]]; then
		  echo -e "> Skipping existing content file \"$FILE_NAME\"\n"
		else
		  echo -e "Merge content file\"$FILE_NAME\"\n"
		  FILE_CONTENT=$(cat $FILE)
		  echo "$FILE_CONTENT" | while read LINE
			do
			  head_len=$(( $head_len+${#LINE} ))
			  indx=$(expr index "$LINE" "\`")
			  if [[ $indx != 0 ]]; then
				 local line_cut=$(echo ${LINE%"\`"*})
				 local splite_str=$(echo ${line_cut##*"\`"} | cut -d " " -f1-)
				 echo -e "${FILE_CONTENT:$head_len}"
				 echo "$splite_str"
				 hugo_sync_file "$splite_str" "${FILE_CONTENT:$head_len}" "$FILE_NAME"
				 break
			 fi
			done
			
		fi
	done
}

hugo_sync_file() {
	local FILE_HEAD="$1"
	local FILE_CONTENT="$2"
	local FILE_NAME="$3"
	cd "$BASE_DIR$SITE_BASE" 
	./$HUGO_BIN new $HUGO_POST/$FILE_NAME
	while read LINE
	do
	    if [[ "$LINE" != "" && "${LINE:0:1}" != "+" && "${LINE:0:5}" != "title" && "${LINE:0:1}" != " " ]]; then
		   NEWLINE=$(echo "$LINE" | sed s/[[:space:]]//g)
		   FILE_HEAD="$FILE_HEAD"" $NEWLINE"
		fi
	done < $HUGO_CONTENT_POST"/"$FILE_NAME
	
	##delete old & write new file	
	rm $HUGO_CONTENT_POST"/"$FILE_NAME
	touch $HUGO_CONTENT_POST"/"$FILE_NAME
	echo "+++" >> $HUGO_CONTENT_POST"/"$FILE_NAME
	
	for TT in $FILE_HEAD
	do
	    echo "$TT" >> $HUGO_CONTENT_POST"/"$FILE_NAME
	done
	echo "+++" >> $HUGO_CONTENT_POST"/"$FILE_NAME
	
	echo -e "$FILE_CONTENT" >> $HUGO_CONTENT_POST"/"$FILE_NAME
	
	#publish
	./$HUGO_BIN --theme=$THEME_NAME
}

db_download_drop_dir
sync_download_file

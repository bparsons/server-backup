#!/bin/bash

#
# Unencrypt backup file
#
# $1 = file
# $2 = passw


###
## 
## Functions
##

usage() {

    echo -e "\nUsage: $0 -p <password> -f <filename>\n"

}

# Process cmd line args
while getopts ":p:f:" optname
do
    case ${optname} in
        f|F) FILENAME=${OPTARG}
             ;;
        p|P) PASSPHRASE=${OPTARG}
             ;;
        *  ) echo "Error: No such option ${optname}."
             usage
             ;;
    esac
done

# Make sure we got a passphrase and that it is not empty
[[ $PASSPHRASE && ${PASSPHRASE-x} ]] || { echo "No password given"; usage; exit 1; }
# Check filename 
[[ $FILENAME && ${FILENAME-x} ]] || { echo "No filename given"; usage; exit 1; }
[ -e "$FILENAME" ] || { echo "Cant find file $FILENAME"; usage; exit 1; }

# set destination file
DESTFILE=`echo "${FILENAME}" | awk -F'.gpg' '{print$1}'`

echo -e "Decrypting ${FILENAME} with password \"${PASSPHRASE}\". Resulting file will be $DESTFILE"

# decrypt file
echo "${PASSPHRASE}"|gpg --batch --passphrase-fd 0 --decrypt -o "${DESTFILE}" "${FILENAME}"

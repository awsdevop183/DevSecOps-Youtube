#!/bin/bash

set -euo pipefail

S3_BUCKET="${S3_BUCKET:-bunnyops}"
S3_PREFIX="mysql"
WORKDIR=$(mktemp -d)

trap 'rm -rf "${WORKDIR}"' EXIT

if [ $# -lt 1 ]
then
    echo "Usage: $0 <databse-1> <database-2>..."
    exit 1
fi

for TOOL in mysqldump aws gzip
do
    if ! command -v $TOOL &> /dev/null
    then
        echo "Error: ${TOOL} is not installed"
        exit 1
    fi
done

DATE=$(date +%F_%H_%M)

echo "===== MySQL backup started: $(date)====="

OK=0
FAILED=0

for DB in "$@"
do
    echo ""
    echo "------ ${DB} ----"
    
    FILE="${DB}-${DATE}.sql.gz"
    LOCAL="${WORKDIR}/$FILE"
    
    echo "  Dumping ...."
    
    
    if ! mysqldump "${DB}" 2> "${WORKDIR}/error.log" | gzip > "${LOCAL}"
    then
        echo " Failed mysqldump error:"
        sed 's/^/        /' "${WORKDIR}/error.log"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    SIZE_BYTES=$(stat -c %s "${LOCAL}")
    
    if [ ${SIZE_BYTES} -lt 100 ]
    then
        echo " Failed, dump is empty ${SIZE_BYTES} bytes - not uploading"
        FAILED=$((FAILED + 1))
        continue
    fi
    SIZE=$(du -h "${LOCAL}" | cut -f 1)
    
    echo " Dumped ${FILE} ${SIZE}"
    
    echo "  uploading to s3://${S3_BUCKET}/${S3_PREFIX}/${DB}/"
    if aws s3 cp ${LOCAL} s3://${S3_BUCKET}/${S3_PREFIX}/${DB}/${FILE}
    then
        echo "Uploaded successfully..."
        OK=$((OK + 1))
    else
        echo " Failed upload error"
        FAILED=$((FAILED +1))
        
    fi
    
done

echo ""
echo "====Done: ${OK} succeeded, ${FAILED} failed ====="

if [ "${FAILED}" -gt 0 ]
then
    exit 1
fi














# Test-2026-07-26_06_10.sql.gz


# DB-DATE.sql.gz
# bunnyops/mysql/
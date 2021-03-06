#!/usr/bin/env bash

function checkEnv {
    envName=$1
    envValue=${!envName}
    if [ -z "$envValue" ]; then
        echo "$envName is not defined"
        return 1
    fi
}

function checkAllEnv {
    checkEnv AWS_ACCESS_KEY_ID &&
        checkEnv AWS_SECRET_ACCESS_KEY &&
        checkEnv AWS_DEFAULT_REGION &&
        checkEnv COUCHBASE_HOST &&
        checkEnv COUCHBASE_USERNAME &&
        checkEnv COUCHBASE_PASSWORD
}

function tryRemoveS3Bucket {
    s3Bucket=$1
    if aws s3 ls $s3Bucket; then
        aws s3 rm --recursive $s3Bucket
    fi
}

function doBackup {
    if [ $# -lt 1 ]; then
        echo "USAGE: $0 backup [s3 bucket]"
        exit 1
    fi
    s3Bucket=$1
    echo "Backing up to $s3Bucket"
    now=`date`
    localFolder=/tmp/backup
    rm -rf $localFolder &&
        mkdir -p $localFolder &&
        aws s3 sync s3://$s3Bucket $localFolder &&
        /opt/couchbase/bin/cbbackup http://$COUCHBASE_HOST $localFolder -u $COUCHBASE_USERNAME -p $COUCHBASE_PASSWORD -m accu &&
        echo "Back up at $now for $COUCHBASE_HOST" >> $localFolder/daily-backup-info.txt &&
        aws s3 sync $localFolder s3://$s3Bucket &&
        echo "Done"
}

function doFullBackup {
    if [ $# -lt 1 ]; then
        echo "USAGE: $0 full-backup [s3 bucket]"
        exit 1
    fi
    s3Bucket=$1
    echo "Do full backup to $s3Bucket"
    now=`date`
    localFolder=/tmp/backup
    rm -rf $localFolder &&
        mkdir -p $localFolder &&
        /opt/couchbase/bin/cbbackup http://$COUCHBASE_HOST $localFolder -u $COUCHBASE_USERNAME -p $COUCHBASE_PASSWORD &&
        echo "Back up at $now for $COUCHBASE_HOST" >> $localFolder/daily-backup-info.txt &&
        tryRemoveS3Bucket s3://$s3Bucket &&
        aws s3 cp --recursive $localFolder $s3Bucket &&
        echo "Done"
}

function doRestore {
    if [ $# -lt 2 ]; then
        echo "USAGE: $0 restore [s3 bucket] [bucket1,bucket2...]"
        exit 1
    fi
    s3Bucket=$1
    buckets=`echo $2 | sed 's/,/ /g'`
    echo "Restoring from $s3Bucket"
    rm -f /tmp/restore && mkdir -p /tmp/restore
    aws s3 sync s3://$s3Bucket /tmp/restore
    if [ $? -ne 0 ]; then
        exit 1
    fi
    for bucket in $buckets; do
        echo "Restoring bucket $bucket"
        /opt/couchbase/bin/couchbase-cli bucket-flush -c $COUCHBASE_HOST -u $COUCHBASE_USERNAME -p $COUCHBASE_PASSWORD --bucket=$bucket --force &&
            /opt/couchbase/bin/cbrestore /tmp/restore http://$COUCHBASE_HOST -u $COUCHBASE_USERNAME -p $COUCHBASE_PASSWORD -b $bucket -B $bucket
        if [ $? -ne 0 ]; then
            exit 1
        fi
    done
    echo "Done"
}

function showHelp {
    echo "USAGE: $0 backup|full-backup|restore"
}

checkAllEnv

if [ $? -ne 0 ]; then
    exit 1
fi

if [ $# -lt 1 ]; then
    exec /bin/bash
fi

cmd=$1
shift

echo "Using COUCHBASE_HOST=$COUCHBASE_HOST"
echo "Using COUCHBASE_USERNAME=$COUCHBASE_USERNAME"
echo "Using COUCHBASE_PASSWORD=${COUCHBASE_PASSWORD:0:4}****"

case $cmd in
    backup)
        doBackup $@
        ;;
    full-backup)
        doFullBackup $@
        ;;
    restore)
        doRestore $@
        ;;
    *)
        exec $cmd $@
        ;;
esac

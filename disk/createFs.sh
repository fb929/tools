#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

do_usage(){
    cat <<EOF
generating commands for creating fs on block device and mounting

usage: $0 <block_device> <mount_dir>

options:
    block_device - path to block device
    mount_dir - path for mount dir

examples:
    $0 /dev/xvdf /var/lib/prometheus
EOF
    exit 1
}
FS="ext4"
MKFS="mkfs.$FS -m 0"
MOUNT_OPTS="defaults,noatime,nodiratime,nofail"
for ARG in $@; do
    if echo "$ARG" | grep -qP -- "^(--help|-h|help)$"; then
        do_usage
    elif echo $ARG | grep -qP "^/dev/[a-zA-Z0-9_]+$"; then
        BLOCK_DEVICE="$ARG"
    elif echo $ARG | grep -qP "^/[a-zA-Z0-9_]+"; then
        MOUNT_DIR="$ARG"
    elif [[ "$ARG" == "xfs" ]]; then
        FS="xfs"
        MKFS="mkfs.$FS"
        MOUNT_OPTS="defaults,nofail"
    fi
    shift
done
if [[ -z $MOUNT_DIR || -z $BLOCK_DEVICE ]]; then
    do_usage
fi

cat <<EOF
# create fs
$MKFS $BLOCK_DEVICE &&
sleep 5 &&
partprobe $BLOCK_DEVICE &&
UUID=\$( lsblk --output UUID $BLOCK_DEVICE | tail -1 )
if [[ -z \$UUID ]]; then
    echo "ERROR: failed get UUID for BLOCK_DEVICE=$BLOCK_DEVICE" 1>&2
    exit 1
fi
echo -e "UUID=\$UUID\t$MOUNT_DIR\t$FS\t$MOUNT_OPTS\t0 0" >> /etc/fstab &&
install -d $MOUNT_DIR &&
mount $MOUNT_DIR
EOF

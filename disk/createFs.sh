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
for ARG in $@; do
    if echo "$ARG" | grep -qP -- "^(--help|-h|help)$"; then
        do_usage
    elif echo $ARG | grep -qP "^/dev/[a-zA-Z0-9_]+$"; then
        BLOCK_DEVICE="$ARG"
    elif echo $ARG | grep -qP "^/[a-zA-Z0-9_]+"; then
        MOUNT_DIR="$ARG"
    fi
    shift
done
if [[ -z $MOUNT_DIR || -z $BLOCK_DEVICE ]]; then
    do_usage
fi

cat <<EOF
# create fs
mkfs.ext4 -m 0 $BLOCK_DEVICE &&
sleep 5 &&
partprobe $BLOCK_DEVICE &&
UUID=\$( lsblk --output UUID $BLOCK_DEVICE | tail -1 )
if [[ -z \$UUID ]]; then
    echo "ERROR: failed get UUID for BLOCK_DEVICE=$BLOCK_DEVICE" 1>&2
    exit 1
fi
echo -e "UUID=\$UUID\t$MOUNT_DIR\text4\tdefaults,noatime,nodiratime,nofail\t0 0" >> /etc/fstab &&
install -d $MOUNT_DIR &&
mount $MOUNT_DIR
EOF

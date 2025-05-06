#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin

do_usage(){
    cat <<EOF
generating commands for creating swap on block device and mounting

usage: $0
EOF
    exit 1
}
for ARG in $@; do
    if echo "$ARG" | grep -qP -- "^(--help|-h|help)$"; then
        do_usage
    fi
    shift
done

SWAP_DEV=$( lsblk -nio NAME,MAJ:MIN,MOUNTPOINT 2>/dev/null \
    | sed 's=\s\+[0-9]\+:[0-9]\+\s\+=;=g' \
    | sed -e ':a;N;$!ba;s=\n[ |`][^\n]*;=;=g' -e 's/;\+/ /g' \
    | grep -v '/' \
    | awk '{print $1}'
)
echo "UUID=\$( mkswap /dev/$SWAP_DEV | grep UUID | cut -d = -f 2); if ! [[ -z \$UUID ]]; then swapon /dev/$SWAP_DEV; echo -e \"UUID=\$UUID none swap sw 0 0\" >> /etc/fstab; fi"

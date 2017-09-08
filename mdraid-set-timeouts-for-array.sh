#!/bin/bash
# Copyright (C) 2017 by Jonathan G. Underwood
# This file is part of mdraid-safe-timeouts.
#
# mdraid-safe-timeouts is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# mdraid-safe-timeouts is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with mdraid-safe-timeouts.  If not, see
# <http://www.gnu.org/licenses/>.

# This script takes a device id of a raid device eg. md0 as input. It
# then establishes what partitions comprise that raid array, and then
# works out what the parent device of each of those volumes is. For
# each parent device, the timeouts are then set appropriately.

PATH="$(dirname "$0"):/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"

dev="$1"

logger "setting timeouts for /dev/$dev"

mdadm_output=$(mdadm --query --detail --export /dev/"$dev" 2>/dev/null)
if [[ $? -ne 0 ]] ; then
    logger "/dev/$dev not an mdraid volume"
    exit 1
fi

vols=$(echo "$mdadm_output" | grep "MD_DEVICE_.*_DEV" | cut -d "=" -f 2 | xargs basename -a)
for vol in $vols ; do # Nb. No quotes around $vols to remove new lines
    # Nb. may be better to use the following rather than readlink:
    # $(lsblk -no pkname /dev/sdb1 | head -1) here
    parent=$(readlink -f "/sys/class/block/"$vol"/..")
    mdraid-set-timeouts-for-disk.sh "$(basename "$parent")"
done

logger "finished setting timeouts for /dev/$dev"
exit 0

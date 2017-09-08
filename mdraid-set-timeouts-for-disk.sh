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

# This script takes a device id eg. sda as input, and then examines
# all partitions associated with that device and, if raid partitions
# are present on the device, sets the drive and controller timeouts
# appropriately. This script is intended to be run by udev rules.

PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"

dev="$1"

logger "setting timeouts for /dev/$dev"

lsblk_output=$(lsblk -o type /dev/"$dev")

if ! echo "$lsblk_output" | grep -q raid ; then
    # No raid partitions present so we'll leave this disk alone
    logger "No raid partitions found on /dev/$dev"
    exit 0
fi

if echo "$lsblk_output" | grep -q raid[1-9]* ; then
    raidgt0="true"
else
    raidgt0="false"
fi

if echo "$lsblk_output" | grep -q raid0 ; then
    raid0="true"
else
    raid0="false"
fi

smartctl_output=$(smartctl -l scterc /dev/"$dev")

if echo "$smartctl_output" | grep -q "Disabled" ; then
    erc="disabled"
elif echo "$smartctl_output" | grep -q "command not supported" ; then
    erc="unsupported"
elif echo "$smartctl_output" | grep -q "seconds" ; then
    erc="enabled"
else
    exit 1
fi

if [[ "$raid0" == "true" ]] ; then
    # If there's a raid0 partition disable ERC and set long controller
    # timeout. Do this even if there's also raid1+ paritions.
    if [[ "$erc" == "enabled" ]] ; then
	smartctl -l scterc,0,0 /dev/"$dev"
	if [[ $? -eq 0 ]] ; then
	    logger "disabled scterc for /dev/$dev"
	    erc="disabled"
	else
	    logger "failed to disable scterc for /dev/$dev"
	    logger "failed to optimize drive and controller timeouts for /dev/$dev"
	    exit 1
	fi
    fi
    echo 180 > /sys/block/"$dev"/device/timeout
    logger "controller timeout for /dev/$dev set to 180 secs"
elif [[ "$raidgt0" == "true" ]] ; then
    # If drive doesn't support scterc, ensure that the controller
    # timeout is set to long time - 180 secs is reported to be sufficient
    if [[ "$erc" == "unsupported" ]] ; then
	echo 180 > /sys/block/"$dev"/device/timeout
	logger "controller timeout for /dev/$dev set to 180 secs"
    else
	# Try to set the scterc timeout to be 5 seconds less than the
	# controller timeout.
	timeout=$(( (`cat /sys/block/"$dev"/device/timeout` - 5) * 10))
	if (( "$timeout" > 999 )) ; then
	    timeout=999
	fi
	smartctl -q errorsonly -l scterc,"$timeout","$timeout" /dev/"$dev"
	if [[ "$?" -eq 0 ]] ; then
	    logger "erc timeout for /dev/$dev set to $timeout"
	    erc="enabled"
	else
	    # Setting disk scterc timeout failed, so instead we'll try
	    # to disable scterc and set a long controller timeout
	    logger "failed to set scterc timeout for /dev/$dev"
	    if [[ "$erc" == "enabled" ]] ; then
		smartctl -l scterc,0,0 /dev/"$dev"
		if [[ "$?" -eq 0 ]] ; then
		    logger "disabled scterc for /dev/$dev"
		    erc="disabled"
		else
		    logger "failed to disable scterc for /dev/$dev"
		    logger "failed to optimize drive and controller timeouts for /dev/$dev"
		    exit 1
		fi
	    fi
	    echo 180 > /sys/block/"$dev"/device/timeout
	    logger "controller timeout for /dev/$dev set to 180 secs"
	fi
    fi
fi    

logger "finished setting timeouts for /dev/$dev"
exit 0

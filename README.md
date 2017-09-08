# mdraid-safe-timeouts
Udev rules and helper scripts for setting safe disk scterc and drive controller
timeout values for mdraid arrays.

## Background
When the OS tries to read from or write to the disk, it sends the command and
waits. What should happen is that drive returns writes the data successfully.

The proper sequence of events when something goes wrong and the drive can't read
the data the OS requests, it should return an error to the OS. In the case of a
failed read the raid code then calculates what the data should be from the other
disks in the array, and writes it back to the disk which raised an error.
Glitches like this are normal and, provided the disk isn't failing, this will
correct the problem.

Unfortunately, with commodity desktop drives, they can take over two minutes to
give up, while the linux kernel will, by default, give up after 30 seconds. At
which point, the RAID code recomputes the block and tries to write it back to
the disk. The disk is still trying to read the data and fails to respond, so the
raid code assumes the drive is dead and kicks it from the array. This is how a
single error with these drives can easily kill an array. With commodity desktop
drives, it is safer therefore to increase the time that the kernel waits for the
disk to return it to allow an error. Empirically it's been found that 180
seconds is sufficient[1] - all known desktop drives will eventually return an error
within this time. Fortunately, the Linux kernel allows setting this timeout on a
per drive basis via `/sys/block/<device_id>/device/timeout`.

The situation becomes more complicated for higher end devices (often intended
for use in hardware RAID arrays) which support SCT Error Recovery Control
(SCTERC), also called TLER on some drives. This is a configurable pair of
settings (one for read and one for right) that set the time that the drive
should try to read/write for before returning an error to the OS. In this case
it's important to set the both the SCTERC timeouts and kernel controller
timeouts appropriately - we certainly don't want the kernel timing out before
the disk has timed out.

See [1,2] for further details.

## Strategy
The approach we take here is to adjust timeouts for drives containing mdraid
managed RAID partitions as follows:

0. Discover all partitions on the drive.
1. If the drive contains any RAID0 partitions, disable STCERC if present, and
   set the kernel controller timeout to 180 secs.
2. If the drive contains redundant RAID partitions (level 1 or higher) and no RAID0 partitions:
      * If the drive does not support STCERC, set the kernel controller timeout to 180 secs.
      * If the drive does support STCERC, set the STCERC timeouts to be 5
        seconds less than the kernel controller timeout (which is 30 seconds by
        default)
      * If setting the STRCERC timeouts fails, then we disable STCERC and set
        the kernel controller timeout to 180 secs

## udev triggering
The implementation uses udev rules for triggering the setting of the timeouts.
There are actually two strategies that are available:

0. Trigger on creation/change of an mdraid device (e.g. /dev/md0). When that happens,
   discover the disks that contribute to the array and set the timeouts for each
   according to the strategy above
1. Trigger whenever a partition is created/changed, discover the host drive and
   set the timeouts according to the strategy above
   
In both cases the timeouts for a drive can end up being set multiple times until
all partitions on the device are known about by the kernel and udev. At this
point it's not entirely clear which is the better approach, but the first seems
most sensible. In either case, the end result should be the same for any active
mdraid devices.


## Further reading
[1] http://strugglers.net/~andy/blog/2015/11/09/linux-software-raid-and-drive-timeouts/
[2] https://raid.wiki.kernel.org/index.php/Timeout_Mismatch



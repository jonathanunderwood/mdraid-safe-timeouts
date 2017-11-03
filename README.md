# mdraid-safe-timeouts
Udev rules and helper scripts for setting safe disk scterc and drive controller
timeout values for mdraid arrays.

## Background

When the OS tries to read from or write to the disk, it sends the
command and waits. What should happen is that drive returns writes the
data successfully.

The proper sequence of events when something goes wrong and the drive
can't read the data the OS requests, it should return an error to the
OS. In the case of a failed read the raid code then calculates what
the data should be from the other disks in the array, and writes it
back to the disk which raised an error.  Glitches like this are normal
and, provided the disk isn't failing, this will correct the problem.

Unfortunately, with commodity desktop drives, they can take over two
minutes to give up, while the linux kernel will, by default, give up
after 30 seconds. At which point, the RAID code recomputes the block
and tries to write it back to the disk. The disk is still trying to
read the data and fails to respond, so the raid code assumes the drive
is dead and kicks it from the array. This is how a single error with
these drives can easily kill an array. With commodity desktop drives,
it is safer therefore to increase the time that the kernel waits for
the disk to return it to allow an error. Empirically it's been found
that 180 seconds is sufficient[1] - all known desktop drives will
eventually return an error within this time. Fortunately, the Linux
kernel allows setting this timeout on a per drive basis via
`/sys/block/<device_id>/device/timeout`.

The situation becomes more complicated for higher end devices (often
intended for use in hardware RAID arrays) which support SCT Error
Recovery Control (SCTERC), also called TLER on some drives. This is a
configurable pair of settings (one for read and one for right) that
set the time that the drive should try to read/write for before
returning an error to the OS. In this case it's important to set the
both the SCTERC timeouts and kernel controller timeouts appropriately
since we don't want the kernel timing out before the disk has timed
out.

See [1,2] for further details.

## Strategies
We provide several sets of udev rules here which implement slightly
different approaches to the problem.

### Strategy 0

This is the simplest strategy, and involves making no changes to the
SMART settings of the disks.

This strategy first checks to see if the disk contains any RAID
partitions of level 1 or higher. If not, no changes are made.

If the disk contains a RAID level 1 or higher parition:
* Use smartctl to see if the disk has any STCERC timeouts set
* If STCERC timeouts are set, no changes are made to the kernel
  controller timeout.
* If the disk doesn't support STCERC, or STCERC is disabled,
  then we set the kernel controller timeout to 180 seconds.

### Strategy 1 and 2

Strategies 1 and 2 attempt to actively adjust the STCERC settings as
well as set an appropriate kernel controller timeout.

The approach we take is to adjust timeouts for drives containing
mdraid managed RAID partitions as follows:

* Discover all partitions on the drive.
* If the drive contains any RAID0 partitions, disable STCERC if present, and
  set the kernel controller timeout to 180 secs.
* If the drive contains redundant RAID partitions (level 1 or higher) and no
  RAID level 0 partitions:
    * If the drive does not support STCERC, set the kernel controller
      timeout to 180 secs.
    * If the drive does support STCERC, set the STCERC timeouts to be 5
      seconds less than the kernel controller timeout (which is 30 seconds
      by default)
    * If setting the STRCERC timeouts fails, then we disable STCERC and set
      the kernel controller timeout to 180 secs

The Strategy 1 and 2 implementations use slightly different udev rules
for triggering the setting of the timeouts:

**Strategy 1:** Trigger on creation/change of an mdraid device
(e.g. /dev/md0). When that happens, discover the disks that contribute
to the array and set the timeouts for each according to the strategy
above

**Strategy 2:** Trigger whenever a partition is created/changed,
discover the host drive and set the timeouts according to the strategy
above
   
In both cases the timeouts for a drive can end up being set multiple
times until all partitions on the device are known about by the kernel
and udev. At this point it's not entirely clear which is the better
approach, but the first seems most sensible. In either case, the end
result should be the same for any active mdraid devices.

## Prior art
This approach was strongly influenced by some earlier work implementing a udev
mechanism for setting the timeouts.

* https://bugs.debian.org/780207
* https://bugs.debian.org/780162
* https://www.smartmontools.org/ticket/658

## Further reading
[1] http://strugglers.net/~andy/blog/2015/11/09/linux-software-raid-and-drive-timeouts/

[2] https://raid.wiki.kernel.org/index.php/Timeout_Mismatch



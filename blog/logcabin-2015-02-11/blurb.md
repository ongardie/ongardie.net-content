This is the fourth in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This entry describes
LogCabin's new storage module and several other recent improvements.


----


Storage Module
--------------

Storage modules are how LogCabin servers persist their logs to disk. Most of
the time, entries are just appended to the end of the log. Two other operations
come up less frequently:

1. If leaders change, a few entries from the end of the log might need to be
truncated away.

2. Periodically, snapshots are written that make some prefix of the log
redundant. Those entries should be discarded.

Up until now, LogCabin had a pretty naive storage module named SimpleFileLog.
On each log append, SimpleFileLog would write the new log entry to disk as a
separate file, then `fsync` that file, the directory, and a separate metadata
file. This was slow and was also never tested. It was never meant to be more
than just a placeholder, and [replacing
it](https://github.com/logcabin/logcabin/issues/30) has been on the to-do list
since 2012.

Last year when I was running performance benchmarks for my dissertation, I
finally had a need for a faster storage module. That's how SegmentedLog was
born. It was written to use disks efficiently, while still sitting on top of
any filesystem for easy deployment. SegmentedLog worked well enough for
performance benchmarks, but my dissertation got in the way, and SegmentedLog
stayed in a not-quite-usable state.

Over the last couple of weeks, I dug up SegmentedLog, cleaned it up, tested it,
and merged it into master. It should behave very similarly as before, but I did
fix a few bugs in the process and touched nearly every line of code.

A storage module that wrote all entries to a single file in a sequential manner
would be really simple and efficient. However, that wouldn't handle truncating
the start of the log well (after snapshotting). The POSIX interface makes
truncating the end of files easy but provides no support for truncating the
start of a file. On the other end of the spectrum, writing each entry to its
own file as in SimpleFileLog is inefficient, as it wastes precious disk writes
on directory updates.

Finding some middle ground, SegmentedLog appends new entries to files it calls
segments that are about 8 megabytes in size. Once a segment fills up with
entries, it starts writing entries into a new file. To truncate entries at the
end of the log, it uses the filesystem's truncate operation. To truncate
entries at the start of the log, it first writes the new start index to a
metadata file, then it removes any complete segments that are no longer needed.
This can leave up to one segment's worth of redundant entries (a few megabytes)
in place at the start of the log, which shouldn't pose a problem.

To further avoid metadata updates, SegmentedLog avoids changing the segment's
file size during appends. A separate thread allocates segment files to be their
full size and calls `fsync` to write the file's metadata to disk. Normal log
appends only require `fdatasync` calls after that, which should be cheaper than
full `fsync` calls. When a segment fills up (it can't fit another entry), the
few extra zero bytes at the end are truncated, just to tidy things up.

SegmentedLog will become the default storage module once we gain more
experience with it, and SimpleFileLog will be deprecated soon.


Configurable Timeouts
---------------------

Two classes of timeouts where hard-coded in LogCabin and are now configurable:

1. The [Raft-level timeouts](https://github.com/logcabin/logcabin/issues/58)
   such as the election timeout and the heartbeat interval.
2. The [lower-level
   heartbeats](https://github.com/logcabin/logcabin/commit/2c645dea) sent on
   TCP connections that have slow outstanding RPCs, used to make sure those
   connections are still alive.

The interesting thing about the lower-level heartbeats is that the code is
shared with the client library, and the client library doesn't consume a
configuration file. Thus, the ``Client::Cluster`` constructor can now take a
map from string to string of options, which applications can configure as they
see fit. The only option so far is this timeout setting, but I'm sure more will
follow.


Application-Level Testing
-------------------------

LogCabin's client library includes a mode in which all operations execute using
an in-memory tree data structure. This is meant to aid with testing
applications, so that they don't need to set up a full LogCabin cluster for
every test. This testing mode was
[limited](https://github.com/logcabin/logcabin/issues/93), however, in that it
didn't give application-level tests control over things like timeout failures,
or injecting state changes or results when specific operations were called.

Now the application can register a pair of callbacks with the client library
which interpose on requests to the LogCabin Tree. They can inspect the contents
of requests, modify them, and/or return custom results.

These callbacks operate at the level of protocol buffers used for communication
between clients and servers ([Protocol::Client::ReadOnlyTree and
Protocol::Client::ReadWrite::Tree](https://github.com/logcabin/logcabin/blob/bf7d2ff3/Protocol/Client.proto#L233)).
These protocols aren't exactly part of the public LogCabin API, but using this
low layer allows applications to get at all the information they need in a few
lines of code, without being burdened by a bunch of C++ types.

Misc
----

- Remember those [event loop
  crashes](https://github.com/logcabin/logcabin/issues/82) from [the last
  post](${URL_PREFIX}/blog/logcabin-2015-01-19)? I spotted [similar
  problems](https://github.com/logcabin/logcabin/issues/86) with a few other
  classes in the RPC layer, and I fixed those in similar ways.

- There were a couple of places in LogCabin where small amounts of data were
  [leaked](https://github.com/logcabin/logcabin/issues/83) with each thread.
  This is because C++ destructors aren't called for `__thread` variables, or at
  least not under GCC 4.4. Those leaks weren't really a concern on the LogCabin
  servers, where the number of threads is limited. However, that code was being
  shared with the client library, and it would have been possible for an
  application that used LogCabin to leak an ever-growing amount of memory by
  creating and destroying threads. That's now fixed.

- Nate and I [merged](https://github.com/logcabin/logcabin/issues/74) in a
  RHEL6-compatible init script and added `scons install` and `scons rpm`
  targets. The `scons install` will put the server binary and a few of the
  example clients into `/usr/bin` and will install the init script. The RPM target
  takes those same install targets and puts them into an RPM package (later
  updated to [not strip
  binaries](https://github.com/logcabin/logcabin/issues/92)). Scons's support
  for RPM is pretty half-baked, so that took some hackery. The rpm target
  creates a "source RPM" consisting of the same binary files, since that seems
  to be the easiest path to to a binary RPM. Building an RPM also meant we had
  to choose a version number; the current version is a humble 0.0.1-alpha.0.


<a name="logcabin-2015-02-11-performance"></a>

A Note on LogCabin's Performance
--------------------------------

Several people have asked me about LogCabin's performance. The top questions are:

- Why is performance so bad for me?
- Why can't we reproduce the numbers in your dissertation?

Unfortunately, performance in LogCabin has never been the top priority, and it
hasn't gotten the dedicated attention it needs.

I made several changes while running benchmarks for my dissertation that still
haven't landed in master (these are in the
[nasty-thesis-wip](https://github.com/logcabin/logcabin/commit/a7ce12da) tag,
which I *will not* be supporting). Some of these changes may be improvements
while others are probably bad ideas. They need further evaluation and care
before they're ready to merge.

The good news:

- The SegmentedLog storage module should help quite a bit for disk-bound
  applications. That was the biggest chunk of code from my dissertation
  benchmarking, and I'm glad it's merged in now.

- Nate discovered that LogCabin operations were slow when the Raft election
  timeout was configured to be on the order of 10 seconds. It turns out that a
  [condition variable should have been
  notified](https://github.com/logcabin/logcabin/commit/35b46b51)
  to cause heartbeats to be sent out immediately after a read request arrived,
  but it wasn't. That omission slowed down each read-only operation by up to 75
  ms with the default timeout settings, and most operations were probably
  slowed down by around 70 ms (if you did two reads back to back, the second
  one would have to wait nearly the full heartbeat interval).

And the bad news:

- I can't say how the current master branch's performance compares to the
  dissertation benchmarks, since I don't have that machine configuration set up
  anymore. If anyone has a few dedicated machines around that I could plug some
  fast SSDs into and run some benchmarks on, please let me know (RAMCloud's
  servers are busy and Scale's servers just moved to Indiana).

- The master branch is still missing support for pipelining AppendEntries RPCs.
  I started to implement this for my dissertation, but I didn't squeeze all the
  potential performance out. The changes aren't ready to be merged.

- It's hard to guess what other performance bottlenecks might exist. It'll take
  some careful measurement, and while I enjoy working on that kind of stuff,
  LogCabin performs well enough at the moment that it's not a high priority.


Next
----

I'll be working through more of the [issue
backlog](https://github.com/logcabin/logcabin/issues) next. First up is a
[problem](https://github.com/logcabin/logcabin/issues/90) that Scale's
regression tests found, where drastically changing the time on the leader of a
LogCabin cluster will needlessly kill all of the clients. Thanks to [Scale
Computing](http://www.scalecomputing.com) for supporting this work.

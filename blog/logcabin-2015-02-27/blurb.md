This is the fifth in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This entry describes a new
cluster-wide monotonic clock used for client session expiry, a new tool to dump
out the contents of a LogCabin server's log and snapshot, a couple of
performance improvements, and several changes around how server IDs and
addresses are assigned and used.

---

## Cluster Clock

The servers' state machines keep track of client sessions, as described in
section 6.3 of my
[dissertation](https://github.com/ongardie/dissertation/#readme). The client
sessions are used to avoid applying an operation more than once if a client
retries it (e.g., if the client didn't receive a reply). Sessions are expired
eventually, and this could potentially happen while a client is still active.
In LogCabin, if a client attempts to modify the state machine and its session
has expired, that client will PANIC. That's because it'd be a difficult error
for clients to to recover from, whereas usually client crashes are a reality
that the higher-level distributed application needs to deal with, at least
occasionally.

LogCabin used to expire client sessions using wall time. The leader that
created each log entry would attach its current system time to each command in
the log, and the state machines would use these times to expire sessions
(remember, the state machines have to be deterministic). Client sessions were
expired after an hour of inactivity, a fairly long time so that clients would
hardly ever panic. And the client library sends heartbeats to keep its session
alive during periods of inactivity, useful in case a client made some changes,
stopped for an hour, and then came back to issue more requests.

One problem with this approach is that, if different leaders have drastically
different notions of the wall time, or if one server's time jumps forwards
drastically, all clients would crash. Whether that's a realistic problem
depends a lot on the environment and the cost of crashing clients. It's an
unnecessary limitation, though, and it [failed Scale's regression
tests](https://github.com/logcabin/logcabin/issues/90), which mess with the
system clocks, so it seemed like it was time to fix it.

The goal was to build a cluster-wide notion of a clock that wouldn't be
affected by skew across servers or by jumps in the system time on a single
server. We still wanted the clock rate to correspond roughly to seconds passing
so that we could specify reasonable timeout durations, but keeping the Unix
epoch wasn't necessary. We essentially wanted a monotonic clock as found on
modern Linux systems, but across the cluster. Linux's monotonic clock counts
the nanoseconds since the system booted, and LogCabin's new cluster clock
roughly counts the nanoseconds the cluster has had a working leader.

Each log entry is now stamped with the leader's cluster time. The leader's
cluster time advances at exactly the rate of its local monotonic clock. When a
new leader takes over, it starts ticking the cluster clock from the time found
in its last log entry. (When snapshotting, the cluster time of a snapshot's
last included entry is saved in the snapshot header.)

State machines now use the cluster time found in the log entries to expire
sessions. Because these times are committed in the log, they are the same for
each state machine. They are also monotonic since the clock on each leader is
monotonic, and they won't be affected by the system clocks at all.

## Storage/Tool

A [new executable](https://github.com/logcabin/logcabin/commit/7ff9a7c1) (built
at `build/Storage/Tool` and installed as `logcabin-storage`) dumps the contents
of the log and snapshot from storage in a somewhat human-readable form. Since
the log and snapshot are binary-encoded, it was very hard to verify their
contents in the past. This tool should aid with troubleshooting and might be
useful if/when things go wrong. We might expand it later on to modify the
storage contents, should that be necessary.

The log modules aren't written to operate in a read-only mode, so the storage
tool may not be used while the LogCabin daemon is running. The two coordinate
using `flock()` to prevent this. Interestingly, I first had the two `flock()`
the storage directory (to which I had a convenient file handle), and that
worked great locally. It didn't work over NFS however (on RHEL6), so I
[changed](https://github.com/logcabin/logcabin/commit/b97b9180) it to call
`flock()` on a file called "lock" within the storage directory; this does seem
to work even over NFS. I don't encourage NFS use for LogCabin storage in
production, by the way, but I use it sometimes for testing; I wanted this to
just work.

## Performance Improvements

After the [last blog post](${URL_PREFIX}/blog/logcabin-2015-02-11/),
I was inspired to look through the code I used for my dissertation benchmarks
and [take inventory](https://github.com/logcabin/logcabin/issues/95) of it.
It had various changes that aren't necessarily good ideas, and two that were useful:

1. It changed the log entry command format from ProtoBuf's slow text format
   (mainly useful for debugging and unit tests) to its fast binary format. I
   didn't use the exact same code, but I did [fix
   this](https://github.com/logcabin/logcabin/issues/96). I'd expect a moderate
   increase in performance.

2. Pipelining of AppendEntries RPCs. The code there isn't very useful, but it
   did prove that pipelining is a good idea. I created [issue
   97](https://github.com/logcabin/logcabin/issues/97) to track this.

There was also another minor issue with a major effect: the Raft module in
LogCabin has a corresponding Invariants class, which runs before the Raft
module mutex is released to make sure various bits of state seem sane. For
example, it asserts that the terms of entries in the logs are monotonically
increasing. This is [slow](https://github.com/logcabin/logcabin/issues/98), and
it gets to be extremely slow once there are a lot of log entries. It's useful
during unit tests and maybe a small system-wide test every now and then, but it
definitely shouldn't run in production. I disabled it by default, and it can be
re-enabled with the config setting `raftDebug` (the `storageDebug` flag is
similar but affects the `SegmentedLog` storage module).

## Server IDs

Server IDs have been [broken](https://github.com/logcabin/logcabin/issues/47)
for years, ever since membership changes were introduced. For example, running
a LogCabin daemon without specifying a server ID would just default to server
ID 1. Reconfiguring a cluster would assign the given _N_ addresses the IDs 1
through _N_. If you didn't get things in exactly the right order everywhere,
terrible things could happen, like two servers having the same ID, or one
server having two IDs, or addresses being completely incorrect.

I made several changes in this space:

- Server IDs must always be assigned explicitly; there is no default anymore.
- Server IDs are now given on the configuration file rather than as a
  command-line argument. Configuration files can no longer be shared across
  servers this way, but on the other hand, each configuration file does not need
  to list every other server.
- Servers can now supply multiple addresses to listen on, and clients and
  servers will attempt to use any of them (randomly). Setting the addresses is
  also required in the configuration file.
- The Reconfigure script now takes the addresses given to it, and it queries
  each server in turn to find its server ID and its canonical list of addresses.
  It uses these IDs and addresses to form the new configuration. This makes
  Reconfigure much [safer](https://github.com/logcabin/logcabin/issues/73), and
  it avoids having to pass every server ID to the Reconfigure script on the
  command line.

The [README](https://github.com/logcabin/logcabin#readme) got an update due to
these and other issues. It also no longer relies on `/etc/hosts` for DNS, so it
should be easier for people to give LogCabin a spin.

## Next

I'm not sure what's next, but I'll keep working on the [issue
backlog](https://github.com/logcabin/logcabin/issues) unless something new pops
up. Thanks to [Scale Computing](https://www.scalecomputing.com) for supporting
this work.

This is the third in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This entry describes a new
tool to extract information from LogCabin servers and a tricky bug that
occurred when unregistering handlers from the event loop.

---

Server Stats
------------

Nate Hardt has been integrating and testing LogCabin into Scale's software
stack, and he's run into a few issues lately that were needlessly
time-consuming to diagnose. Some of the problems were silly, like when one test
stopped the LogCabin daemon and it was never restarted for the next test.
Still, even this was one hard to spot, since LogCabin had no tooling for
diagnostics.

To make our lives easier, we [wanted a
tool](https://github.com/logcabin/logcabin/issues/77) that would go collect
information that might be useful about each server's internals, then report it
back in a nice way.

The first step was to collect some statistics into a Protocol Buffer, and have
servers dump these out to their debug logs. They now do this periodically
(defaulting to once per minute) and also upon the `SIGUSR1` signal. Protocol
Buffers are nice for this sort of thing, since we anticipate the number of
stats to grow over time, and not every tool needs to understand each stat.

Here's an example of the raw output (using the Protocol Buffers text format):

    server_id: 1
    address: "192.168.2.1:61023"
    start_at: 1421726306722327036
    end_at: 1421726306722407779
    raft {
      current_term: 39
      state: LEADER
      commit_index: 135
      last_log_index: 135
      leader_id: 1
      voted_for: 1
      start_election_at: 9223372036854775807
      withhold_votes_until: 9223372036854775807
      last_snapshot_index: 123
      last_snapshot_bytes: 1207
      log_start_index: 124
      log_bytes: 11019
      peer {
        server_id: 1
        old_member: true
        new_member: false
        staging_member: false
        last_synced_index: 135
      }
      peer {
        server_id: 2
        old_member: true
        new_member: false
        staging_member: false
        request_vote_done: true
        have_vote: true
        force_heartbeat: false
        next_index: 136
        last_agree_index: 135
        is_caught_up: true
        next_heartbeat_at: 1421726306777304527
        backoff_until: 1421726273743534090
      }
      peer {
        server_id: 3
        old_member: true
        new_member: false
        staging_member: false
        request_vote_done: false
        have_vote: false
        force_heartbeat: false
        next_index: 136
        last_agree_index: 135
        is_caught_up: true
        next_heartbeat_at: 1421726306779778550
        backoff_until: 1421726273643086864
      }
      peer {
        server_id: 4
        old_member: true
        new_member: false
        staging_member: false
        request_vote_done: false
        have_vote: false
        force_heartbeat: false
        next_index: 136
        last_agree_index: 135
        is_caught_up: true
        next_heartbeat_at: 1421726306781546795
        backoff_until: 1421726270475566462
      }
      peer {
        server_id: 5
        old_member: true
        new_member: false
        staging_member: false
        request_vote_done: true
        have_vote: true
        force_heartbeat: false
        next_index: 136
        last_agree_index: 135
        is_caught_up: true
        next_heartbeat_at: 1421726306783424837
        backoff_until: 1421726273743630864
      }
    }

The second step was to go collect all this information with a new RPC, named
getServerStats(). This RPC is different from existing ones in that it's not
destined for the cluster leader. That's because we want statistics from every
individual server, and they need to be collected even if the cluster has no
leader. The client library had to be refactored a little bit as a result, so
that the event loop and TCP connection rate-limiting mechanism are available
outside of `Client::LeaderRPC`. A new client binary called `ServerStats`
invokes the RPC and prints out the results.

Finally, the `scripts/serverstats.py` script understands the meaning of the
ServerStats fields, and it tries to present something a little nicer for human
consumption. Some of the fields in the raw output (like nanoseconds since the
Unix epoch) are not easy for humans, so the script translates those to more
meaningful formats. It also uses colors to highlight interesting things, and
it'll output a warning if the cluster has no leader (more warnings to come in
the future).

Here's an example of the `serverstats.py` output for the same server as above:

    Server 1 at 192.168.2.1:61023:
      Leader at term 39
      Snapshot covers entries 1 through 123 (1207 bytes)
      Log covers entries 124 through 135 (11019 bytes)
      All log entries committed
      All log entries flushed to disk
      Voted for server 1
      Withholding votes for +infinity
      Configuration: [1, 2, 3, 4, 5]
      Peer 2 (old/curr):
        Next index: 136
        Match index: 135
        Next heartbeat in +54.897 ms
      Peer 3 (old/curr):
        Next index: 136
        Match index: 135
        Next heartbeat in +57.371 ms
      Peer 4 (old/curr):
        Next index: 136
        Match index: 135
        Next heartbeat in +59.139 ms
      Peer 5 (old/curr):
        Next index: 136
        Match index: 135
        Next heartbeat in +61.017 ms
      Stats collected at 2015-01-19 19:58:26.722
      Took 0.081 ms to generate stats

The ServerStats structure will need to include much more information to be
comprehensive, but it's probably easier to do that over time than all at once.
It currently includes just the state that was easily available in the Raft
module. There's also room for improvement on formatting the information nicely
and highlighting problems. Still, it's a useful tool already, and it's a good
starting point for further iteration.


DumpTree
--------

It's also important to be able to see what a LogCabin state machine is storing
in its Tree structure. I created a simple client called `DumpTree` to
recursively list out the values for each key. This will only work for small
state machines with human-readable values, but it's so much better than not
being able to see inside at all or writing a new C++ client every time.


Event Loop Crashes
------------------

Nate kept running into crashes like [this
one](https://github.com/logcabin/logcabin/issues/82), which came with pretty
mysterious error messages:

    pure virtual method called
    terminate called without an active exception
    Program received signal SIGABRT, Aborted.

After seeing a few of these with similar stack traces, we took a closer look
and found the problem. It's subtle but worth discussing.

LogCabin has a set of classes that wrap `epoll` and provide an event loop.
`Event::File` used to be an abstract base class that would register a file
descriptor with the event loop and arrange for the event loop thread to call a
virtual `handleFileEvent()` method appropriately. The destructor on File would
first interrupt the event loop thread, then unregister the file handler.


`RPC::ReceiveSocket` is one example of a class that derives from `Event::File`,
representing the receiving end of a TCP connection. When ReceiveSocket is
destroyed, C++ calls its destructor, starts to destroy the ReceiveSocket
members, probably scribbles on the vtable, and only *then* does it call the
destructor on the base class, `Event::File`. If the event loop thread called
handleFileEvent at this point (just before the `Event::File` destructor), the
process would crash.

The desired behavior is to run through the shutdown procedure for `Event::File`
first, interrupting the event loop thread and unregistering the file handler.
Only then would it be safe to start destroying the ReceiveSocket.

One way to achieve this behavior is to require all classes that derive from
`Event::File` to call a shutdown method on `Event::File` as the first step in
their destructors. However, this approach would be error-prone: if someone
forgot to call this method in any one class, they might get crashes, either now
or anytime in the future.

Instead, the approach I implemented split `Event::File` into two classes: one
to provide a handler, and a second one, called a `Monitor`, to register the
handler with the event loop. The lifetime of the handler must extend beyond
that of the monitor; thus, the monitor's destructor will interrupt the event
loop and unregister the handler before the handler begins to be destroyed. This
is relatively easy for users of these classes to get right: they generally
declare a monitor following a handler in the same object or scope. The
monitor's constructor needs a reference to the handler, so it's hard to declare
these variables backwards. And if someone forgets to create a monitor
altogether, their handler will *never* fire, so they will probably notice in
testing.



Next
----

Scale is in the middle of an office move that's making some of the development
and test clusters unavailable, so it's probably a good time to work through
some of the [issue backlog](https://github.com/logcabin/logcabin/issues) next.
Thanks to [Scale Computing](http://www.scalecomputing.com) for supporting this
work. And congrats to Nate on his first two pull requests
([#79](https://github.com/logcabin/logcabin/pull/79) and
[#81](https://github.com/logcabin/logcabin/pull/81)).

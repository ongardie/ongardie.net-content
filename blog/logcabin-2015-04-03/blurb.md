This is the sixth in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This entry describes
progress towards the upcoming 1.0.0 release of LogCabin, a useful new
command-line client to access LogCabin, and several other improvements.

----

Upcoming 1.0.0 Release
----------------------

We're pushing for a 1.0.0 release of LogCabin in the coming weeks. It's close.
[Milestone 1.0.0](https://github.com/logcabin/logcabin/milestones/1.0.0) on
GitHub tracks the release-blocking issues (there are currently 7 open).
[Scale](http://www.scalecomputing.com) will be rolling this out to QA and
eventually to customers, so we want to make sure it's ready. This has meant
additional testing and bug fixing, but also adding support for rolling
upgrades.

Most of the testing we've been doing uses Scale's internal testing system, but
I've also added two tests to LogCabin itself: an end-to-end test that
[repeatedly kills servers](https://github.com/logcabin/logcabin/issues/100),
and a test that [reconfigures the cluster
repeatedly](https://github.com/logcabin/logcabin/issues/108).

Up until now, LogCabin has not supported upgrades in any way from one commit to the next.
For example, a commit changing the format on disk would require deleting a server's entire
storage directory; a commit changing the network protocol would require a complete outage.
In some cases, upgrades could only be done destructively.

Now that 1.0 is coming up, this is no longer suitable. LogCabin will continue
to evolve over time, but it needs to provide clear and easy upgrade paths. One
of Scale's key features is non-destructive upgrades, where the cluster software
can be upgraded with no loss in availability. As LogCabin will be a part of
this software stack, it too needs to support rolling upgrades, during which
clients and servers may support different versions of the network protocols.

[Issue 99](https://github.com/logcabin/logcabin/issues/99) and the related
issues track the work of versioning various formats and protocols in LogCabin.
LogCabin will use [Semantic Versioning](http://semver.org) for its release
numbering, and the new
[RELEASES.md](https://github.com/logcabin/logcabin/blob/master/RELEASES.md)
file describes the various pieces that make up LogCabin's public API. That file
will also include release and upgrade notes moving forwards.

Command-Line Client
-------------------

LogCabin now includes a [command-line
client](https://github.com/logcabin/logcabin/issues/101) that allows accessing
and modifying the replicated state machine's tree data structure from the
shell. This makes it even easier to try out LogCabin. It's built at
`build/Examples/TreeOps` and installed as, simply, `/usr/bin/logcabin`. Here's
an example (after running a LogCabin server on localhost):

    $ alias logcabin='build/Examples/TreeOps --quiet --cluster=localhost'
    $ logcabin --help
    Run various operations on a LogCabin replicated state machine.
    
    Usage: build/Examples/TreeOps [options] <command> [<args>]
    
    Commands:
      mkdir <path>    If no directory exists at <path>, create it.
      list <path>     List keys within directory at <path>. Alias: ls.
      dump [<path>]   Recursively print keys and values within directory at <path>.
                      Defaults to printing all keys and values from root of tree.
      rmdir <path>    Recursively remove directory at <path>, if any.
                      Alias: removedir.
      write <path>    Set/create value of file at <path> to stdin.
                      Alias: create, set.
      read <path>     Print value of file at <path>. Alias: get.
      remove <path>   Remove file at <path>, if any. Alias: rm, removefile.
    
    Options:
      -c <addresses>, --cluster=<addresses>  Network addresses of the LogCabin
                                             servers, comma-separated
                                             [default: logcabin:61023]
      -d <path>, --dir=<path>        Set working directory [default: /]
      -h, --help                     Print this usage information
      -p <pred>, --condition=<pred>  Set predicate on the operation of the
                                     form <path>:<value>, indicating that the key
                                     at <path> must have the given value.
      -q, --quiet                    Suppress NOTICE messages
      -t <time>, --timeout=<time>    Set timeout for the operation
                                     (0 means wait forever) [default: 0s]
    $ logcabin mkdir /etc/logcabin
    $ date | logcabin write /etc/logcabin/now
    $ logcabin read /etc/logcabin/now
    Fri Apr  3 14:35:55 PDT 2015
    $ logcabin dump /etc
    /etc/
    /etc/logcabin/
    /etc/logcabin/now: 
        Fri Apr  3 14:35:55 PDT 2015
    
    $ echo 1337 | logcabin write /etc/passwd
    $ logcabin list /etc 
    logcabin/
    passwd
    $ logcabin dump
    /
    /etc/
    /etc/logcabin/
    /etc/logcabin/now: 
        Fri Apr  3 14:35:55 PDT 2015
    
    /etc/passwd:
        1337
    
    $ logcabin rmdir /etc/passwd
    terminate called after throwing an instance of 'LogCabin::Client::TypeException'
      what():  /etc/passwd is a file
    $ logcabin rmdir /
    $ logcabin dump
    /
    $

Note that this creates a new client session and connection to the server on
every invocation, so I'd advise against using it for operations that are
repeated frequently; see also [issue
116](https://github.com/logcabin/logcabin/issues/116).

Big State Machines
------------------

LogCabin was initially developed to store small amounts of metadata, but some
users might want to store more data in it (gigabytes) or they might do so by
accident. I want LogCabin 1.0.0 to function with large state machines, just
perhaps more slowly or with temporary availability losses. So I tried loading
up about 6 GB of keys into a state machine and taking a snapshot. This
confirmed a suspicion that [large snapshot files wouldn't
work](https://github.com/logcabin/logcabin/issues/52) when written with
ProtoBuf's I/O library, so I switched to reading and writing the files
directly. I also added a few messages to the debug log to show progress when
reading a large log from disk or loading a large snapshot. Things now seem to
function as intended with large state machines and snapshots, but memory usage
and availability could be improved in the future; see issues labeled
[bigdata](https://github.com/logcabin/logcabin/labels/bigdata) for more detail.

Misc
----

The TCP connection timeout is now
[configurable](https://github.com/logcabin/logcabin/issues/111), so that an
operation-wide timeout period isn't spent entirely on a single connection
attempt.

Skype Xu reported an [issue](https://github.com/logcabin/logcabin/issues/122) where
a `std::unique_lock` was accidentally not locking anything at all. The one-line patch by Skype Xu was correct, but I also
wanted to avoid this problem in the future. C++11 introduced two types of
scoped (RAII) objects that lock and then unlock a mutex:

- `std::lock_guard` locks on construction and unlocks on destruction, and that's about all it does.
- `std::unique_lock` is more flexible. It may or may not lock on construction,
  and it can be unlocked and locked again while the object exists.
  `std::unique_lock` is thus necessary in cases such as waiting for a condition
  variable, when the lock must be temporarily released.

Before, I was using `std::unique_lock` everywhere in LogCabin. However,
`std::lock_guard` is often sufficient, and it gives better static guarantees:
if you have a `std::lock_guard` instance, you at least know it's locking some
mutex. The problem that Skype Xu reported would not have existed with
`std::lock_guard`. So, I switched LogCabin to use `std::lock_guard` whenever
possible, and I'll try to maintain that coding convention moving forwards.

Finally, debug logs can now be better controlled by clients. Clients can
control which messages are logged, and they can opt to receive debug log events
as a [callback](https://github.com/logcabin/logcabin/issues/12), which they can
include into their own logging facilities. These things are available in the
namespace `LogCabin::Client::Debug` after including `<LogCabin/Debug.h>` and
`<LogCabin/Client.h>`.

Next
----

Next up, I plan to continue the push for 1.0.0 and will hopefully get a release
out the door.
We might even get a new logo for LogCabin in time; follow [this Twitter
thread](https://twitter.com/ongardie/status/584067985335193600) and [issue
123](https://github.com/logcabin/logcabin/issues/123) for progress.
I'll also be speaking about Raft and LogCabin at the upcoming [Sourcegraph
Hacker
Meetup](http://www.meetup.com/Sourcegraph-Hacker-Meetup/events/221199291/) on
April 15th and the [CoreOS Fest](https://coreos.com/fest/) on May 4th and 5th,
both in San Francisco.
Thanks to [Scale Computing](http://www.scalecomputing.com) for supporting
this work.

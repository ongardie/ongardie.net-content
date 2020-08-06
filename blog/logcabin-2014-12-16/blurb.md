This is the first in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This first entry catches
up on the developments from when I started working with [Scale
Computing](https://www.scalecomputing.com) in November, so it's longer than most
of the future updates will be.

The theme of this entry is getting started in a new environment. Up until now,
I'd done nearly all of the development of LogCabin on my laptop and on the
RAMCloud cluster. Running it somewhere new uncovered a bunch of implicit
assumptions baked-in about the environment, so it exposed a new set of issues
and bugs. This is fairly inevitable when it comes to low-level systems code,
and there's a lot of value in working through it. LogCabin is significantly
easier to run now than it was before, and it should be easier for the rest of
you to install on your systems, too.

---

Getting Started
---------------

At Scale, we've been working to integrate LogCabin into Scribe, the software
that runs their private cloud products. We needed LogCabin to be installable
and deployable as a normal system service with an RPM (Scale's software
distribution is currently based on RHEL 6). So, I added an option for LogCabin
to behave more [like a daemon](https://github.com/logcabin/logcabin/issues/65),
reparenting to init and writing to a log file instead of stderr. Others at
Scale wrote a basic init script and an RPC spec file, which we [intend to
merge](https://github.com/logcabin/logcabin/issues/74) into the upstream repo.

On the client side of things, I
[moved](https://github.com/logcabin/logcabin/commit/f8f3b7ec) the `Client.h`
header that clients need to include. Client code used to `#include
<Client/Client.h>`, which is fairly confusing; now it's `#include
<LogCabin/Client.h>`.

I also started removing the need for DNS in clients. Instead of requiring a DNS
name that resolves to multiple addresses, the `Cluster` constructor [now
accepts](https://github.com/logcabin/logcabin/commit/83733fe8) a
semicolon-delimited list of addresses and will randomly connect to hosts in
that list. Left to do are [simplifying the README and other
scripts](https://github.com/logcabin/logcabin/issues/63) to take advantage of
this, and finding a way for dynamic membership changes to work without DNS
(maybe we should expose a way for running clients to reset the list of hosts?).
For now, Scribe still uses a DNS hostname set up by `/etc/hosts`.

Client API
----------

As I was adding the first lines of code to write to LogCabin from Scribe, I
noticed that LogCabin had no way to do a [conditional
create](https://github.com/logcabin/logcabin/issues/59). In other words, you
could write to a key on the condition that it had a particular value, but you
couldn't write to it on the condition that it had no value. Now,
`Tree::setCondition(path, "")` will match not only "files" in the replicated
state machine with 0-length values but also files that don't exist at all. In
the future, we may want to extend the condition system to include matching on
hashes of files for large files, or maybe switch to using version numbers.

Internal Improvements
---------------------

I also fixed two crashes in the RPC system. One was a [race
condition](https://github.com/logcabin/logcabin/issues/70), in which a socket
that was disconnected and closed was still being used to attempt to send
outbound messages. An additional mutex protecting access to that file
descriptor fixed the problem.

The other bug in the RPC system was [harder to track
down](https://github.com/logcabin/logcabin/issues/66). This crash happened to
Nate when he reconfigured the cluster to include an address that was invalid,
so that DNS resolution failed. Instead of retrying periodically, the non-leader
servers would PANIC with messages like:

    1418256261.050477 RPC/Address.cc:188 in refresh() WARNING[2:Peer(1)]: Unknown error from getaddrinfo("192.168.51.30:61023 192.168.51.31:61023 192.168.51.32", "61023"): Temporary failure in name resolution
    1418256261.050639 RPC/MessageSocket.cc:292 in read() ERROR[2:evloop]: Error while reading from socket: Transport endpoint is not connected Exiting...

But the MessageSocket never should have been instantiated with an invalid
address! And strangely, I couldn't reproduce this problem on my laptop, only on
Scale's servers.

It turns out that `connect()` behaves incorrectly on Scale's servers. As far as
I understand from the POSIX standard, `connect(fd, NULL, 0)`, with a 0-length
sockaddr, should return -1 and set `errno` to `EINVAL`. That's what it does on
my laptop, and that's what it does on Scale's servers when running through
strace or valgrind. However, if I run that on Scale's servers as a normal
program, it returns 0, that everything is ok, and then barfs later that the
socket isn't connected! I couldn't find any other reference to this problem
after a quick web search, but I suspect its a glibc issue. I worked around it
by making sure not to call `connect()` with an empty sockaddr.

A couple additional improvements to the client library's internals:

- If a client ever issues a write request, the client library needs to open a
  session with the LogCabin cluster, and it'll periodically issue keep-alive
  RPCs to keep that session open. Unfortunately, if the cluster went down,
  these RPCs would [prevent clients from
  exiting](https://github.com/logcabin/logcabin/issues/71), as they'd retry
  their keep-alive RPCs forever. Fixing this required making that RPC
  cancellable, which caused a fair amount of code churn.
- Clients that couldn't connect to a cluster were actually very aggressively
  trying to reconnect, causing 100% CPU usage and probably wasting network
  bandwidth. They're now
  [rate-limited](https://github.com/logcabin/logcabin/commit/37a53ec9).

Travis CI
---------

[![Build Status](https://travis-ci.org/logcabin/logcabin.svg?branch=master)](https://travis-ci.org/logcabin/logcabin)

I also set up [Travis CI](https://travis-ci.org/logcabin/logcabin) to do
automated builds for LogCabin. This started with wanting the code-level
documentation (produced by [Doxygen](https://www.doxygen.nl/index.html) to be available on a
web server. It's a simple idea, but the documentation changes as the code
changes, so static hosting wouldn't quite work. On each commit, Travis CI will
now check out the new version of the code, build it, run the unit tests, and
build the documentation. Then, it'll push the docs to a [GitHub static
page](https://github.com/logcabin/logcabin.github.io), which GitHub then hosts
at [logcabin.github.io](https://logcabin.github.io).

Travis CI runs these automated builds on fairly puny and/or overloaded VMs. I'm
not blaming them (it's a free service), but this made some of the unit tests
fail intermittently. Unfortunately, a few of the unit tests are just
fundamentally sensitive to timing, like making sure that a condition variable
waits for about the right amount of time. I renamed such tests to include
"TimingSensitive" in the name, and, using a [gtest
filter](https://github.com/google/googletest/blob/master/googletest/docs/advanced.md#running-a-subset-of-the-tests),
Travis CI will no longer fail the build for such tests.

Next
----

Next time I'll discuss ongoing work to [add timeouts to LogCabin's client
library](https://github.com/logcabin/logcabin/issues/69), including a battle
against libstdc++ 4.4's [broken support for clocks and
time](https://github.com/logcabin/logcabin/issues/24). Thanks to [Scale
Computing](https://www.scalecomputing.com) for supporting this work.

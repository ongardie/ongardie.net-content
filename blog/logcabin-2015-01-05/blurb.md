This is the second in a series of blog posts detailing the ongoing development
of [LogCabin](https://github.com/logcabin/logcabin). This entry describes the
battle of adding timeouts to the client library API. Timeouts are useful for
implementing leases in client applications. For example, a client might want to
assert its lease but give up after few seconds, and in case of a timeout, it
might need to crash or stop other processes from doing things that may no
longer be safe.

Not Quite C++11
---------------

C++11 specifies a bunch of new time-related classes, including
[steady_clock](http://en.cppreference.com/w/cpp/chrono/steady_clock),
[time_point](http://en.cppreference.com/w/cpp/chrono/time_point), and a
[condition_variable](http://en.cppreference.com/w/cpp/thread/condition_variable/wait_until)
that will stop waiting after a given timeout. Unfortunately, libstdc++ doesn't
implement those very well until around version 4.9. This is a problem for
LogCabin, which aims to run on all versions of gcc from 4.4 through 4.9 (the
still-popular RHEL 6 distro comes with gcc 4.4). There's two basic
[issues](https://github.com/logcabin/logcabin/issues/24) with libstdc++'s
implementation in 4.4: one is the clocks, and the other is the condition
variable.

#### Clocks

The monotonic clock in 4.4 is just a typedef to the system clock, so it is
prone to jumps in time caused by, e.g., NTP. Moreover, up until 4.8, the
now-called ``std::chrono::steady_clock`` and ``std::chrono::system_clock`` are
rounded to the nearest microsecond for default libstdc++ compiles. LogCabin
doesn't strictly need nanosecond granularity, but it sure makes life easier<sup>[1](#logcabin-2015-01-05-footnote-1)</sup>.
For example, with nanosecond granularity you don't have to worry so much about
``<`` vs ``<=`` (especially in unit tests), since every clock reading is highly
likely to be different from the previous.

Ultimately, I implemented versions of the monotonic and system clocks that
LogCabin can rely on, which call ``clock_gettime()``. LogCabin will use these
when it's running on libstdc++ versions below 4.8.

#### Condition Variable

Even with the working clocks, I was unable to get ``std::condition_variable``
to work reliably on all libstdc++ versions. Thus, I rewrote LogCabin's
[ConditionVariable wrapper
class](https://github.com/logcabin/logcabin/blob/7be0672c/Core/ConditionVariable.h)
to use pthreads condition variables instead. The key advantage here is that
it's easy to see exactly what's happening with respect to timeouts, and, unlike
before, the class reliably passes its unit tests.

One silly thing is that the pthreads condition variables want a clock per
condition variable, whereas C++11 allows you to use a different clock each time
you wait with a timeout. LogCabin's condition variable always uses the
monotonic clock, so if you pass in a system clock time to wait until, it will
wait for the number of nanoseconds between now and then. This might be a little
odd for users that actually want the system clock; for example, if you wanted
to wait until midnight 6 hours from now, and NTP jumped forward by 2 hours,
you'd wake up at 2am. But I think that use case is rare, and it doesn't occur
in LogCabin as of now.

Client API
----------

Once I had reliable clocks and condition variables, I started to [implement
timeouts](https://github.com/logcabin/logcabin/issues/69) in the RPC system and
to expose them in the client API. There are up to three potentially
time-consuming things that happen in the client library:

- Resolving a DNS name,
- Initiating a TCP connection, and
- Waiting for an RPC response.

The second and third ones were relatively straightforward, though they affected
a lot of functions where timeout values had to be pushed down and new error
codes sent back up. Waiting for an RPC response with a timeout just required
adding a timeout to a condition variable wait. Using ``connect()`` with a
timeout requires putting the socket in non-blocking mode, calling ``connect()``
on it, and using poll/select/epoll with a timeout to learn when it's ready (see
the man page for ``connect()`` under ``EINPROGRESS``).

Unfortunately, resolving a DNS name with a timeout appears to be difficult. I
started down the road of using ``getaddrinfo_a()``, only to learn that its
current implementation leaves much to be desired. It's implemented as a thread
pool, where workers call the synchronous ``getaddrinfo()`` to do DNS
resolution, and they can't be interrupted from this. Thus, there's no real way
to cancel a DNS request once it's started, say upon a timeout, and it seems
that the memory for the request must be kept valid through its completion. I
now appreciate why libevent includes [its own DNS
resolver](http://www.wangafu.net/~nickm/libevent-2.0/doxygen/html/dns_8h.html),
but I wasn't ready to go down that path. I've left this as [future
work](https://github.com/logcabin/logcabin/issues/75). For now, DNS resolution
will continue to be bound by the system timeout setting, not those specified by
LogCabin clients; if you're relying on timeouts, it's a good idea to specify IP
addresses or use a local ``/etc/hosts`` file.


Next
----

I can't say for certain what's coming next. One idea is to start working on
administrative tools to introspect the LogCabin state and/or extract metrics
from the LogCabin servers. We'll see. Thanks to [Scale
Computing](http://www.scalecomputing.com) for supporting this work.

----

1. <a id="logcabin-2015-01-05-footnote-1"></a>Phil White warns that two time
readings with nanosecond granularity may still return the same value on a
virtual machine. See [KVM timekeeping
docs](http://www.mjmwired.net/kernel/Documentation/kvm/timekeeping.txt),
section 4, for related reading.

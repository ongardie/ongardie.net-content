LogCabin 1.0 is out! This is the first stable release of the
[LogCabin](https://github.com/logcabin/logcabin) coordination service, which
includes a C++ implementation of the
[Raft consensus algorithm](https://raft.github.io). If you're new
to these, I recently spoke about Raft and a little about LogCabin at the
[Sourcegraph Hacker
Meetup](http://www.meetup.com/Sourcegraph-Hacker-Meetup/events/221199291/) in
San Francisco; watch the [video](https://youtu.be/2dfSOFqOhOU) for a visual
walk-through of how Raft works.

---

<center>
[![Sourcegraph talk](${VAR_URL_PREFIX}/blog/logcabin-1.0/sourcegraph.jpg)](https://youtu.be/2dfSOFqOhOU)
</center>

I initially developed LogCabin at Stanford University while co-designing the
[Raft consensus algorithm](https://raft.github.io) with my advisor,
[John Ousterhout](https://web.stanford.edu/~ouster/). LogCabin was the system
we used to put Raft into code, which in turn influenced the design of Raft and
the way we described it. By the time I graduated, LogCabin had a fairly mature
Raft implementation but needed more work around the edges. Since then, I've
been working with [Scale Computing](http://www.scalecomputing.com/) to turn
LogCabin into a production system. We've improved its usability, updated how it
writes to disk, added a few features such as client-side timeouts, and
discovered and fixed a few bugs (for more details, see the [series of blog
posts](${URL_PREFIX}/blog/+logcabin/)). The latest push added rolling
upgrades, something we wanted to have in place right from the first release.

Today, we're ready to release 1.0 to the world, and we invite others to give it
a spin. LogCabin is written in C++11 and is released under the permissive ISC
license.

LogCabin 1.0 also has a logo. A serious project needs a logo, after all. It
lets people know they can place their trust in LogCabin.

<div style="border: 1px solid #ccc">
<center>
<blockquote class="twitter-tweet" lang="en"><p lang="tl" dir="ltr">The making of the new LogCabin logo. Analog to digital to analog to digital. <a href="http://t.co/eJXGyGMRRV">http://t.co/eJXGyGMRRV</a> <a href="http://t.co/m2HQtvYnoo">pic.twitter.com/m2HQtvYnoo</a></p>&mdash; Diego Ongaro (@ongardie) <a href="https://twitter.com/ongardie/status/586396192835153921">April 10, 2015</a></blockquote>
<script async src="//platform.twitter.com/widgets.js" charset="utf-8"></script>
</center>
</div>

Included with 1.0
-----------------

At a high level, LogCabin looks similar to
[Chubby](http://research.google.com/archive/chubby.html),
[ZooKeeper](https://zookeeper.apache.org/), and
[etcd](https://github.com/coreos/etcd). It's a network service providing a
small amount of consistent storage. You can set keys to values in a
hierarchical tree, fetch keys, and list the keys in a particular "directory".
It supports compare-and-swap style operations, such as set key *x* to value *y*
but only if its current value is *z* (actually, you can add a condition to any
operation, and it can require that a distinct key have the given value). Every
operation in LogCabin is linearizable, meaning that the effect of a write is
immediately visible to all future reads, and writes appear to happen atomically
and instantaneously.

The above is about all you need for simple uses of a consensus service. There
are several other features that we'd like to add in the future; these are
outlined below in "Next for LogCabin". Our philosophy is to first get a
small but useful system in place with a solid foundation, and looking forward
from 1.0, we can start thinking about building out more user-facing features.

LogCabin 1.0 ships with a C++ client library used to access a LogCabin cluster,
a few administrative tools, and a command-line interface to access the LogCabin
data. See the [release
notes](https://github.com/logcabin/logcabin/blob/master/RELEASES.md) for
exactly what makes up the stable API.


The 1.0 label
-------------

In LogCabin's case, 1.0 means that I think it's ready to be deployed to
production. You'll still have to do your due diligence in testing, of course. I
think it's stable enough to roll out for production use, and there will be
upgrade paths for any data you put into LogCabin moving forwards. I've spent
the last few weeks working on internal versioning protocols so that LogCabin
will be able to do rolling upgrades for most releases moving forwards. Even
if it couldn't (perhaps across some major version bumps), shutting down and
restarting a LogCabin cluster with moderate amounts of data only takes a couple
of seconds.


Next for LogCabin
-----------------

While we think 1.0 is useful as is and hope others will try it, there is still
plenty we'd like to do. Several higher-level client-facing features are on the
[wishlist](https://github.com/logcabin/logcabin/labels/wishlist), such as a
notification mechanism so that clients can be notified when keys change,
ephemeral keys that go away when client sessions are closed, and transactions
allowing clients to change multiple keys atomically. We'd also like to better
measure and continue to improve LogCabin's performance. If you're interested in
helping out with any of this, please get in touch!

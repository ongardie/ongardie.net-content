This post surveys the libraries available in Node.js for LevelDB, shows that
support for transactions is missing, and lays out a path to get there. In
short, we need the Node bindings for LevelDB to expose snapshots, then we can
build transactions with snapshot isolation on top without much trouble.

---

## Motivation

I've been dabbling in web development recently, and as part of that, I'm trying
to access [LevelDB](https://github.com/google/leveldb) from
[Node.js](https://nodejs.org/en/).

LevelDB is a C++ library that provides a key-value interface to local storage,
implemented as a [log-structured
merge-tree](https://en.wikipedia.org/wiki/Log-structured_merge-tree). Its
[API](https://github.com/google/leveldb/blob/master/doc/index.md) contains:

- Basic key-value operations: `get`, `put`, and `delete`.
- Iterators, which can be used to return all keys within a particular range.
- Snapshots, which are point-in-time, copy-on-write, read-only views of the
  database. A normal `get` will return the latest value written to the
  database, while a snapshot `get` will return the value at the time the
  snapshot was taken.
- Atomic updates (`WriteBatch`), which allow the application to apply multiple
  `put` and `delete` operations to the database atomically. Either all of these
  will succeed, or none will.

Note that LevelDB does not implement transactions directly, but snapshots and
atomic updates can be leveraged to implement these above LevelDB, as I'll
describe below.

I like the idea of using LevelDB for simple Node.js projects, since it's
lightweight, really easy to operate (there's no separate database daemon), and
fairly easy to understand what's happening under the hood. That said, I do also
want transactions for things like adding a label to an item, while atomically
adding a backreference to the item from the label.

I should take a moment to say that most projects needing transactional
databases should probably just use [PostgreSQL](https://www.postgresql.org) or
[SQLite](https://sqlite.org/index.html), two excellent open source relational databases.
Those are what I'd use if I had to actually get something done. This is a side
project and a learning experience for me, so I'm intentionally exploring a path
less traveled.

## Node's LevelDB Libraries

One of the hardest things when starting out with JavaScript in general is
figuring out which libraries to use. I'll summarize what I found for LevelDB,
in hopes that some of you will have an easier time getting oriented.

To access LevelDB, I started out with the
[LevelUP](https://github.com/Level/levelup) library. LevelUP is written in
JavaScript and relies on the C++
[LevelDOWN](https://github.com/Level/leveldown) library to call into
LevelDB. Over time, LevelUP has evolved to have various backends, but I'm
just interested in using LevelDB for now.

LevelUP uses callbacks instead of
[promises](https://web.dev/promises/), which makes
it a bit ugly to use directly. Fortunately,
[level-promise](https://github.com/nathan7/level-promise/) wraps LevelUP to
expose a promise-based API. It adapts LevelUP in an automated way, based on a
description of the API from
[level-manifest](https://github.com/dominictarr/level-manifest).

None of these libraries currently implements transactions. When I started this
project, LevelDOWN did not expose snapshots in the API either, which would be
useful for implementing transactions.
[LevelUP community issue #47](https://github.com/Level/community/issues/47) contains
the relevant discussion for exposing snapshots, and I've started a patch to add
them in [LevelDown PR #152](https://github.com/Level/leveldown/pull/152).

## level-transaction

As I was writing this post, I came across a project called
[level-transaction](https://github.com/eugeneware/level-transaction), which
aims to implement transactions on top of LevelDB in Node.js. That's my goal
too, but level-transaction's approach does not look promising, and
I wouldn't recommend using it in its current form. To be fair,
level-transaction includes a clear disclaimer:

> NB: This module is still under active development and is not to be used in
> production

The rest of this section explores level-transaction's approach and argues
against it. You should feel free to skip this part.

level-transaction doesn't use LevelDB snapshots at all, and it's probably
aiming for
serializability rather than snapshot isolation. It might be an attempt at
[two-phase locking](https://en.wikipedia.org/wiki/Two-phase_locking), but it's
hard to tell. I'm certain that one could implement transactions with
serializability using two-phase locking, and the code would take a similar
shape, but it doesn't seem like that's quite what's happening here.

From my understanding of the current code, level-transaction works as follows.

The primary data structure is `txKeys`, the set of keys being modified by any
active transaction.

To execute a `get` operation, level-transaction:

1. Waits until the key being read is not in `txKeys`. By wait, I mean spin with
   [`setImmediate()`](https://developer.mozilla.org/en-US/docs/Web/API/Window/setImmediate)
   (JavaScript uses a single-threaded run-to-completion [event
   loop](https://developer.mozilla.org/en-US/docs/Web/JavaScript/EventLoop) with
   asynchronous I/O for concurrency).
2. Then executes a `get` against the current database.

To execute update operations (`put`, `delete`, and batches), level-transaction:

1. Waits until the key is not in `txKeys`.
2. Adds the key to `txKeys`.
3. Fetches the existing value of the key, and uses this to store "rollback"
   information, which can be used to restore the key to its previous version
   later, if needed.
4. Executes the `put`, `delete`, or batch against the current database. Returns
   if there's an error.
5. Sets a timer to later execute the rollback operation and clear `txKeys`
   entirely.
6. Returns the application a commit function, which will remove the rollback
   timer and clear `txKeys` entirely, and an abort function, which will
   execute the rollback operation and clear `txKeys` entirely.

I've written the above description of update operations in terms of one key for
simplicity, but batch operations do contain multiple keys.

There's at least one fundamental problem with this approach: what happens if
the application crashes? Uncommitted updates are written to the database right
away. Even if their values aren't exposed to concurrent transactions, they will
remain in the database in the event of a crash. That's probably a showstopper.

There are several smaller issues too:

- It doesn't make sense to clear `txKeys` entirely, since other transactions
  may have added keys to that set. A transaction should only remove the keys
  that it has contributed.
- Commit and abort should apply to entire transactions, not to single
  operations. A transaction probably needs to be represented by an object.
- Spinning with `setImmediate()` is wasteful in terms of energy usage. It'd be
  better for these to block nicely on changes to `txKeys`.

The level-transaction author is probably aware of some of these problems
already, given its disclaimer, and I'm not trying to pick on them. My point is
that transactions for LevelDB in Node.js are not a solved problem, and the
current level-transaction approach is probably not the right one.

## A Path Forward for LevelDB Transactions in Node.js

If we can get snapshots exposed in the LevelDOWN API
([PR #152](https://github.com/Level/leveldown/pull/152)), then we'll have
both atomic updates and snapshot primitives available from Node.js. These lend
themselves well to implementing transactions with [snapshot
isolation](https://en.wikipedia.org/wiki/Snapshot_isolation).
Snapshot isolation is a relaxed form of concurrency control relative to
[serializability](https://en.wikipedia.org/wiki/Serializability),
but it is still fairly strong, popular, and not too difficult to use correctly
(I think).

People often choose snapshot isolation over serializability for high
performance or concurrency, but in this case, I just want reasonable
performance and a simple implementation. Implementing snapshot isolation is
simple in this case precisely because LevelDB does the heavy lifting by
providing snapshots and atomic updates.

Let's say we had these primitives and wanted to implement transactions in a
shiny new library, which I'll call txlib. The world needs more JavaScript
libraries, after all.

To start a transaction, txlib would create a snapshot on which the
transaction's reads (`get` and iterator operations) would execute. The
transaction's `put` and `delete` operations would be buffered in memory. To
commit a transaction, txlib would submit an atomic update to LevelDB with all
of the the buffered updates.

There are two remaining issues that must be resolved to arrive at snapshot
isolation.

First, buffering up `put` and `delete` operations in a transaction can affect
the result of that transaction's `get` and iterator operations. For example,
the `get` should return the value `B` here, even though at the beginning of the
transaction, `key1` had the value `A`:

    put key1 A
    begin transaction
    put key1 B
    get key1
    ...
    commit

This behavior should be straightforward to implement in txlib by consulting the
buffered updates on each `get` and iterator operation, with those taking
precedence over the results from the database snapshot.

Second, if two overlapping transactions both update the same key (a
[write-write
conflict](https://en.wikipedia.org/wiki/Write%E2%80%93write_conflict)), at
least one of them must abort in snapshot isolation. This prevents one
transaction from blindly overwriting the other's updates. For example:

    transaction 1:          transaction 2:
    --------------          --------------
    begin transaction
                            begin transaction
    bal1 = get account1
                            bal1 = get account1
    bal2 = get account2
                            bal3 = get account3
    bal1 -= 50
                            bal1 -= 50
    bal2 += 50
                            bal3 += 50
    put account1 bal1
                            put account1 bal1
    put account2 bal2
                            put account3 bal3
    commit
                            commit

<!-- prettier-ignore -->
If we suppose every account started with $100 and transaction 2 commits after
transaction 1, we'd end up with `account1` having $50, `account2` and
`account3` having $150 each, and some accountant yelling at us about the $50
discrepancy. Instead, what we'd like is for one of these transactions to abort
and start over, rather than producing $50 out of thin air.

According to Cahill, et al (cited below):

> Implementations of SI [snapshot isolation] usually prevent a transaction from
> modifying an item if a concurrent transaction has already modified it.

This can be done by blocking one transaction, as in classic database engines,
or it can be done by aborting transactions when the possibility of a conflict
is detected, as I'll describe next.

Here's what an implementation might look like. txlib would track the last
transaction to update (`put` or `delete`) each key in memory, using a key to
transaction map called `lastUpdate`.

When a `put` or `delete` occurred within a transaction, txlib would:

- Look up `lastUpdate[key]`. If found and that transaction had not committed by
  the time the current transaction started, abort the current transaction.
- Otherwise, set `lastUpdate[key]` to the current transaction.
- Buffer up the update to be issued later in an atomic batch.

In the above example, transaction 2 would be aborted as soon as it called
`put account1 bal1`, since transaction 1 would have already touched the key in
the `lastUpdate` map. This isn't quite optimal: if transaction 1 happened to
abort, transaction 2 would have aborted unnecessarily. However, this is
probably uncommon, and the simplicity of the approach probably outweighs any
performance concerns.

Note that normal `put` and `delete` operations (those outside a transaction)
would have to update the `lastUpdate` map as well, so that transactions would
abort accordingly.

Keys in the `lastUpdate` map would also have to be cleaned up eventually. If
`OAT` is the oldest active transaction (the one with the earliest start time
that hasn't yet committed or aborted), `lastUpdate[k]` can be removed if its
commit time is before `OAT`'s start time. At that point, every active
transaction sees the effects of that update in its snapshot.

In case you're wondering, the same snapshot primitive can also be used to
provide serializability instead of snapshot isolation. This might be desired to
prevent what are called [write skew
anomalies](https://en.wikipedia.org/wiki/Snapshot_isolation), which snapshot
isolation allows. See
"Serializable Isolation for Snapshot Databases"
by M. Cahill, U. Roehm, and A. Fekete
([acm](https://dl.acm.org/doi/10.1145/1376616.1376690)
[pdf](https://courses.cs.washington.edu/courses/cse444/08au/544M/READING-LIST/fekete-sigmod2008.pdf)
[thesis](https://ses.library.usyd.edu.au/bitstream/handle/2123/5353/michael-cahill-2009-thesis.pdf;jsessionid=751DF91C40440FA7F7ADDA484537CDF7?sequence=1))
for one approach. I discussed snapshot isolation above since it's simpler to
implement and sufficient for many applications.

## Conclusion

To reiterate, you should probably just use PostgreSQL or SQLite. This is what
happens when a systems PhD dabbles in web development. I want to have
transactions on LevelDB in Node.js as a lightweight option, and I'm doing this
as a learning experience.

I must be one of a very small group of people that
want transactions on LevelDB in Node, and that suggests that maybe I'm doing it
wrong. Maybe I shouldn't be using LevelDB in Node for something transactional.
Maybe [RocksDB](https://rocksdb.org/) or another LevelDB fork has better
support. Maybe Node supports database servers better than database libraries
due to its event-driven concurrency model. It's hard for me to tell, but I
think what I'm trying to do is rational.

Hopefully we can get snapshot support into LevelDOWN, then add yet another
library to the mix to implement transactions using them. I think it'll make for
a nice lightweight alternative to the relational databases when you want
transactions but don't need SQL. It'd also serve as a platform for prototyping
various forms of concurrency control, which might be interesting for people to
toy with.

---

<small>
Thanks to <a href="https://twitter.com/rstutsman">Ryan Stutsman</a> for his
feedback on an earlier draft of this post. While he didn't quite endorse it,
he did help make it much clearer.
</small>

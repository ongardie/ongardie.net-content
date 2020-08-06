![Ousterhout placing academic hood on Ongaro](${VAR_URL_PREFIX}/blog/phd/hooding.jpg)

Well, I spent the last five years getting my Ph.D. in Stanford's Computer
Science department. I won't do that justice here, but I'll fill in the story
briefly so that subsequent posts make sense. I was part of
[Professor John Ousterhout](https://www.stanford.edu/~ouster/)'s group,
which is primarily focused on
[RAMCloud](https://web.stanford.edu/~ouster/cgi-bin/projects.php#ramcloud),
a large-scale in-memory distributed storage system.

---

I started working on RAMCloud soon after joining Stanford
([Ryan](https://twitter.com/rstutsman/) made the first commit the month after I
started), and I worked on various low-level parts of the system and master
recovery. Eventually, I began to look into eliminating the single point of
failure that RAMCloud's coordinator once was, and I became interested in using
consensus to solve the problem. (To be fair, I never fixed the problem in
RAMCloud; [Ankita](https://twitter.com/ankitaak) and John deserve the credit
for that.)

I wasn't impressed with the existing consensus-based systems, so I started
learning about [Paxos](https://en.wikipedia.org/wiki/Paxos_(computer_science)),
the algorithm that's nearly synonymous with consensus.
I struggled through how to build a complete system using Multi-Paxos, and
meanwhile, John questioned whether Paxos even had the right approach. He kept
pushing on the idea of *understandability*, to find the solution that's the
easiest for someone else to understand. He asked: what's the advantage to
agreeing on log entries (slots) out of order if they then have to be applied in
order? If the game was understandability, I just couldn't defend Paxos on this
question.

Eventually, John went off during a weekend and proposed ALPO, the first version
of the algorithm that matured into the [Raft](https://raft.github.io)
consensus algorithm. Raft turned into my thesis topic, and I developed an
implementation of it in C++ called
[LogCabin](https://github.com/logcabin/logcabin). Meanwhile, Raft gained
significant traction in industry, being implemented in a variety of systems in
many different languages, and it's also been taught in a few distributed
systems courses already.

Early on in RAMCloud's history, in April 2010, we held the RAMCloud
[Design Review](https://ramcloud.atlassian.net/wiki/display/RAM/Design+Review):
a group of friendly people from academia and industry came over to
listen to our ideas for RAMCloud and give us feedback. As part of this
feedback, we were advised to use [ZooKeeper](https://zookeeper.apache.org/) for
the coordinator (which RAMCloud eventually did use) and were warned of the
"danger in believing one should do Paxos from scratch or optimize it". I think
that was pretty solid advice when interpreted as: if you start on this path, it
will consume your life. Sometimes, though, getting side-tracked to work on an
important problem is the right thing, especially in academia.

Now that I've graduated, I plan to continue to stay involved with Raft and help
support the Raft community where I can. I've recently
[announced](https://groups.google.com/d/msg/raft-dev/Dbb2TB0dgSU/fEtmYOXi2IIJ)
my plans to continue developing LogCabin with support from
[Scale Computing](https://www.scalecomputing.com/), and I'm excited to see
LogCabin mature into a stable and production-quality system. I plan to post
articles about this development here on a regular basis
([RSS](${URL_PREFIX}/blog/rss.xml)).

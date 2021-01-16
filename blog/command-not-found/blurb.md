On Debian/Ubuntu, `command-not-found` tells you what package to install when
you try to run a program you don't have. I find this helpful, but it takes a
long time to maintain its index for lookups. This post tells the meandering
story of how I first optimized `command-not-found`, then replaced it with a
script that doesn't use an index at all.

---

## update-command-not-found is slow

I noticed recently that `apt update` stalls on my computer after fetching new
data:

```
Get:139 http://ftp.us.debian.org/debian unstable/non-free amd64 Contents (deb) T-2021-01-15-0800.20-F-2021-01-14-0800.15.pdiff [2,707 B]
Fetched 1,504 kB in 39s (38.5 kB/s)
```
...stall for about 15 seconds...
```
Reading package lists... Done
Building dependency tree
Reading state information... Done
10 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

I found the culprit to be `update-command-not-found` from the
[command-not-found](https://packages.debian.org/command-not-found) package.
That package provides a useful error message when you attempt to run a command
you don't have installed. It searches through the APT cache for Debian (or
Ubuntu or whatever) packages that would install an executable with the same
name. Here's an example:

```
~$ python2

Command 'python2' not found, but can be installed with:

sudo apt install python2-minimal
```

To make this search efficient, `update-command-not-found` builds a lookup table
when `apt update` runs. This table is stored in in
`/var/lib/command-not-found/`. Unfortunately, building this lookup table and
maintaining it is slow, at least for me.

The code is written in Python. It's maintained
[upstream by Ubuntu](https://code.launchpad.net/~ubuntu-core-dev/command-not-found/ubuntu)
but is [modified by Debian](https://salsa.debian.org/jak/command-not-found) (in
a reversal from their typical roles). The relevant code for me is all from
Debian's changes that read through package Contents files. The changes are kept
in a series of patches inside the `debian/patches/` directory
(using [quilt](https://www.debian.org/doc/manuals/maint-guide/modify.en.html)),
and the relevant patch is
[0003-cnf-update-db-Add-support-for-Contents-files.patch](https://salsa.debian.org/jak/command-not-found/-/blob/e94d7236/debian/patches/0003-cnf-update-db-Add-support-for-Contents-files.patch).
My computer seems to spend all its time in the method
`_parse_single_contents_file`.

Upon profiling `update-command-not-found` with
[pyinstrument](https://github.com/joerick/pyinstrument) and plenty of
trial-and- error, I was able to speed it up by about 40% (again, on my
computer) with a minor change. The patch itself is quite small:

```diff
     def _parse_single_contents_file(self, con, f, fp):
         # read header
         suite=None      # FIXME
+        pattern = re.compile(b'usr/sbin|usr/bin|sbin|bin')

         for l in fp:
-            l = l.decode("utf-8")
-            if not (l.startswith('usr/sbin') or l.startswith('usr/bin') or
-                    l.startswith('bin') or l.startswith('sbin')):
+            if not pattern.match(l):
                 continue
+            l = l.decode("utf-8")
             try:
                 command, pkgnames = l.split(None, 1)
             except ValueError:
```

Each line `l` in the file stream `fp` comes from a Contents file, which looks
like this:

```
usr/bin/cvs                       vcs/cvs
usr/bin/parallel                  utils/moreutils,utils/parallel
usr/share/cvs/contrib/README      vcs/cvs
```

The contents files are kept in `/var/lib/apt/lists/` and have names like
`ftp.us.debian.org_debian_dists_unstable_non-free_Contents-amd64.lz4`. They can
be decompressed with `lz4 -d < FILE` or
`/usr/lib/apt/apt-helper cat-file FILE`.

Before, the code would check if each line started with four separate strings. I
optimized that to use a pre-compiled regular expression, which is more
efficient. I also deferred decoding the line from an array of bytes into a
Unicode string. Many lines don't have the ASCII prefixes we're looking for, so
we don't need to spend time decoding those.

I submitted this change to Debian in
[bug #980076](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=980076).

That improvement got the updates down from about 16 seconds to about 10 seconds
for me. I looked for more opportunities to speed up `update-command-not-found`,
but nothing major jumped out at me. One approach would be to parallelize the
work so multiple files can be searched at once. Another would be to rewrite the
tool in a faster language; there's lots of discussion about this in
[Debian bug #881692](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=881692).

## Skip the index

Then I started wondering whether the index that `update-command-not-found`
builds is even worth building. If I'm typing a command in my terminal and it
doesn't exist, I'm OK with waiting a second or so to be told what packages to
install. Can we search the Contents files quickly enough to make this
interactive without an index?

There's a package called `apt-file` that `command-not-found` depends on and
does just this. It's written in Perl. This is equivalent to what
`update-command-not-found` does:

```sh
apt-file search --regex "^(usr/)?s?bin/$PACKAGE$"
```

It's slower than I'd like (times shown are with warm caches):

```sh
~$ /bin/time -p apt-file search --regex "^(usr/)?s?bin/cvs$"
cvs: /usr/bin/cvs
real 3.35
user 4.44
sys 1.08
```

The [man page](https://manpages.debian.org/buster/apt-file/apt-file.1.en.html)
warns users that the `--regexp` option is slow. That turns out to be true. This
next invocation is equivalent but significantly faster:

```sh
~$ /bin/time -p apt-file search "bin/cvs" | grep -P ": /(usr/)?s?bin/cvs$"
cvs: /usr/bin/cvs
real 1.22
user 1.57
sys 0.52
```

Honestly, that's fast enough, and I probably should have stopped there.
Spoiler: I didn't.

## Parallel search

Searching through multiple Contents files is trivially parallelizable, or at
least it should be. I don't know Perl, so I didn't want to make major changes
to `apt-file`.

What I wanted to do was a parallel execution of `apt-helper cat-file` piped
into `grep`. In shell scripts, you can do this using tools like
[GNU parallel](https://manpages.debian.org/testing/parallel/parallel.1.en.html)
or the conflicting program from
[moreutils](https://manpages.debian.org/testing/moreutils/parallel.1.en.html).
I came across this 2012
[rant on GNU parallel](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=597050#75)
by Joey Hess, the developer of
[moreutils](https://joeyh.name/code/moreutils/), and that's enough reason for
me to avoid it. The whole mess of not knowing which parallel might be installed
at `/usr/bin/parallel`, if any, was also off-putting.

Instead, I switched to using [ripgrep](https://github.com/BurntSushi/ripgrep).
ripgrep (`rg`) is parallel by default. It can decode compressed files with the
`-z` flag if `lz4` and similar programs are available.

This initial test was promising:

```sh
~$ /bin/time -p rg -z --no-filename "^(usr/)?s?bin/cvs\s" /var/lib/apt/lists/*Contents* | cat
usr/bin/cvs                   vcs/cvs
usr/bin/cvs                   vcs/cvs
usr/bin/cvs                   vcs/cvs
usr/bin/cvs                   vcs/cvs
usr/bin/cvs                   vcs/cvs
usr/bin/cvs                   vcs/cvs
real 0.39
user 1.42
sys 2.12
```

The pipe into `cat` is there to disable ripgrep's "nice" output for interactive
terminals.

So, this is definitely fast enough for interactive use. Even after I [drop my
caches](https://linux-mm.org/Drop_Caches), the same command only takes about
0.46 seconds on this machine.

My actual script, which you can find at the end of this post, has some more
bells and whistles:

- It falls back to a regular `grep` when `rg` or `lz4` are unavailable.
- It doesn't scan through the small files in `/var/lib/apt/lists/` with
  extension `.diff_Index`.

## Extracting the package names

The next challenge was formatting the data. If you remember from the earlier
example, some of the lines in the Contents files have a comma-separated list of
packages. I don't know of a great way to deal with that in shell script. I
ended up with this:

```sh
sed 's/^.* +//; s/,/\n/g; s/^.*\///'
```

The input looks like:

```
usr/bin/parallel             utils/moreutils,utils/parallel
```

The first regular expression strips out the path, leaving:

```
utils/moreutils,utils/parallel
```

The second regular expression breaks it into lines by comma, leaving:

```
utils/moreutils
utils/parallel
```

The third regular expression strips off the section names, leaving:

```
moreutils
parallel
```

Finally, that gets piped through `sort -u` to remove the duplicates from
multiple architectures or distributions.

## Printing relevant information

I could just print the package names and call it a day, but it's helpful to
print more information. The best way I know to do this is with `apt search`:

```
~$ apt search --names-only '^(moreutils|parallel)$'
Sorting... Done
Full Text Search... Done
moreutils/stable 0.62-1 amd64
  additional Unix utilities

parallel/stable,stable,testing,testing,unstable,unstable,now 20161222-1.1 all
  build and execute command lines from standard input in parallel
```

Sadly, this takes about 1 second, but I think it's valuable enough to be worth
the delay.

You're not really supposed to use `apt` in a script like this because its
output may change. I'm not really bothered by that, though, since my script is
intended for human consumption. The
[apt man page](https://manpages.debian.org/buster/apt/apt.8.en.html)
says to use
[`apt-cache`](https://manpages.debian.org/buster/apt/apt-cache.8.en.html)
instead. However, I don't see a way to get `apt-cache` to format the results in
a similar way.

Building that regular expression from the list of packages is also not obvious
in a shell script. I ended up with this ugly thing:

```sh
PACKAGES_DISJUNCTION=$(echo $PACKAGES | sed 's/ /|/g')
apt search --names-only "^($PACKAGES_DISJUNCTION)$"
```

## Putting it all together

I've assembled all this into a script called
[`apt-binary`](https://github.com/ongardie/configs/blob/main/bin/apt-binary)
in my configs repo, along with how to enable it for
[bash](https://github.com/ongardie/configs/blob/main/.bashrc) and
[zsh](https://github.com/ongardie/configs/blob/main/.zshrc)
(look for the calls to `apt-binary` there).

If you're removing `command-not-found` from your system, use
`apt purge command-not-found` to get rid of its index, too.

I hope this was useful or that you learned a trick or two. I found it to be a
frustrating exercise. I'm a professional software engineer that's comfortable
with several programming languages and different models for parallel
programming, yet for "simple" scripts like this, I'm sort of forced into
ancient UNIX tooling. In this environment, simple parallelism problems and
simple string manipulation can actually be pretty difficult. I'd normally use
Python for a language that's universally available with no setup, but it's not
well-suited to parallel or high-performance code. Go or Rust would have been
better choices, but they might not be set up everywhere. I think I settled on
an OK compromise here with `ripgrep` falling back to `grep` and a bunch of
regular expressions; I just feel like this should have been easier.

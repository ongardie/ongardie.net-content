The code for this website has been running without any major updates since 2009.
Back then, I wrote it as a Python 2 program using FastCGI, served originally by
[lighttpd](https://www.lighttpd.net/) and more recently by
[Caddy](https://caddyserver.com/).

---

I recently overhauled the code to run as a static site generator. This makes it
easier to run locally, feels better from a security perspective, and actually
simplifies the code in a few ways:

 - When serving individual requests, you need to figure out what page the
   request is asking for. With generating an entire site, you just loop through
   all the possible pages.
 - When serving individual requests, you need to load in only the relevant data
   for those requests. When generating an entire site, you can just load the
   input data once at startup.
 - When serving individual requests, you need to recover gracefully from errors.
   When generating an entire site, you can just let any exceptions propogate to
   crashing the program and have the user fix the problem and rerun.

One thing I gave up in switching to a static site generator was the page trail.
Before, the history of where you've been on this site was tracked with a session
cookie and displayed just under the title bar. I somehow felt that was an
important feature in the early 2000s, but that sort of navigation is better
suited to browser history today.

On a related note, I used to host the code for this website with a local
[cgit](https://git.zx2c4.com/cgit/about/) instance. I've turned that off and
moved the code to a [GitHub repo](https://github.com/ongardie/website-gen)
instead. If you're curious, You can look through the history of that repo to see
what's changed.

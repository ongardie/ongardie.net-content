<img src="${VAR_URL_PREFIX}/blog/python-builtins/python-logo.png" alt="Python logo" style="float:right" />

So, I just realized that I re-implemented two built-in Python functions on a
small project I'm working on for [ETSZONE](https://www.etszone.com). I just
didn't know that these existed, so I'm writing about them here in case you've
overlooked them too.

---

## sorted

[sorted](https://docs.python.org/3/library/functions.html#sorted) is useful if
you want to sort a copy of a list. Use `sorted()` instead of copying the list
and then using `list.sort()`.

This was my re-implementation (and I think I still like its name better):

```python
def sort(seq, **args):
    x = list(seq)
    x.sort(**args)
    return x
```

The `sorted` function has been available since Python v2.4.

## enumerate

[enumerate](https://docs.python.org/3/library/functions.html#enumerate) is
useful when you want a foreach loop, but you also need a loop counter around.
Use `enumerate()` instead of keeping a counter elsewhere.

For example, I was writing out a spreadsheet with
[ooolib-python](http://ooolib.sourceforge.net/). For each spreadsheet cell to
write, I had to specify row and column indexes. I could write more natural loops
with `enumerate`, while still having a counter to use as a row or column index.

This was my re-implementation (and its name would have never caught on):

```python
def indexiter(iterable):
    return zip(range(len(iterable)), iterable)
```

The `enumerate` function has been available since Python v2.3. Read about the
optional `start` parameter in the
[docs](https://docs.python.org/3/library/functions.html#enumerate).

---

This shows that it's a good idea to occasionally browse back through the very
basic support a language gives you, since you might just find a couple useful
tools in there that you had overlooked. If you're into Python, start
[here](https://docs.python.org/3/library/functions.html).

Most people seem to have an opinion as to whether exceptions in C++ are slow or
fast, but very few people have put any useful numbers out there. Here's a lower
bound.

---

```c++
#include <inttypes.h>
#include <stdio.h>

const uint64_t count = 1000000;

inline uint64_t
rdtsc()
{
    uint32_t lo, hi;
    asm volatile("rdtsc" : "=a" (lo), "=d" (hi));
    return (((uint64_t) hi << 32) | lo);
}

int
main()
{
    // Measure the cost of throwing and catching an int.
    uint64_t start = rdtsc();
    for (uint64_t i = 0; i < count; i++) {
        try {
            throw 0;
        } catch (int) {
            // do nothing
        }
    }
    uint64_t stop = rdtsc();
    printf("Cycles per exception: %lu\n",
           (stop - start) / count);
}
```

The code just measures the time it takes to throw the number 0 as an exception
and catch it.

Using g++ version 4.4.4, compiled with -O3 in 64-bit mode, and running on an
otherwise idle Intel Xeon E5620 CPU at 2.4 GHz, this benchmark takes 2.18 to
2.21 microseconds on average per exception.

So the cheapest exceptions on a modern CPU would cost about 2 microseconds.
When you throw an exception in a real project rather than a microbenchmark,
this cost is significantly higher. Anecdotally, we typically see times closer
to 5 microseconds for exceptions in the context of
[RAMCloud](https://web.stanford.edu/~ouster/cgi-bin/projects.php#ramcloud),
the project I work on at school.

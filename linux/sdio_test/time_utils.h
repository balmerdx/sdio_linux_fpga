#include <stdint.h>
#include <time.h>

static inline int msleep(long msec)
{
    struct timespec ts;
    int res;

    if (msec < 0)
    {
        errno = EINVAL;
        return -1;
    }

    ts.tv_sec = msec / 1000;
    ts.tv_nsec = (msec % 1000) * 1000000;

    do {
        res = nanosleep(&ts, &ts);
    } while (res && errno == EINTR);

    return res;
}

static inline uint64_t TimeUsec()
{
	struct timespec ts;
	timespec_get(&ts, TIME_UTC);
    return ts.tv_sec*(uint64_t)1000000+ts.tv_nsec/1000;
}

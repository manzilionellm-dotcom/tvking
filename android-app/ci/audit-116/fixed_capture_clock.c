// Horloge de capture, réservée au processus de test sélectionné.
// Aucun réglage de l'application ni du système n'est modifié. CLOCK_MONOTONIC
// et les autres bases de temps gardent les fonctions réelles de la libc.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static bool selected = false;
static time_t fixed_epoch;
static int (*real_clock_gettime)(clockid_t, struct timespec *);
static int (*real_gettimeofday)(struct timeval *, void *);
static time_t (*real_time)(time_t *);

__attribute__((constructor)) static void prepare_capture_clock(void) {
  real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
  real_gettimeofday = dlsym(RTLD_NEXT, "gettimeofday");
  real_time = dlsym(RTLD_NEXT, "time");
  const char *target = getenv("AUDIT116_CLOCK_PROCESS");
  const char *epoch = getenv("AUDIT116_CLOCK_EPOCH");
  if (!target || !epoch || !*target || !*epoch) return;
  char executable[PATH_MAX];
  ssize_t count = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
  if (count <= 0) return;
  executable[count] = '\0';
  const char *name = strrchr(executable, '/');
  if (strcmp(name ? name + 1 : executable, target) != 0) return;
  char *end;
  errno = 0;
  long long value = strtoll(epoch, &end, 10);
  if (errno || *end || value <= 0) return;
  fixed_epoch = (time_t)value;
  selected = true;
}

int clock_gettime(clockid_t clock, struct timespec *result) {
  if (selected && (clock == CLOCK_REALTIME || clock == CLOCK_REALTIME_COARSE)) {
    result->tv_sec = fixed_epoch;
    result->tv_nsec = 0;
    return 0;
  }
  if (!real_clock_gettime) real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
  return real_clock_gettime(clock, result);
}

int gettimeofday(struct timeval *result, void *zone) {
  if (selected) {
    result->tv_sec = fixed_epoch;
    result->tv_usec = 0;
    return 0;
  }
  if (!real_gettimeofday) real_gettimeofday = dlsym(RTLD_NEXT, "gettimeofday");
  return real_gettimeofday(result, zone);
}

time_t time(time_t *result) {
  if (selected) {
    if (result) *result = fixed_epoch;
    return fixed_epoch;
  }
  if (!real_time) real_time = dlsym(RTLD_NEXT, "time");
  return real_time(result);
}

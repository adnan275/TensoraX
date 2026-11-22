/*
 * File: cpu_baseline.c
 * Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
 * Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
 * Description: Sequential CPU baseline for N x N matrix multiplication with the
 *              same arithmetic as the RTL: signed 16-bit operands, products
 *              accumulated in a 32-bit two's-complement register that wraps on
 *              overflow (computed in unsigned arithmetic, so there is no C
 *              undefined behaviour).
 *
 * Build and run through scripts/run_cpu_benchmark.py. Direct use:
 *   cc -O2 -o cpu_baseline scripts/cpu_baseline.c
 *   ./cpu_baseline --info
 *   ./cpu_baseline --verify tb/vectors/array_rand_vectors.hex
 *   ./cpu_baseline --kernel generic --workload throughput --n 3
 *
 * Kernels
 *   generic : triple loop, N read at run time (cannot be unrolled for one N).
 *   fixed3  : the same triple loop with N = 3 known at compile time, so the
 *             compiler may fully unroll it and, at -O2, vectorize it.
 * Workloads
 *   throughput : independent matrix pairs from a pool that fits in L1, so the
 *                out-of-order core overlaps successive multiplies.
 *   latency    : each product is fed back (low 16 bits of every output) as the
 *                next A matrix, so every multiply waits for the previous one,
 *                including the store-to-load forwarding of a memory-resident
 *                matrix.
 *
 * Timing and cycles
 *   Wall-clock time per multiply is measured over many multiplies per trial.
 *   Neither macOS nor most Linux user space exposes a cycle counter, so CPU
 *   cycles are an ESTIMATE: ns per multiply times a clock estimate taken from
 *   a chain of dependent integer adds (1 cycle latency each) run just before
 *   every trial. --ghz overrides the estimate with a known frequency.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef __APPLE__
#include <mach/mach_time.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <sys/qos.h>
#endif

#define MAXN 16
#define MAXTRIALS 64

typedef int16_t in_t;
typedef int32_t out_t;

/* ------------------------------------------------------------------ timing */

static inline uint64_t now_ns(void)
{
#ifdef __APPLE__
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
#endif
}

/* Smallest non-zero step between two consecutive timer reads. */
static double timer_resolution_ns(void)
{
    uint64_t best = UINT64_MAX;
    for (int i = 0; i < 20000; i++) {
        uint64_t a = now_ns(), b = now_ns();
        while (b == a)
            b = now_ns();
        if (b - a < best)
            best = b - a;
    }
    return (double)best;
}

/* Clock estimate in GHz from a chain of 1-cycle dependent adds; 0 if unsupported. */
static double estimate_ghz(void)
{
#if defined(__aarch64__) || defined(__x86_64__)
    const uint64_t iters = 2000000; /* x 32 dependent adds = 64 M adds, ~15-20 ms */
    uint64_t x = 1, one = 1, cnt = iters;
    uint64_t t0 = now_ns();
#if defined(__aarch64__)
#define A8 "add %0, %0, %2\n\t" "add %0, %0, %2\n\t" "add %0, %0, %2\n\t" "add %0, %0, %2\n\t" \
           "add %0, %0, %2\n\t" "add %0, %0, %2\n\t" "add %0, %0, %2\n\t" "add %0, %0, %2\n\t"
    __asm__ volatile("1:\n\t" A8 A8 A8 A8 "subs %1, %1, #1\n\tb.ne 1b\n\t"
                     : "+&r"(x), "+&r"(cnt) : "r"(one) : "cc");
#else
#define A8 "add %2, %0\n\t" "add %2, %0\n\t" "add %2, %0\n\t" "add %2, %0\n\t" \
           "add %2, %0\n\t" "add %2, %0\n\t" "add %2, %0\n\t" "add %2, %0\n\t"
    __asm__ volatile("1:\n\t" A8 A8 A8 A8 "dec %1\n\tjnz 1b\n\t"
                     : "+&r"(x), "+&r"(cnt) : "r"(one) : "cc");
#endif
    uint64_t t1 = now_ns();
    /* Exact result check: catches a folded or mis-allocated chain. */
    if (x != 1 + iters * 32 || t1 <= t0)
        return 0.0;
    return (double)(iters * 32) / (double)(t1 - t0); /* adds per ns = GHz */
#else
    return 0.0;
#endif
}

/* Spin until three consecutive clock estimates agree within 1.5% (DVFS ramp-up done). */
static double settle_clock(void)
{
    double h[3] = {0, 0, 0}, last = 0;
    for (int i = 0; i < 60; i++) {
        last = estimate_ghz();
        h[0] = h[1]; h[1] = h[2]; h[2] = last;
        if (h[0] > 0 && h[1] > 0 && h[2] > 0) {
            double lo = h[0], hi = h[0];
            for (int k = 1; k < 3; k++) { if (h[k] < lo) lo = h[k]; if (h[k] > hi) hi = h[k]; }
            if ((hi - lo) / hi < 0.015)
                break;
        }
    }
    return last;
}

static void prefer_performance_core(void)
{
#ifdef __APPLE__
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
#endif
}

/* ----------------------------------------------------------------- kernels */

__attribute__((noinline)) static void matmul_generic(const in_t *A, const in_t *B, out_t *C, int n)
{
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            uint32_t acc = 0;
            for (int k = 0; k < n; k++)
                acc += (uint32_t)((int32_t)A[i * n + k] * (int32_t)B[k * n + j]);
            C[i * n + j] = (out_t)acc;
        }
}

__attribute__((noinline)) static void matmul_fixed3(const in_t *A, const in_t *B, out_t *C)
{
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) {
            uint32_t acc = 0;
            for (int k = 0; k < 3; k++)
                acc += (uint32_t)((int32_t)A[i * 3 + k] * (int32_t)B[k * 3 + j]);
            C[i * 3 + j] = (out_t)acc;
        }
}

static int use_fixed3;

static inline void run_kernel(const in_t *A, const in_t *B, out_t *C, int n)
{
    if (use_fixed3)
        matmul_fixed3(A, B, C);
    else
        matmul_generic(A, B, C, n);
}

/* ------------------------------------------------------------------ verify */

static int read_hex_words(const char *path, uint32_t **out, size_t *count)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    size_t cap = 4096, n = 0;
    uint32_t *w = malloc(cap * sizeof *w);
    char line[64];
    while (fgets(line, sizeof line, f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '\n' || *p == '\0' || *p == '/')
            continue;
        if (n == cap) {
            cap *= 2;
            w = realloc(w, cap * sizeof *w);
        }
        w[n++] = (uint32_t)strtoul(p, NULL, 16);
    }
    fclose(f);
    *out = w;
    *count = n;
    return 0;
}

/* Record layout (scripts/gen_array_vectors.py): gap, noclr, A[9], B[9], C_expected[9]. */
static int verify(const char *path)
{
    const size_t REC = 29;
    uint32_t *w;
    size_t n;
    if (read_hex_words(path, &w, &n) != 0) {
        fprintf(stderr, "cannot open %s\n", path);
        return 2;
    }
    size_t records = n / REC;
    long mism_generic = 0, mism_fixed = 0, noclr_ops = 0;
    uint32_t prev[9] = {0};
    for (size_t r = 0; r < records; r++) {
        const uint32_t *rec = w + r * REC;
        int noclr = (int)rec[1];
        in_t A[9], B[9];
        out_t Cg[9], Cf[9];
        for (int e = 0; e < 9; e++) {
            A[e] = (in_t)(uint16_t)rec[2 + e];
            B[e] = (in_t)(uint16_t)rec[11 + e];
        }
        matmul_generic(A, B, Cg, 3);
        matmul_fixed3(A, B, Cf);
        if (noclr)
            noclr_ops++;
        for (int e = 0; e < 9; e++) {
            uint32_t eg = (uint32_t)Cg[e] + (noclr ? prev[e] : 0u);
            uint32_t ef = (uint32_t)Cf[e] + (noclr ? prev[e] : 0u);
            uint32_t want = rec[20 + e];
            if (eg != want)
                mism_generic++;
            if (ef != want)
                mism_fixed++;
            prev[e] = want;
        }
    }
    printf("{\"verify\": {\"vectors\": \"%s\", \"records\": %zu, \"records_with_accumulate_on_top\": %ld, "
           "\"outputs_checked_per_kernel\": %zu, \"mismatches_generic\": %ld, \"mismatches_fixed3\": %ld}}\n",
           path, records, noclr_ops, records * 9, mism_generic, mism_fixed);
    free(w);
    return (mism_generic || mism_fixed || records == 0) ? 1 : 0;
}

/* ------------------------------------------------------------------ bench */

static uint64_t lcg_state = 0x9E3779B97F4A7C15ull;
static uint32_t lcg(void)
{
    lcg_state = lcg_state * 6364136223846793005ull + 1442695040888963407ull;
    return (uint32_t)(lcg_state >> 33);
}

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static double median(double *v, int n)
{
    double tmp[MAXTRIALS];
    memcpy(tmp, v, (size_t)n * sizeof(double));
    qsort(tmp, (size_t)n, sizeof(double), cmp_double);
    return (n & 1) ? tmp[n / 2] : 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
}

static volatile uint32_t sink;

/* Time `reps` passes; returns elapsed ns. Throughput: pass = whole pool. Latency: pass = one multiply. */
static uint64_t timed_pass(int latency, long reps, in_t *A, in_t *B, out_t *C, int pool, int n)
{
    int nn = n * n;
    uint64_t t0 = now_ns();
    if (latency) {
        for (long r = 0; r < reps; r++) {
            run_kernel(A, B, C, n);
            for (int e = 0; e < nn; e++)
                A[e] = (in_t)C[e];
        }
    } else {
        for (long r = 0; r < reps; r++)
            for (int p = 0; p < pool; p++)
                run_kernel(A + (size_t)p * nn, B + (size_t)p * nn, C + (size_t)p * nn, n);
    }
    return now_ns() - t0;
}

static int bench(int n, int latency, int trials, double target_ms, double ghz_override)
{
    int nn = n * n;
    int pool = 1;
    if (!latency) {
        pool = 49152 / (8 * nn); /* bytes per pair: 2 inputs x 2 B + 1 output x 4 B = 8 B per element */
        if (pool < 4) pool = 4;
        if (pool > 512) pool = 512;
    }
    in_t *A = malloc((size_t)pool * nn * sizeof *A);
    in_t *B = malloc((size_t)pool * nn * sizeof *B);
    out_t *C = calloc((size_t)pool * nn, sizeof *C);
    for (size_t e = 0; e < (size_t)pool * nn; e++) {
        A[e] = (in_t)(lcg() & 0xFFFF);
        B[e] = (in_t)(lcg() & 0xFFFF);
    }
    prefer_performance_core();

    /* Pilot run: choose reps so that one trial lasts about target_ms. */
    long reps = 1;
    uint64_t dt = 0;
    while (dt < 5000000ull) { /* at least 5 ms to get beyond timer granularity */
        reps *= 2;
        dt = timed_pass(latency, reps, A, B, C, pool, n);
    }
    long matmuls_per_rep = latency ? 1 : pool;
    double ns_each = (double)dt / ((double)reps * matmuls_per_rep);
    reps = (long)((target_ms * 1e6) / (ns_each * matmuls_per_rep)) + 1;
    (void)timed_pass(latency, reps, A, B, C, pool, n); /* warm-up at final size */

    if (ghz_override <= 0)
        (void)settle_clock();
    double ns_per[MAXTRIALS], ghz_t[MAXTRIALS], cyc_per[MAXTRIALS];
    int unstable = 0;
    for (int t = 0; t < trials; t++) {
        double g0 = ghz_override > 0 ? ghz_override : estimate_ghz();
        dt = timed_pass(latency, reps, A, B, C, pool, n);
        double g1 = ghz_override > 0 ? ghz_override : estimate_ghz();
        double ghz = 0.5 * (g0 + g1);
        if (g0 > 0 && g1 > 0 && (g0 > g1 ? g0 - g1 : g1 - g0) / ghz > 0.05)
            unstable++;
        ns_per[t] = (double)dt / ((double)reps * matmuls_per_rep);
        ghz_t[t] = (g0 > 0 && g1 > 0) ? ghz : 0.0;
        cyc_per[t] = ghz_t[t] > 0 ? ns_per[t] * ghz_t[t] : -1.0;
    }
    uint32_t chk = 0;
    for (size_t e = 0; e < (size_t)pool * nn; e++)
        chk ^= (uint32_t)C[e] * 2654435761u;
    sink = chk;

    double ns_med = median(ns_per, trials);
    double ghz_med = ghz_t[0] > 0 ? median(ghz_t, trials) : 0.0;
    double cyc_med = cyc_per[0] >= 0 ? median(cyc_per, trials) : -1.0;
    double ns_min = ns_per[0], ns_max = ns_per[0], cyc_min = cyc_per[0], cyc_max = cyc_per[0];
    for (int t = 1; t < trials; t++) {
        if (ns_per[t] < ns_min) ns_min = ns_per[t];
        if (ns_per[t] > ns_max) ns_max = ns_per[t];
        if (cyc_per[t] < cyc_min) cyc_min = cyc_per[t];
        if (cyc_per[t] > cyc_max) cyc_max = cyc_per[t];
    }
    printf("{\"kernel\": \"%s\", \"workload\": \"%s\", \"n\": %d, \"trials\": %d, \"matmuls_per_trial\": %ld, "
           "\"pool\": %d, \"ns_per_matmul_median\": %.4f, \"ns_per_matmul_min\": %.4f, \"ns_per_matmul_max\": %.4f, "
           "\"est_ghz_median\": %.4f, \"cycles_per_matmul_median\": %.3f, \"cycles_per_matmul_min\": %.3f, "
           "\"cycles_per_matmul_max\": %.3f, \"unstable_trials\": %d, \"checksum\": %u}\n",
           use_fixed3 ? "fixed3" : "generic", latency ? "latency" : "throughput", n, trials,
           reps * matmuls_per_rep, pool, ns_med, ns_min, ns_max, ghz_med, cyc_med, cyc_min, cyc_max, unstable, chk);
    free(A); free(B); free(C);
    return 0;
}

static void info(void)
{
    double res = timer_resolution_ns();
    double ghz[5];
    prefer_performance_core();
    (void)settle_clock();
    for (int i = 0; i < 5; i++)
        ghz[i] = estimate_ghz();
    printf("{\"info\": {\"timer_resolution_ns\": %.2f", res);
#ifdef __APPLE__
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    printf(", \"mach_timebase_numer\": %u, \"mach_timebase_denom\": %u", tb.numer, tb.denom);
#endif
    printf(", \"ghz_calibration_samples\": [%.3f, %.3f, %.3f, %.3f, %.3f]}}\n", ghz[0], ghz[1], ghz[2], ghz[3], ghz[4]);
}

int main(int argc, char **argv)
{
    const char *kernel = "generic", *workload = "throughput", *verify_path = NULL;
    int n = 3, trials = 9, do_info = 0;
    double target_ms = 60.0, ghz = 0.0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--kernel") && i + 1 < argc) kernel = argv[++i];
        else if (!strcmp(argv[i], "--workload") && i + 1 < argc) workload = argv[++i];
        else if (!strcmp(argv[i], "--n") && i + 1 < argc) n = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--trials") && i + 1 < argc) trials = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--target-ms") && i + 1 < argc) target_ms = atof(argv[++i]);
        else if (!strcmp(argv[i], "--ghz") && i + 1 < argc) ghz = atof(argv[++i]);
        else if (!strcmp(argv[i], "--verify") && i + 1 < argc) verify_path = argv[++i];
        else if (!strcmp(argv[i], "--info")) do_info = 1;
        else {
            fprintf(stderr, "unknown argument: %s\n", argv[i]);
            return 2;
        }
    }
    if (do_info) { info(); return 0; }
    if (verify_path) return verify(verify_path);
    if (n < 1 || n > MAXN || trials < 1 || trials > MAXTRIALS) {
        fprintf(stderr, "n must be 1..%d and trials 1..%d\n", MAXN, MAXTRIALS);
        return 2;
    }
    use_fixed3 = !strcmp(kernel, "fixed3");
    if (use_fixed3 && n != 3) {
        fprintf(stderr, "kernel fixed3 only supports n = 3\n");
        return 2;
    }
    return bench(n, !strcmp(workload, "latency"), trials, target_ms, ghz);
}

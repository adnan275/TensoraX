#!/usr/bin/env python3
"""Generate reproducible random test vectors for tb_systolic_array_random.v.

Independent reference model: plain Python integers, 32-bit two's-complement
wrap, no Verilog involved. Each record is 29 hex words (one per line):
  gap, noclr, A[0..8] (row-major, 16-bit), B[0..8] (16-bit), C_expected[0..8] (32-bit)
gap   = idle cycles between this operation and the previous one (0 = back to back)
noclr = 1: do not assert clr_acc, accumulate onto the previous result
Usage: gen_array_vectors.py [seed] [num_ops] > tb/vectors/array_rand_vectors.hex
"""
import random, sys

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 20261114
nops = int(sys.argv[2]) if len(sys.argv) > 2 else 600
rng = random.Random(seed)

def s16(x): return x & 0xFFFF
def wrap32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x

def rand_mat():
    mode = rng.choice(["small", "small", "full", "full", "extreme", "zero", "sparse"])
    def one():
        if mode == "small":   return rng.randint(-20, 20)
        if mode == "full":    return rng.randint(-32768, 32767)
        if mode == "extreme": return rng.choice([-32768, 32767, -1, 0, 1])
        if mode == "zero":    return 0
        return rng.choice([0, 0, 0, rng.randint(-1000, 1000)])
    return [one() for _ in range(9)]

acc = [0] * 9
for n in range(nops):
    A, B = rand_mat(), rand_mat()
    noclr = 1 if (n > 0 and rng.random() < 0.15) else 0
    gap = rng.choice([0, 0, 0, 1, 2, 3])
    if n == 0: gap = 0
    prod = [sum(A[i*3+k] * B[k*3+j] for k in range(3)) for i in range(3) for j in range(3)]
    acc = [wrap32((acc[x] if noclr else 0) + prod[x]) for x in range(9)]
    words = [gap, noclr] + [s16(v) for v in A] + [s16(v) for v in B]
    out = [f"{w:08x}" for w in words] + [f"{(v & 0xFFFFFFFF):08x}" for v in acc]
    print("\n".join(out))

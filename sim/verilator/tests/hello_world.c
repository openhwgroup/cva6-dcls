// Copyright (c) 2026, Eclipse Foundation AISBL
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Expected values for the default Verilator target:
 * cv64a6_imafdc_sv39_hpdcache_wb.
 */
#define DEFAULT_TARGET      "cv64a6_imafdc_sv39_hpdcache_wb"
#define EXPECTED_MISA      0x800000000014112FULL
#define EXPECTED_MVENDORID 0x0000000000000602ULL
#define EXPECTED_MARCHID   0x0000000000000003ULL
#define EXPECTED_MIMPID    0x0000000000000000ULL

static inline uint64_t read_misa(void) {
    uint64_t value;
    asm volatile ("csrr %0, misa" : "=r"(value));
    return value;
}

static inline uint64_t read_mvendorid(void) {
    uint64_t value;
    asm volatile ("csrr %0, mvendorid" : "=r"(value));
    return value;
}

static inline uint64_t read_marchid(void) {
    uint64_t value;
    asm volatile ("csrr %0, marchid" : "=r"(value));
    return value;
}

static inline uint64_t read_mimpid(void) {
    uint64_t value;
    asm volatile ("csrr %0, mimpid" : "=r"(value));
    return value;
}

static int check_csr64(const char *name, uint64_t actual, uint64_t expected) {
    if (actual != expected) {
        printf("\tERROR: CSR %s reads as 0x%016llx - expected 0x%016llx for %s.\n",
               name,
               (unsigned long long)actual,
               (unsigned long long)expected,
               DEFAULT_TARGET);
        return 1;
    }
    return 0;
}

static unsigned misa_mxl(uint64_t misa) {
    return (unsigned)((misa >> 62) & 0x3ULL);
}

static const char *mxl_name(unsigned mxl) {
    switch (mxl) {
        case 1:
            return "RV32";
        case 2:
            return "RV64";
        case 3:
            return "RV128";
        default:
            return "invalid";
    }
}

static void print_misa_extensions(uint64_t misa) {
    printf("\tmisa extensions = ");
    for (char ext = 'A'; ext <= 'Z'; ext++) {
        if ((misa >> (ext - 'A')) & 0x1ULL) {
            putchar(ext);
        }
    }
    putchar('\n');
}

int main(int argc, char* arg[]) {
    (void)argc;
    (void)arg;

    for (int i = 0; i < 5; i++) {
        printf("%d: Hello World !\n", i);
    }

    uint64_t misa = read_misa();
    uint64_t mvendorid = read_mvendorid();
    uint64_t marchid = read_marchid();
    uint64_t mimpid = read_mimpid();
    unsigned mxl = misa_mxl(misa);

    printf("\nCVA6-DCLS Verilator smoke-test CSR summary:\n");
    printf("\ttarget    = %s\n", DEFAULT_TARGET);
    printf("\tmvendorid = 0x%016llx\n", (unsigned long long)mvendorid);
    printf("\tmarchid   = 0x%016llx\n", (unsigned long long)marchid);
    printf("\tmimpid    = 0x%016llx\n", (unsigned long long)mimpid);
    printf("\tmisa      = 0x%016llx\n", (unsigned long long)misa);
    printf("\tmxl       = %u (%s)\n", mxl, mxl_name(mxl));
    print_misa_extensions(misa);

    int failures = 0;
    failures += check_csr64("misa", misa, EXPECTED_MISA);
    failures += check_csr64("mvendorid", mvendorid, EXPECTED_MVENDORID);
    failures += check_csr64("marchid", marchid, EXPECTED_MARCHID);
    failures += check_csr64("mimpid", mimpid, EXPECTED_MIMPID);

    if (failures != 0) {
        return EXIT_FAILURE;
    }

    printf("CSR check passed.\n");
    return EXIT_SUCCESS;
}

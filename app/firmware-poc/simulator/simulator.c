/**
 * simulator.c — ELF binary validator for CI pipeline
 * Supports ELF32 and ELF64.
 * Exit: 0=PASS, 1=FAIL
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define EI_NIDENT   16
#define EI_CLASS    4
#define ELFCLASS32  1
#define ELFCLASS64  2

#define EM_386      3
#define EM_ARM      40
#define EM_X86_64   62
#define EM_AARCH64  183

#define PT_LOAD  1
#define PF_X     0x1

#define MIN_SIZE_BYTES    512
#define MAX_SIZE_BYTES    (512 * 1024)

typedef struct { uint8_t e_ident[EI_NIDENT]; uint16_t e_type, e_machine;
    uint32_t e_version, e_entry, e_phoff, e_shoff, e_flags;
    uint16_t e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx;
} Elf32_Ehdr;

typedef struct { uint32_t p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align; } Elf32_Phdr;

typedef struct { uint8_t e_ident[EI_NIDENT]; uint16_t e_type, e_machine;
    uint32_t e_version; uint64_t e_entry, e_phoff, e_shoff; uint32_t e_flags;
    uint16_t e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx;
} Elf64_Ehdr;

typedef struct { uint32_t p_type, p_flags; uint64_t p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align; } Elf64_Phdr;

static void pass(const char *m)                   { printf("  [PASS] %s\n", m); }
static void fail(const char *c, const char *r)    { printf("  [FAIL] %s: %s\n", c, r); }

int main(int argc, char *argv[])
{
    printf("============================================================\n");
    printf(" POC Firmware Simulator — Binary Validator\n");
    printf("============================================================\n\n");

    if (argc != 2) { fprintf(stderr, "Usage: %s <firmware.elf>\n", argv[0]); return 1; }

    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "[ERROR] Cannot open: %s\n", argv[1]); return 1; }

    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    uint8_t *buf = malloc(size);
    if (!buf || fread(buf, 1, size, f) != (size_t)size) { fclose(f); free(buf); return 1; }
    fclose(f);

    printf("Binary : %s\n\n--- Running checks ---\n", argv[1]);
    int err = 0;

    /* 1. Magic */
    if (buf[0]==0x7f && buf[1]=='E' && buf[2]=='L' && buf[3]=='F') pass("ELF magic bytes");
    else { fail("ELF magic bytes", "not a valid ELF file"); free(buf); return 1; }

    /* 2. Size */
    if (size < MIN_SIZE_BYTES) { fail("File size", "too small"); err++; }
    else if (size > MAX_SIZE_BYTES) { fail("File size", "too large (> 512 KB)"); err++; }
    else { printf("  [PASS] File size (%ld bytes)\n", size); }

    if (err) goto done;

    /* 3. ELF class dispatch */
    uint8_t cls = buf[EI_CLASS];

    if (cls == ELFCLASS32) {
        Elf32_Ehdr *h = (Elf32_Ehdr *)buf;
        if (h->e_machine != EM_ARM && h->e_machine != EM_386)
            { fail("Architecture", "unexpected e_machine"); err++; }
        else printf("  [PASS] ELF32 architecture (%s)\n", h->e_machine==EM_ARM?"ARM":"x86");

        if (h->e_entry == 0) { fail("Entry point", "null"); err++; }
        else printf("  [PASS] Entry point (0x%08X)\n", h->e_entry);

        uint32_t xsz = 0;
        for (int i = 0; i < h->e_phnum; i++) {
            Elf32_Phdr *p = (Elf32_Phdr *)(buf + h->e_phoff + i * sizeof(Elf32_Phdr));
            if (p->p_type == PT_LOAD && (p->p_flags & PF_X)) xsz += p->p_filesz;
        }
        if (xsz == 0) { fail("Executable code", "no executable segment"); err++; }
        else printf("  [PASS] Executable code (%u bytes)\n", xsz);

    } else if (cls == ELFCLASS64) {
        Elf64_Ehdr *h = (Elf64_Ehdr *)buf;
        if (h->e_machine != EM_X86_64 && h->e_machine != EM_AARCH64)
            { fail("Architecture", "unexpected e_machine"); err++; }
        else printf("  [PASS] ELF64 architecture (%s)\n", h->e_machine==EM_X86_64?"x86-64":"AArch64");

        if (h->e_entry == 0) { fail("Entry point", "null"); err++; }
        else printf("  [PASS] Entry point (0x%016llX)\n", (unsigned long long)h->e_entry);

        uint64_t xsz = 0;
        for (int i = 0; i < h->e_phnum; i++) {
            Elf64_Phdr *p = (Elf64_Phdr *)(buf + h->e_phoff + i * sizeof(Elf64_Phdr));
            if (p->p_type == PT_LOAD && (p->p_flags & PF_X)) xsz += p->p_filesz;
        }
        if (xsz == 0) { fail("Executable code", "no executable segment"); err++; }
        else printf("  [PASS] Executable code (%llu bytes)\n", (unsigned long long)xsz);

    } else {
        fail("ELF class", "unknown (not ELF32 nor ELF64)"); err++;
    }

    /* Checksum fingerprint (informational) */
    uint32_t csum = 0;
    for (long i = 0; i < size; i += 4) csum += buf[i];
    printf("  [INFO] Checksum fingerprint: 0x%08X\n", csum);

done:
    free(buf);
    printf("\n--- Result ---\n");
    if (err == 0) {
        printf("  SIMULATOR: PASS — binary validated successfully\n");
        printf("============================================================\n");
        return 0;
    } else {
        printf("  SIMULATOR: FAIL — %d check(s) failed\n", err);
        printf("============================================================\n");
        return 1;
    }
}

/*
 * KroMs Stage 2 Bootloader
 *
 * Architecture: x86-64
 * Initial mode: 16-bit real mode
 *
 * Kernel location: 0x10000
 * Kernel disk LBA: 9
 */

.intel_syntax noprefix
.code16

.section .text
.global _start

_start:

    cli

    xor ax, ax

    mov ds, ax
    mov es, ax
    mov ss, ax

    mov sp, 0x7A00

    cld

    mov byte ptr [boot_drive], dl


/************************************************
 * BIOS DISK SUPPORT
 ************************************************/

    mov bx, 0x55AA
    mov ah, 0x41
    mov dl, byte ptr [boot_drive]

    push ds
    push es
    int 0x13
    pop es
    pop ds

    jc edd_error

    cmp bx, 0xAA55
    jne edd_error

    test cx, 1
    jz edd_error


/************************************************
 * CPU CAPABILITY CHECK
 ************************************************/

    /* Check PAE support */

    mov eax, 1
    cpuid

    bt edx, 6
    jnc cpu_error

    /* Check extended CPUID */

    mov eax, 0x80000000
    cpuid

    cmp eax, 0x80000001
    jb cpu_error

    /* Check long mode */

    mov eax, 0x80000001
    cpuid

    bt edx, 29
    jnc cpu_error


/************************************************
 * LOAD KERNEL FROM DISK
 ************************************************/

    mov word ptr [dap_count], 1
    mov word ptr [dap_offset], 0
    mov word ptr [dap_segment], 0x1000

    mov dword ptr [dap_lba], 9
    mov dword ptr [dap_lba + 4], 0

    mov cx, 120

.load_kernel:

    mov byte ptr [retry_count], 3


.read_sector:

    mov si, offset dap

    mov ah, 0x42
    mov dl, byte ptr [boot_drive]

    push ds
    push es
    push cx

    int 0x13

    pop cx
    pop es
    pop ds

    jnc .sector_loaded


    /* Reset disk service */

    xor ah, ah
    mov dl, byte ptr [boot_drive]

    push ds
    push es
    push cx

    int 0x13

    pop cx
    pop es
    pop ds

    dec byte ptr [retry_count]

    jnz .read_sector

    jmp disk_error


.sector_loaded:

    /* Advance destination segment */

    add word ptr [dap_segment], 0x20

    /* Advance disk LBA */

    add dword ptr [dap_lba], 1

    loop .load_kernel


/************************************************
 * ENABLE A20
 ************************************************/

    in al, 0x92

    or al, 0x02
    and al, 0xFE

    out 0x92, al


/************************************************
 * LOAD GLOBAL DESCRIPTOR TABLE
 ************************************************/

    lgdt [gdt_descriptor]


/************************************************
 * ENTER PROTECTED MODE
 ************************************************/

    mov eax, cr0

    or eax, 1

    mov cr0, eax

    ljmp 0x08, protected_mode


/************************************************
 * ERROR HANDLERS
 ************************************************/

edd_error:

    mov si, offset edd_error_text
    jmp print_error


cpu_error:

    mov si, offset cpu_error_text
    jmp print_error


disk_error:

    mov si, offset disk_error_text


print_error:

    lodsb

    test al, al
    jz halt_system

    mov ah, 0x0E
    mov bx, 0x0007

    int 0x10

    jmp print_error


halt_system:

    cli

1:
    hlt
    jmp 1b


/************************************************
 * GLOBAL DESCRIPTOR TABLE
 ************************************************/

.align 8

gdt_start:

    /* Null descriptor */

    .quad 0x0000000000000000

    /* 32-bit code */

    .quad 0x00CF9A000000FFFF

    /* Data */

    .quad 0x00CF92000000FFFF

    /* 64-bit code */

    .quad 0x00AF9A000000FFFF

gdt_end:


gdt_descriptor:

    .word gdt_end - gdt_start - 1
    .long gdt_start


/************************************************
 * VARIABLES
 ************************************************/

boot_drive:
    .byte 0

retry_count:
    .byte 0


.align 4


/************************************************
 * BIOS DISK ADDRESS PACKET
 ************************************************/

dap:

    .byte 0x10, 0

dap_count:
    .word 1

dap_offset:
    .word 0

dap_segment:
    .word 0x1000

dap_lba:
    .quad 9


/************************************************
 * ERROR STRINGS
 ************************************************/

edd_error_text:
    .asciz "KroMs: BIOS EDD extensions required"

cpu_error_text:
    .asciz "KroMs: CPU lacks PAE/long mode"

disk_error_text:
    .asciz "KroMs: kernel disk read failed"


/************************************************
 * 32-BIT PROTECTED MODE
 ************************************************/

.code32

protected_mode:

    mov ax, 0x10

    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x90000


/************************************************
 * CREATE IDENTITY PAGE TABLES
 ************************************************/

/*
 * PML4: 0x70000
 * PDPT: 0x71000
 * PD:   0x72000
 *
 * Map first 1 GiB using 2 MiB pages.
 */

    mov dword ptr [0x70000], 0x71003
    mov dword ptr [0x70004], 0

    mov dword ptr [0x71000], 0x72003
    mov dword ptr [0x71004], 0


    mov edi, 0x72000

    mov eax, 0x00000083

    mov ecx, 512


.make_pages:

    mov dword ptr [edi], eax
    mov dword ptr [edi + 4], 0

    add eax, 0x00200000
    add edi, 8

    loop .make_pages


/************************************************
 * ENABLE PAE
 ************************************************/

    mov eax, cr4

    or eax, 1 << 5

    mov cr4, eax


/************************************************
 * ENABLE LONG MODE
 ************************************************/

    mov ecx, 0xC0000080

    rdmsr

    or eax, 1 << 8

    wrmsr


/************************************************
 * ENABLE PAGING
 ************************************************/

    mov eax, 0x70000

    mov cr3, eax

    mov eax, cr0

    or eax, 1 << 31

    mov cr0, eax


/************************************************
 * ENTER 64-BIT MODE
 ************************************************/

    ljmp 0x18, long_mode


/************************************************
 * 64-BIT LONG MODE
 ************************************************/

.code64

long_mode:

    mov ax, 0x10

    mov ds, ax
    mov es, ax
    mov ss, ax

    xor ax, ax

    mov fs, ax
    mov gs, ax

    /* Initialize stack */

    mov rsp, 0x90000

    xor rbp, rbp

    /* Jump to KroMs kernel */

    mov rax, 0x10000

    jmp rax
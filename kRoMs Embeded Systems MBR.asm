/*
 * KroMs Stage 1 BIOS Bootloader 
 * Architecture: x86
 * Boot mode: Legacy BIOS
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
    mov sp, 0x7C00

    cld

    /* Preserve BIOS boot drive */
    mov byte ptr [boot_drive], dl

    sti

    /* Check BIOS EDD support */
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

    /* Retry disk reads up to three times */
    mov byte ptr [retry_count], 3

.read_stage2:

    mov si, offset dap
    mov ah, 0x42
    mov dl, byte ptr [boot_drive]

    push ds
    push es
    int 0x13
    pop es
    pop ds

    jnc stage2_loaded

    /* Reset disk service */
    xor ah, ah
    mov dl, byte ptr [boot_drive]

    push ds
    push es
    int 0x13
    pop es
    pop ds

    dec byte ptr [retry_count]
    jnz .read_stage2

    jmp disk_error


edd_error:
    mov si, offset edd_error_text
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


stage2_loaded:

    mov dl, byte ptr [boot_drive]

    ljmp 0x0000, 0x8000


/* Variables */

boot_drive:
    .byte 0

retry_count:
    .byte 0


.align 4

/* BIOS Disk Address Packet */

dap:
    .byte 0x10, 0
    .word 8
    .word 0x8000, 0
    .quad 1


/* Error messages */

edd_error_text:
    .asciz "KroMs: BIOS EDD required"

disk_error_text:
    .asciz "KroMs: stage-2 disk read failed"


/* Partition table */

.org 446
.space 64

/* Boot signature */

.word 0xAA55
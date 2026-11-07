ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0, LENGTH = 64K }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > ram
    .data : { *(.data*) *(.sdata*) } > ram
    . = ALIGN(4);
    _bss_start = .;
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); } > ram
    _bss_end = .;
    _stack_top = 0x10000;
    ASSERT(_bss_end < 0xd000, "Firmware overlaps host mailbox / reserved stack")
}

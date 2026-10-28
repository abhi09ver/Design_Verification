OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text*) *(.rodata*) *(.srodata*) }
  . = 0x80008000;
  .data : { *(.data*) *(.sdata*) }
  __bss_start = .;
  .bss : { *(.sbss*) *(.bss*) *(COMMON) }
  __bss_end = .;
}

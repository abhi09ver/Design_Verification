/* Program image: code at 0x80000000 (reset vector), data at 0x80008000.
   TOHOST (0x8000F000) is written with an absolute address by the test itself. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text) }
  . = 0x80008000;
  .data : { *(.data) }
}

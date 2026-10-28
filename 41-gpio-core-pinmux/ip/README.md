# Chipmunk Logic GPIO v1.0 package

`gpio_v1_0_Chipmunk.rar` is the original package from the [Chipmunk IP catalog](https://chipmunklogic.com/ip-solutions), by Mitu Raj, open-source licensed ("as is", no warranty).

The archive itself is not encrypted, but **every file inside is password-protected**. The password comes from subscribing at chipmunklogic.com (see the IP catalog page).

Contents (from the archive listing):

| File | Size |
|---|---|
| `gpio_v1_0/src/gpio_top.sv` | 19.8 KB |
| `gpio_v1_0/src/tb_gpio.sv` | 18.3 KB |
| `gpio_v1_0/src/apb_transactor.sv` | 8.1 KB |
| `gpio_v1_0/src/intr_gateway.sv` | 7.8 KB |
| `gpio_v1_0/src/intr_gen.sv` | 7.6 KB |
| `gpio_v1_0/src/irq_sync.sv` | 6.0 KB |
| `gpio_v1_0/src/areset_sync.sv` | 4.6 KB |
| `gpio_v1_0/src/gpio_cfg_macros.svh` | 4.4 KB |
| `gpio_v1_0/src/tristate_buff.sv` | 4.1 KB |
| `gpio_v1_0/Makefile`, `scripts/run.do` | 3.4 KB |
| `gpio_v1_0/doc/gpio_v1_0_ug.pdf`, `gpio_v1_0_IP_overview.pdf` | 0.9 MB |
| `LICENSE.md`, `readme.txt`, `release_notes.txt` | 6.2 KB |

Public copies of the documents:
- [User guide](https://chipmunklogic.com/wp-content/uploads/ip_cores/pdfs/gpio_v1_0_ug.pdf)
- [IP overview](https://chipmunklogic.com/wp-content/uploads/ip_cores/pdfs/ip_overview/gpio_v1_0_IP_overview.pdf)
- [Blog post: Design of GPIO core in RTL](https://chipmunklogic.com/ip-cores/design-of-gpio-core-in-rtl/)

To run the testbench on the real RTL: extract into `ip/gpio_v1_0/` with the password, then
`make vcs RTL=chipmunk RTL_DIR=ip/gpio_v1_0/src` (keep the extracted sources out of git if the licence terms ask you to).

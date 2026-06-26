## What this project does

Translates transactions from the fast AHB (Advanced High-performance Bus) to the simpler, slower APB (Advanced Peripheral Bus). In real SoCs, this bridge sits between the processor bus and low-speed peripherals like UARTs, timers, and GPIO controllers — allowing them to be controlled without needing to implement the full AHB protocol.

Why this bridge exists

AHB is pipelined — the address phase of the next transfer can overlap with the data phase of the current one. APB is much simpler — it has no pipelining, just a setup phase (PSEL high, PENABLE low) followed by an enable phase (PSEL high, PENABLE high).

The bridge's job is to absorb AHB's pipeline and translate each transaction into APB's two-phase handshake.

How an AHB transaction arrives

A transaction is valid when hselapb = 1 AND htrans is NONSEQ (2'b10) or SEQ (2'b11). This is decoded into a combinational valid signal.

The one-cycle pipeline registers

Since AHB is pipelined, the address arrives one cycle before the data (for writes). The bridge captures:

haddr_r — address, registered

hwdata_r — write data, registered

hwrite_r — read/write direction, registered

valid_r — whether the registered beat was a valid transaction

These registered versions are what the bridge actually uses to drive the APB side.

FSM — 8 states

| State | Meaning | Key signals |
| --- | --- | --- |
| IDLE | Waiting | hready=1 |
| READ | APB setup for read | psel=1, penable=0, pwrite=0 |
| RENABLE | APB enable for read | psel=1, penable=1 → captures prdata into hrdata |
| WWAIT | Stall AHB — waiting for write data | hready=0 |
| WRITE | APB setup for simple write | psel=1, penable=0, pwrite=1 |
| WRITE_P | APB setup for pipelined write | psel=1, penable=0, pwrite=1 |
| WENABLE | APB enable for simple write | psel=1, penable=1, hready=1 |
| WENABLE_P | APB enable for pipelined write | psel=1, penable=1, hready=1 |

The WRITE_P and WENABLE_P states handle the case where a new AHB transaction arrives while the bridge is still completing a write — pipelined write handling.

PSEL goes high in the setup phase. PENABLE goes high one cycle later in the enable phase. The peripheral samples PADDR and PWDATA when both are high.

## File structure

bridge.v      — Complete bridge: pipeline registers + 8-state FSM

bridge_tb.v   — Testbench: drives AHB read and write transactions, checks APB outputs

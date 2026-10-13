# Nanosecond-Accuracy FPGA-Implemented Time Synchronisation

UCL EEE 4th Year Project (ELEC0118), June 2026
Supervisor: Dr. Kari Clark

**Authors:** Faizaan Abbas, Edison Lo, Akindu Wijesekera, Bamidele Adelusi-Sanni

## Overview

Hardware-level time synchronisation underpins ultra-low latency trading, 5G,
and high-precision TDOA spatial positioning. While protocols like IEEE 1588
PTP and White Rabbit achieve exceptional accuracy, they treat the datalink
layer as an opaque "black box," masking asymmetric phase drift within FPGA
packet-processing pipelines. This project addresses that diagnostic gap by
designing a transparent, modular hardware architecture that executes a
two-way timestamp exchange while enabling granular, per-stage latency
characterisation.

A custom dual-endpoint architecture was implemented on a Xilinx VCU108
(150 MHz fabric clock). To isolate digital datapath latency from physical
medium uncertainty, the system was validated via an 80-bit GTY-bypass
configuration. The AXI4-Stream design spans a five-layer pipeline (framing,
CRC-32, PCS, and 8b/10b encoding) and executes a full PTP-style exchange
(SYNC, DELAY_REQ, DELAY_RESP), feeding the derived offset into a closed-loop
hardware servo to steer a subordinate local time counter.

### Key results

- Met all Vivado timing constraints (WNS +0.125 ns) with a low footprint
  (4.34% LUT usage)
- Hardware ILA captures confirmed error-free protocol execution and
  bidirectional clock steering, with a logical offset bounded between 1–15 ns
- Decomposed internal per-block latency: the two-way exchange averaged
  384.5 cycles (≈2.56 μs), with hardware probing identifying receive-side
  processing (RX register slice → CRC checker, 42 cycles / 280 ns) as the
  dominant bottleneck versus timestamp arithmetic (3 cycles / 20 ns)

By characterising this asymmetric digital pipeline latency — a blind spot in
state-of-the-art systems like CERN's TCLink — the design acts as both a
synchronisation node and a diagnostic instrument, providing a verified
digital foundation for drift-compensated, sub-nanosecond board-to-board
synchronisation over active transceivers.

## Repository structure

```
Modules/                       SystemVerilog source (interfaces, transmitter,
                                receiver, local time counter, core logic)
  reduced_Comlexity_Design/    Final/up-to-date version of the datapath
                                modules, with testbenches under sim/
vcu108_4trx/                   Vivado project for the Xilinx VCU108 target
  vcu108_4trx.srcs/            Project sources (constraints, IP cores, top-level)
  vcu108_4trx.xpr               Vivado project file
```

The `vcu108_4trx` Vivado project scaffold was provided by our supervisor,
Dr. Kari Clark, as the baseline platform project for the VCU108 board; our
own contribution is the time-synchronisation datapath and core logic built
on top of it. Vivado-generated build output (`.cache`, `.gen`, `.hw`,
`.ip_user_files`, `.runs`, `.sim`, logs/journals) is excluded via
`.gitignore` since it's regenerated from the project sources.

## Team

This was a team project built with Faizaan Abbas, Edison Lo, and Bamidele
Adelusi-Sanni, supervised by Dr. Kari Clark at UCL.

🧬 ROOM: Read-Once-Only Memory

(Verilog Reference Implementation — Patent Pending)

ROOM (Read-Once-Only Memory) is a post-algebraic, quantum-inspired cryptographic primitive developed by QSymbolic LLC and protected under U.S. Patent Pending: US 19/286,600.

Inspired by the irreversibility of quantum measurement and the no-cloning theorem, a ROOM register guarantees:

A stored value can be retrieved exactly once — and then it self-collapses.

On the first valid read, the register releases its secret, then irreversibly collapses within the same clock cycle.
On every subsequent read, the cell emits obfuscation (pseudorandom noise, TRNG-derived output, or collapse-jitter), ensuring the original secret cannot be recovered or cloned.

This repository contains the official reference Verilog modules implementing the ROOM primitive as described in QSymbolic’s post-algebraic cryptography patent filings.

⸻

✨ Key Features
	•	Read-once enforcement — secrets collapse and are permanently destroyed after the first qualified read.
	•	Metadata gating — access requires correct basis, phase, tags, or protocol-specific conditions.
	•	Collapse latch — same-cycle, deterministic disable after disclosure.
	•	Obfuscation feed — pseudorandom or entropy-derived replacement values for every post-collapse read.
	•	Peer-linked collapse — entangled cells trigger group rekey or network-wide collapse events.
	•	Entropy harvesting — collapse jitter, metastability, and timing noise feed local RNGs.

⸻

📂 Repository Contents
	•	collapse_register_entangled.sv — peer-linked collapse behavior
	•	collapse_register_keyexchange.sv — ephemeral key release with KDF
	•	qkd_collapse_register.sv — BB84-style collapse emulation
	•	qkd_entangled_pair.sv — E91-inspired entangled memory pair
	•	mdi_qkd_top.sv — MDI-QKD demo for ROOM
	•	collapse_rng.sv — collapse-derived entropy source
	•	testbench.sv — simulation and verification environment

All modules are directly derived from the RTL disclosed in the Atomic Memory™ patent filings.

⸻

🔒 Security Properties
	•	Post-algebraic & post-quantum — independent of hardness assumptions (lattice, multivariate, code-based).
	•	Quantum-inspired no-cloning — secrets self-destroy after measurement/decapsulation.
	•	QKD-style intrusion detectability — wrong-basis reads collapse the state and raise error rates.
	•	Low-power & efficient — collapse + KDF cost far less than Kyber, Dilithium, or optical QKD.
	•	Composable across stacks — works in FPGAs, ASICs, secure elements/SIMs, SoCs, and software models.

⸻

🛰️ Applications
	•	6G mobile radios — ultralow-latency ephemeral rekeying
	•	Satellites & swarms — collapse-driven group rekeying or distributed QKD-like state sharing
	•	Cloud KMS / HSMs — tamper-evident ephemeral per-tenant keys
	•	IoT & secure boot — one-time provisioning and firmware authentication
	•	ZKP & homomorphic crypto — collapse-derived entropy for sampling and masking

⸻

🛡️ Patent Status

This work is Patent Pending under:

U.S. Patent Application: US 19/286,600
Title: Post-Algebraic Cryptography Using Atomic (Read-Once-Only) Memory
Filed and owned by QSymbolic LLC.

This repository provides an evaluative, academic-only reference implementation of the disclosed techniques.

⸻

📜 License

This project is licensed under the PolyForm Noncommercial License 1.0.0.
	•	✅ Free for personal, academic, research, and noncommercial use
	•	🚫 Commercial use prohibited — including ASIC/FPGA/SoC integration, security appliances, telecom products, cloud services, or any revenue-generating deployment
	•	➡️ A commercial license is required for any commercial application

Commercial Licensing

For semiconductor, telecom, cloud, defense, or consumer-device licensing, contact:

QSymbolic LLC — Francis X. Cunnane III
📧 frank@qsymbolic.com
🌐 https://qsymbolic.com

⸻

⚠️ Disclaimer

This software is provided “as is”, without warranty of any kind, express or implied.
Use at your own risk. No guarantee of correctness, robustness, suitability, or cryptographic security is provided.

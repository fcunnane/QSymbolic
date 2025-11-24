ROOM: Read-Once-Only Memory (Verilog Reference Implementation)

ROOM (Read-Once-Only Memory) is a post-algebraic, quantum-inspired cryptographic primitive developed by QSymbolic LLC.

Modeled after a quantum measurement enforcing the no-cloning theorem, ROOM ensures that a stored value (e.g., a cryptographic key) 
can be read once only. On the first valid access, the value is released and the register collapses irreversibly within the same clock cycle. 
All subsequent reads return obfuscation (pseudorandom or noise-influenced replacement values).

This repository provides the reference Verilog modules for ROOM as described in the Post-Algebraic Cryptography patent filings.

⸻

✨ Key Features
	•	Read-once enforcement — secrets collapse on first qualified read.
	•	Metadata gating — access requires matching basis, phase, tags, or timing.
	•	Collapse latch — same-cycle disable after release.
	•	Obfuscation source — pseudorandom or entropy-derived replacement values.
	•	Peer-linked collapse — entangled cells propagate collapse for group rekeying.
	•	Entropy harvesting — collapse jitter and metastability seed RNGs.

⸻

📂 Contents
	•	collapse_cell.v — core ROOM cell with collapse latch + obfuscation.
	•	metadata_collapse_register.v — adds metadata predicates (basis, phase, tags).
	•	collapse_register_entangled.v — peer-linked collapse across cells.
	•	collapse_register_keyexchange.v — ephemeral key release with KDF.
	•	qkd_collapse_register.v — BB84-style collapse emulation.
	•	qkd_entangled_pair.v — entangled pair register (E91-style).
	•	mdi_qkd_top.v — measurement-device-independent (MDI) protocol demo.
	•	collapse_rng.v — collapse-derived entropy source.
	•	testbench.v — simulation environment.

⸻

🔒 Security Properties
	•	Post-algebraic & post-quantum: independent of lattice/coding hardness assumptions.
	•	Quantum-inspired: enforces a no-cloning principle at the hardware/software level.
	•	QKD-like intrusion detectability: unauthorized reads collapse secrets into noise, measurable via error rates.
	•	Low power, high efficiency: collapse + KDF cycle costs far less than lattice-based PQC or optical QKD.
	•	Composable: works in FPGA, ASIC, SIM/secure elements, and software.

⸻

🛰️ Applications
	•	Mobile / 6G radios — ultra-low-latency ephemeral rekeying.
	•	Satellites & swarms — low-power, high-efficiency key release; peer collapse for group rekey.
	•	Cloud KMS / HSMs — tamper-resistant ephemeral API/tenant keys.
	•	IoT & secure boot — one-time provisioning and firmware authentication.
	•	ZKPs & homomorphic encryption — collapse-backed entropy for protocols.

⸻

📜 License

This project is licensed under the PolyForm Noncommercial License 1.0.0.
	•	✅ Free for personal, research, academic, and other noncommercial purposes.
	•	🚫 Not permitted for commercial use (products, services, paid offerings) without a license.

For commercial licensing (semiconductors, telecom, satellite, defense, etc.), please contact:
QSymbolic LLC — Francis X. Cunnane III
📧 frank@qsymbolic.com | 🌐 qsymbolic.com


All code and documentation were reviewed, tested, and curated by QSymbolic LLC.

⸻

⚠️ Disclaimer: This software is provided “as is”, without warranty of any kind, express or implied.

⸻

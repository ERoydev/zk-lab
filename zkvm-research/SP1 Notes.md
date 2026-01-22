# SP1 Notes

## Overview

SP1 Hypercube proves the validity of computations encoded as program with the RISC-V 64-bit instruction set. → https://blog.succinct.xyz/nethermind-lean/

- SP1 uses Poseidon2 hash (SNARK Friendly hash) in the trace commitments
- SP1 toolchain includes a custom Rust target and compiler plugin that outputs RISC-V binaries along with a CLI to produce proofs.
- SP1 zKVM fully supports the Rust standard library (std)
- SP1 uses `cargo-prove` → Init, compile (RISC-V ELF binary), supports Docker-based builds to ensure "Reproducible Builds"
- SP1 uses the RISC-V `ECALL` instruction to invoke precompiles and system calls
- SP1 is configured to provide at least 100 bits of security, which is the standard for high-security ZK systems. (FRI Conjectures, to keep proof sizes small without compromising safety.)
- SP1 implements a second VM dedicated to verification, with its own instruction set for verifier calculations. (Provides Rust DSL)

---

## 1. Performance

- Use a state-of-the-art GPU prover tuned for speed
- Generates proofs for Ethereal block in just minutes

---

## 2. Scalability

Sp1 breaks the execution trace into small, manageable chunks called shards.

- **Parallel proving**: because of these shards are independent, a closer of GPU can prove 100 different parts of the program at the same time.
- **The "trillion cycle" scale**: allows sp1 to handle programs that would crash a normal computer, workload is spread across a decentralized network.
- Once the shards are proven, SP1 Glue them together, with specializing mini-zkvm with only job to verify START proofs using ISA extensions for proof-checking.
- **Recursion DSL**: custom domain specific language that allows engineers to write recursive circuits optimized for math-heavy verification
- Uses a "Two-Phase Prover" approach with a single verifier challenge
- Proves memory is consistent across shards mathematically without ever building a Merkle tree. This removes the "Hashing Tax" that usually slows down long-running programs.

---

## 3. Dev Experience

- SP1 zKVM fully supports the Rust standard library (std)
- SP1 uses `cargo-prove` → Init, compile (RISC-V ELF binary), supports Docker-based builds to ensure "Reproducible Builds"
- SP1 Projects are typically split into three clean parts:
    - **Program (guest)**: The code that actually runs inside the ZKVM.
    - **Script (host)**: The untrusted code that runs on your local machine to provide data to the VM and trigger the proof generation
    - **ELF**: The compiled RISC-V executable that acts as the bridge between your code and the ZK math.

---

## 4. Prover

- Devs write their program, compile using SP1 toolchain. After that, use SP1 Prover to generate a proof.
- Can offer on-chain verifier contract on Solidity.

---

## 5. Tools → Built-in Syscalls

- **I/O Operations**: `sp1_zkvm::io::read`, `sp1_zkvm::io::commit` used to pull data into VM and push public results out.
- **Halt**: clean way to exit the program and finalize proof
- **Cryptographic Primitives**: Precompiles for Sha256, keccak256, secp256k1 and BN254 arithmetic are all exposed as sys calls.

---

## 6. ZKP Scheme

- SP1 uses a protocol that combines PLONK-style custom gates (for complex logic) with a START-style FIR (Fast Reed-Solomon IOP) commitment scheme.
- SP1 represents the RISC-V execution trace as an Algebraic IR. Uses algorithm called `LogUp` to handle lookups (memory access or bus communication)
- **FRI Protocol**: the core "engine" there proves the polynomials in the trace are of low degree
- While many ZK systems use large 256-bit numbers, SP1 operates in the BabyBear field. (31-bit Prime). Because 31 bits fit perfectly inside a standard 32-bit or 64-bit computer register, addition and multiplication are incredibly fast. (That's why SP1 achieve such high throughput on GPUs)
- **Poseidon2 Hashing**, Ideal Glue of connecting shards of proof together.

---

## 7. Memory

Instead of building a giant Merkle Tree of every memory access, SP1 uses a two-phase protocol to prove memory consistency:

- **Phase 1**: The prover executes the program and logs every "Read" and "Write" operation into a giant transcript.
- **Phase 2**: The verifier provides a "challenge" (a random number). The prover then uses a mathematical "running total" (accumulator) to prove that every "Read" at a specific address matches the last "Write" to that same address.

### What is this "running total":

- It uses a specialized elliptic curve defined over a degree-7 extension of the 31-bit BabyBear field.
- This curve is chosen specifically because its operations are fast in the BabyBear field but "hard" for an attacker to break.
- SP1 assumes the Discrete Logarithm Problem on this curve is hard. It follows SafeCurves standards to ensure roughly 100-bit security, matching the rest of the system.

**SP1 Way (Accumulator)**: You only perform a lightweight elliptic curve operation. This allows SP1 to handle massive programs with millions of memory operations without the proof size or proving time exploding.

---

## 8. Final Proof Compression

- While internal VM logic uses fast STARKs, they are too large for Ethereal to verify cheaply. SP1 "wraps" the STARK in a final, tiny SNARK.
- SP1 compress it via recursive aggregation → shards compressed into a single, intermediate STARK proof
- This single START is fed into a final circuit that outputs a Groth16 SNARK proof.

---

## 9. Virtual Machine → Core ISA (RV32IM)

- Doesn't implement CSR
- Operate on a flat trust model (no kernel, no OS layer inside the VM), there is no kernel/user split.
- **The calling convention for Syscalls** → Load the Syscall ID into register `T0` and place Arguments into registers `A0` and `A1` (else is "undefined behavior")

### 9.1. Memory Model → Uses LinearMemory

Memory verification is specified in step 7.

- **Pseudo-Registers (0x0 - 0x1F)**: memory range is memory-mapped to the 32 physical RISC-V CPU registers. Writing data to the address `0x5` is the same as modifying the register x5. (The first 32 addresses are not "normal" memory. They are aliased directly to the RISC-V CPU registers.)
- **Valid Heap Range**: Program memory is restricted o the range `0x20` to `0x78000000`, everything above is invalid!
- **Strict Alignment**: LW and SW must be word-aligned (address divisible by 4), LH and SH must be half-word aligned, these ensures the AIR representation remains as small as possible.
    - *Example*: In a traditional CPU, if you try to load a 4-byte "word" from an odd address (like 0x103), the hardware has to do extra work to "stitch" the data together from two different memory slots.

---

## 10. Prover Implementation

- **Sharding**: Breaks RISC-V execution into "shards"
- **START Proofs**: Generates parallel proofs for each shard using Plonky3
- **Recursion**: Recursively merges these shards into a single "Master STARK."
- **Final Wrap**: Uses the Gnark library to wrap the START into a tiny Groth16 SNARK.

---

## 11. Verifier Implementation

- **On-Chain**: auto-generated Solidity contract to verify the final Groth16 proof.
- **Off-Chain**: sp1-verifier crate
- SP1 maintains a set of "Universal" verification keys for its circuits. As long as you are using a standard version of the SP1 VM, your on-chain verifier will recognize the proofs without needing a new deployment.

### Verification Key

**Verification Key** → 32-byte identifier for specific compiled RISC-V program. (Identity for my logic), allows a single, permanent on-chain contract to verify any program.

**Process**: Compile code → Get Vkey → Generate Proof → Send Proof + Vkey to the existing universal verifier.

---

# Security

**Reference**: [SP1 ZKVM Security Guide](https://blog.sigmaprime.io/sp1-zkvm-security-guide.html#:~:text=SP1%20is%20architected%20like%20a,2)

## Host Vs Guest Architectural Separation

- SP1 programs are structured with clear separation between trusted and untrusted components
- Both host and guest code only execute during proving, the verifier performs pure mathematical verification without executing any source code.

### 1. Host Program (Untrusted orchestrator)

- Runs in a standard execution environment (your OS)
- Prepares inputs for the guest program
- Invokes the SP1 zKVM to generate proofs
- Is NOT part of the cryptographic proof
- Can be controlled by a malicious prover

Everything that the host does outside the cryptographic guarantees. A malicious actor controlling the host can provide arbirtrary inputs to the guest program.

### 2. Guest Program

They runs inside the VM, they do not have access to an operation system. No Internet connections, databases, files or operating system calls. These tasks all must be done by the host and shared as untrusted input.

- Contains the logic you want to prove
- Runs inside the SP1 zkVM (RISC-V env)
- Derives a unique verification key
- Has its execution cryptographically proven
- Operates n a 32-bit RISC-V env.

**Important**: Only the guest program's execution is proven. The verifier math checks validate only the guest code's execution, host code behavior is never cryptographically verified.

---

## Auditing

### 1. All input Data is Untrusted

That means Guest program must validate all input data taken from host

### 2. Only Guest code is proved

Critical logic must be implemented in the guest program, NOT THE HOST.

### 3. 32-bit vs 64-bit Architecture Differences

- Have in mind that: SP1 uses 32-bit RISC-V, which can cause issues when porting from 64-bit systems.
- **Important Note**: The Baby Bear field used by SP1's cryptographic system (~2^31) does NOT affect guest program integer type, usize remains a full 32-bit unsigned integer (0 to 2^32 - 1).
- That means `usize` is always 32 bits in the guest, pointer arithmetic differences, memory addressing limitations, integer overflow in calculations that work fine on 64-bit systems.

### 4. Third-Party Dependencies and Compatibility

- Libs written for general platforms may assume access to to the OS 64-bit arch
- Unsafe code or FFI

### 5. Integer Overflow

- Rust integer overflow behavior differs between debug and release modes. (Use checked_arithmetic checked_add, checked_mul)6

### 6. Verification Key Management

- Program compiled generate two keys (both are public key). First is given to the prover (Pkey), only valid for specific program. Second key is verification key (VKey), specifically verification key is valid only for a specific program
- Both public keys are derived from the source code, changing the source code changes the keys

### 7. Public vs Private Data Leakage

### 8. Proof Replay and Uniqueness

Valid proofs might be replayed in unintended contexts

---

# My Hands-On Notes

## 1. The SP1 Project Structure

- **program/** → The Guest → The "Trusted" logic I want to prove. This code is compiled to RISC-V and runs inside the ZKVM. (sp1-zkvm)
- **script/** → The Host → The "Untrusted" orchestrator. This runs on my actual CPU/GPU (x86/ARM) to manage inputs and trigger the prover (sp1-sdk)
- **contracts/** → The Verifier → (Optional) Solidity code used to verify the generated proofs on an EVM blockchain (found)

### The Guest (program/)

- This is where my STF lives
- Reads inputs, performs the computation like checking an Ethereal block, "commits" the results via `sp1_zkvm::io::commit()`
- **Result**: When I build this folder, it produces ELF

### The Host (script/)

- This is the "wrapper" that feeds data to the Guest.
- It uses `ProverClient` and `include_elf!` macro.
- Loads ELF from the program folder → I gathers real-world data (like fetching transactions from RPC) → Calls `client.prove(&pk, stdin)` to start the heavy math.
- **Important**: Host code itself is NOT proven. If I have a bug here, the proof generation might fail, but it cannot "fake" a proof of the Guest's logic.

**Analogy**: The Guest is a witness in a courtroom (providing the truth), and the Host is the lawyer (organizing the paperwork and presenting the witness to the judge).

### How Data flows

- Host writes data to `stdin`
- Guest reads data from `stdin` inside the VM
- Guest does the math and `commits` the output.
- Host receives the `Proof` and the `Public Values`

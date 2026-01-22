# ZK SP1 Part 2: Deep Dive

## Workflow

- The `guest` code - ('Program' in the image above) is basically an EVM/STF
- The `program inputs` are all the transactions included in the block, and the previous block state.
- The `host` uses these inputs to execute the EVM State Transition Function (STF)
- The `host` then produces the `output` (a new block), along with a proof of valid execution

### Three Kinds of Proofs Required in Each Block

- **State**: What are all the balances, addresses and raw data currently, and do they agree with the entire history of the chain?
- **Execution**: Now that we know what the current state is, what is the post execution state transition, once all the transactions in the current block are executed? Has this been done correctly without any cheating?
- **Consensus**: Has the cryptoeconomics of the proof of stake mechanism (which ultimately secures the chain) been executed correctly? Have all the validator actions, balances, withdrawals signatures etc been updated

---

## What is STF() Ethereal State Transition Function

Specify ta checklist that every Ethereal node - and every ZKVM must complete to move the blockchain from the Old State to the New State.

### STF Checks

- Verifying transaction signatures.
- Verifying account & storage state against the parent block's state root.
- Applying transactions.
- Paying the block reward.

So in order to say that the block is "logical" in mean the STF must verify a set of strict rules for every transaction. And the every node on Ethereal runs this to verify a block.

**Formal mathematical name for the logic of a block**: `S_t+1 = f(S_t, B)`

- `S_t`: Pre-State (balances/data before the block)
- `B`: The Block (the list of new transactions)
- `S_t+1`: The Post-state (the final result)

### Delegation to Coprocessor

During the execution of the STF, the ZKVM will "delegate" to the coprocessor every time the STF rules require:

- Hashing a new state root (Update the Merkle Patricia Trie).
- Recovering a public key from a signature (ECDSA)
- Checking a contract's bytecode hash.

### Summary

- **Input**: Parent Block Root + New transactions
- **Execution**: The program completes the checklist
- **Output**: New block root + ZK Proof (receipt) proving that every check is followed perfectly

---

## Glue and Coprocessor Architecture

- **RISC-V (The Glue)**: Handles the "Business Logic" (smart contract rules). It is easy to program but slow for heavy math. ("Did the sender have enough ETH?")
- **Specialized Modules (The Coprocessor)**: Hard-coded mathematical circuits that do one thing (things like Keccak hashes or ECDSA signatures) extremely fast.
- **The Goal**: To avoid the "10,000x overhead" of running heavy math inside a virtual CPU. You "offload" the heavy lifting to the specialist and use RISC-V to stick the pieces together.

### How the Combination Works

1. **The Programmer Writes Code**: You write your contract in Rust/Solidity.
2. **The Compilation**: It turns into RISC-V.
3. **The Execution (The Hand-off)**:
    - The RISC-V "Glue" runs your balance checks and logic.
    - When the code hits a line that says "Hash this data," the RISC-V doesn't try to solve it. It calls out to the specialized Keccak Coprocessor.
4. **The "Stitching" (The Proof)**: The ZKVM takes the small proof from the RISC-V logic and the small proof from the Coprocessor and "glues" them together into one final, valid certificate.

### How Process is Handled Inside the Coprocessor

| Step in your logic | What the Glue (RISC-V) does | What the Coprocessor does |
|-------------------|------------------------------|---------------------------|
| **1. System Tx Setup** | Orchestrates the "special" transaction. Decides if a beacon root needs updating. | If the update requires a hash, the coprocessor handles the SHA-256 or Keccak math. |
| **2. Initialize Tries** | Manages the memory for the new data structures. Loops through the initial state. | Merkle Patricia Trie (MPT) creation. Every time a new branch is "hashed," a coprocessor takes the hit. |
| **3. Transaction Loop** | The "Manager": Loops through every tx, checks the nonce, and manages gas accounting. | ECDSA Recovery: Verifying the sender's signature. RLP Encoding: Hashing the tx data for the trie. |
| **4. Apply Withdrawals** | Processes the validator list. Calculates how much ETH to move. | Updating the Withdrawal Trie. (Heavy Hashing work). |
| **5. Finalize Output** | Aggregates all results into the ApplyBodyOutput struct. | Logs Bloom: Bitwise OR operations on huge filters. Final State Root: The massive "Grand Finale" hash of the entire state. |

### In the Context of Ethereal

EVM Precompiles are the "triggers":

1. The Glue (RISC-V) runs the code.
2. It reaches a part of the code that says: "Now verify this signature"
3. In a normal CPU, this would take 100,000 cycles.
4. The Glue instead sends a signal (`ecall`) to the Coprocessor Circuit.
5. The Coprocessor returns the answer in effectively 1 cycle of "math time"

### Summary

- **The Glue (RISC-V code)** acts as the "Manager" of the block. It is good for logic
- **Coprocessor**: The "Hardware Accelerators" for Keccak, SHA256 and ECDSA.
- Glue only handles the easy stuff, Coprocessors handle the "Moon math".

---

## Precompiles

**Reference**: [HackMD - Execute ecall syscall_impl](https://hackmd.io/@grandchildrice/By-6PQickx#:~:text=The%20process%20within%20execute_ecall(),syscall_impl)

They act like built-in contracts the handle heavy-lift operations in a more optimized way than raw EVM byte code.

- Cryptographic primitives as BLS12-381 can be invoked vie these precompile addresses, this cuts down on the large number of instructions a normal contract would need to perform these operations.
- Conceptually, these precompiles are a software-lever "coprocessor"- The EVM recognizes them as special addresses that execute native code.

Precompile tasks in our case are implemented under `RISC-V extensions` where specialized instructions handle elliptic-curve arithmetic, large integer math, or hashing at the hardware layer. This expansion allow me to run them on dedicated circuits or co-processors optimized for parallel computation and low-latency arithmetic.

We want o run the whole STF inside a zKVM, and then produce a proof of the validity of the execution. In this scenario, each step of block validation (header checks, transaction execution, merle trie updates) generates a cryptographic proof that every operation was carried out correctly.

### 1. Reduced Arithmetic Bloat

- Using RISC-V with specialized extension for special instruction to use coprocessors i can handle keccak round or elliptic-curve operations in fewer CPU instructions
- **Example**: A single "Keccak round" instruction replaces dozens (or hundreds) of general-purpose RISC-V ops, cutting down the total steps the zk proof must cover.

### 2. Parallel/Offloaded Computation

- Signature checks, merke trie hashing, polynomial arithmetic, can be offloaded to dedicated coprocessor blocks or precompiles that run in constant or near-constant time.
- Since zKVM is proving the RISC-V execution itself, every CPU instruction is part of the proof. A specialized unit providing a "hardware call" for, say, big-integer multiplication can be treated as one instruction call, rather than expanding many micro-operations in the proof.

---

## Overall Block Proof Workflow

1. **Compile** → Take the source code of the VM and compile it into RISC-V Elf binary (the guest)
2. **Input**: Send the Transactions and the Parent State root (The witness) into the zkvm.
3. **Execute and Prove**: The zkvm "Host" runs that RISC-V binary.
4. **Output**: You get the New State Root and the ZK Proof.

### Closer Look into the Inputs

- **The Block Transactions**: list of singed messages from users
- **The Parent Header**: contains the "Parent State Root" `S_t`.
- **The Execution Witness**: Since the compiled RISC-V code doesn't have a hard drive, the Host must provide "mini-proofs" (Merkle proofs) for every account balance and storage slot that the transactions will touch.
    - *"I don't have the whole Ethereum database, but I have this cryptographic proof that Alice's balance was exactly 5 ETH at the start of this block."*

**STF Formula**: `STF(S_t, B, W)` → Parent Root, Block Tx's, Execution witness

### Workflow Visualization

| Phase | Action | Component |
|-------|--------|----------|
| **1. Preparation** | Compile the STF logic (the "Guest") into a RISC-V binary. | The Guest (e.g., revm or reth) |
| **2. Gathering** | Fetch the Transactions and the Execution Witness (Merkle proofs for touched accounts). | The Inputs (from an Archive Node) |
| **3. Proving** | The ZKVM Host runs the Guest code using the Inputs to calculate the new state. | The ZKVM (e.g., RISC Zero or SP1) |
| **4. Finalizing** | Generate the ZK Proof and the New State Root. | The Output (The "Receipt") |

### Note

The coprocessors and extensions are there to solve the Aritmethics. When my compiled Guest code needs to do a keccak.

The idea is that I don't take the full EVM I take the "Stateless executor", it is the man only version of the EVM that takes the data (witness) as input, runs the rules, and spits out a proof.

### Ensuring Correctness via Formal Verification

In the end I have to ensure the correctness of the underlying RISC-V architecture itself via formal verification:

- If the RISC-V extensions and base ISA are proven to adhere to a rigorously specified, mathematically checked model, then the proof of execution isn't just attesting to the correctness of higher-level operations (like hashing or signature checks)—it's also anchored in the guarantee that each instruction in the CPU pipeline conforms precisely to the specification. This end-to-end assurance means that no hidden bugs or deviations in the hardware instructions can silently undermine the zero-knowledge proof process. In other words, formal verification of the RISC-V spec ensures that both the "coprocessor" tasks (like cryptographic math) and the "glue" logic (like branching and state transitions) faithfully follow the intended logic at the hardware level, extending trust from the software stack all the way down to the silicon.

---

## Formal Verification (FV)

**Reference**: [Nethermind Lean Blog Post](https://blog.succinct.xyz/nethermind-lean/)

- You've built a system where a general-purpose CPU (RISC-V) runs the Ethereum rules (STF) and generates a proof. But how do you know the "Math Circuit" for the RISC-V ADD instruction actually does what the real RISC-V ADD instruction is supposed to do?

Formal Verification is the process of using a computer (like the Coq or Lean proof assistants) to mathematically prove that the ZK circuits are a 100% perfect match for the official RISC-V specification.

### The Three Components

- **The Specification (The rulebook)** → there is "Source of Truth" for RISC-V (called Sail), defines what should happen to register when instruction runs
- **The Arithmetization (The Math Circuit)**: Engineers write the ZK equations (constraints) for each RISC-V instruction.
- **The Check (Formal Verification)**: A "Formal Verifier" tool compares the Rulebook to the Math Circuit. It checks every possible input and output to ensure they are identical.

### The Final Hierarchy of Trust

1. **Smart Contract Logic**: Verified by the EVM STF.
2. **EVM STF**: Compiled into RISC-V.
3. **RISC-V Execution**: Proved by the ZKVM.
4. **ZKVM Integrity**: Guaranteed by Formal Verification.

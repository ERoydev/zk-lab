
# ZKVM Overview

The idea of a ZKVM is to recompile the "engine" of the Ethereal Virtual Machine (EVM) itself.

### The Problem

- Traditional ZK-EVM had to manually build math circuits for every single Ethereum OPCODE.
- So for every operations (like adding), engineers had to manually design a mathematical circuit (constraint). Every time when I want to solve a new type of math problem, I need to write another circuit. In other words it's hard to update.

### Solution
- The written code in high-level languages like (C++, Rust) can be compiled to RISC-V ISA. And then this can be ruined in the so called ZKVM.
- The result: Instead of just the result, I will get a zk proof that the RISC-V Cpu executed the instructions correctly.

### Conclusion
- zKvm turns a “zero knowledge Prover” into a Universal CPU, so everything that can be compiled to RISC-V can be proved, allowing any standard program (like a game or the Ethereum engine) to be verified cryptographically
- A ZKVM still uses mathematical circuits, but they are built for the fixed RISC-V instructions rather than the specific application logic. Because the ISA is small and never changes, these circuits are built once and used to prove everything.


RISC-V ZKVM takes the EVM and recompiles it into RISC-V machine code and runs that RISC-V code in the SP1 ZKVM for example. It runs the EVM compiled code, which EVM inside runs the Solidity smart contracts.

The Workflow Summary
1. The Source: Take the code for the EVM (e.g., the revm engine written in Rust).
2. The Compile: Compile that Rust code into RISC-V machine code.
3. The Execution: Run that RISC-V code inside the ZKVM.
4. The Proof: The ZKVM generates a ZK Proof (using that FRI-based prover we talked about) that proves the RISC-V CPU executed the EVM code correctly.


So for example when. Send a Solidity contract to this “virtualized” EVM, the zkvm will not give me the output, instead it will give me the ZK Proof that the EVM rules were followed perfectly

## Is it Performant?

- The overhead by ZKVM is too high compared to custom proofs, there always be certain areas where going "under the hood" provides significant performance gains.
  
- However the ZK-proof community has realized this is okay. Some modern ZKVMs have adopted precompile-centric architecture that combines best of both worlds; it allows users to compile their code to RISC-V in most cases, while surgically extending the ISA with low-level circuits that accelerate performance-sensitive operations.

---

## Why Reproducibility Matters

### Example Scenario
- One player needs to write a program that processes valid moves in the game and proves their resolution on the board (verifying hits and misses without revealing ship positions). In practice, this code would be written in a high-level language like Rust, which is the advantage of using a RISC-V ZKVM.

- Both players must agree that this program meets their expectations, and they must also agree on the ZKVM they want to use.

- Then, one player (say Alice) compiles the program to RISC-V, resulting in a RISC-V assembly that the VM can verify the execution of.

- Alice then writes a smart contract designed to verify valid proofs of execution of this RISC-V assembly on various inputs (e.g., valid player moves) and ensures the payout to the winner once the game concludes.

Concretely, this smart contract is parameterized with a verifying key specific to the RISC-V assembly program. This key is necessary because, without it, the smart contract could accept proofs from any RISC-V program and might not correctly assign rewards to the winner. For Bob to produce valid proofs for his Battleship moves—and trust that the proof corresponds to the original program agreed upon with Alice—he must independently reproduce this verifying key, which requires getting the exact same RISC-V assembly that Alice used.

---

## Reproducible Builds

### The Challenge: Reproducible Builds

- **Goal**: Ensuring that high-level code (Rust) always turns into the exact same RISC-V binary, regardless of who compiles it.
- **The Danger**: If Bob can't reproduce Alice's binary, he can't trust that the ZK proof corresponds to the code he read.

### Key Information for Reproducibility

So as an information that Alice and Bob should share to achieve reproducibility should be (RISC-V compilation target, exact ZKVM Version):

- Exact choice and version of the compiler is crucial (GCC and LLVM produces different results from same source)
- All compilation parameters are needed, as compilers often introduce difficult-to-reproduce environment values (e.g. file paths) into the produced assembly
- Other problems are like compiles employ profile-guided optimizations, linkers produce results dependent on the linking order, which can vary across systems, and so on…

In response, zkvms have adopted a compilation pipeline that generates the RISC-V binary within a docker container (still do not provide reproducibility, they are neither deterministic or portable).

### Proposed Solutions

#### 1. Deterministic Compilation (The "Hermit" approach)

Instead of using a normal OS, you use a "sealed" environment. Every time you hit compile, the "clock" is set to exactly January 1st, 1970, the file paths are renamed to `/work`, and all random factors are removed. This ensures that no matter who hits "Compile," the binary is identical.

#### 2. "On-Chain" Compilation (The Extreme Solution)

Some projects suggest that the Blockchain itself should perform the compilation. If the network compiles the Rust code into RISC-V, everyone knows the binary is honest. (This is very expensive and slow, however).

#### 3. Formal Verification

As the text mentions, the Ethereum Foundation is looking into Formally Verifying the compiler. This means using math to prove that the "Translator" (the compiler) can never tell a lie when turning Rust into RISC-V.

---

## Security Concerns: RISC-V VM Proofs

Modern compilers often introduce bugs where the binary (RISC-V assembly, in our case) does not accurately reflect the original high-level code:

### Peephole Optimization Example

One example is peephole optimization → compiler identifies patterns in the generated assembly and rewrites them to be more efficient.

So the LLVM IR function may compute `f(x) = 4` on a function `f(x) = 4 - x` and this is **BIG BUG**. It is so called **mis-optimization bug**:
- Code is often unit tested and expected inputs and outputs are easy to verify. However in a ZKVM prover doesn’t reveal their inputs and a peephole optimization like that will produce error that is hard to detect.
- Here is example during an audit on Aave contracts on ZKSync → https://www.certora.com/blog/llvm-bug
- That bug allows an attacker to create a proof that appears to match the high-level program's semantics but actually follows the mis-optimized semantics. That's an exploitable bug.

Even with conservative estimates, every month, there should be at least a dozen new known vulnerabilities likely to lead to an exploit in a formally verified RISC-V ZKVM, where proofs are verified against assembly generated by one of the two major compilers (GCC or LLVM).

---

## Certified Compilation
While mainstream compilers may not be reliable enough to produce trustworthy assembly, there are better alternatives, such as certified compilation.

### CompCert

`CompCert` offers a formally verified compiler that ensures the preservation of a wide range of semantics during the compilation process.

- With all its limitations that it has it still includes a RISC-V 32-bit backend that could provide strong guarantees for the correctness of compiled assembly.

### Factors to Consider

- Most modern RISC-V ZKVMs benchmark their performance code compiled at the more aggressive (and default) optimization level 3. How much of a setback would going back to level 1 represent?
- The performance of native execution doesn't always correlate directly with proving performance.

---

## Summary

Overall RISC-V-based ZKVMs allows for fast proof development and the reuse of existing codebases.

### Challenges

- Performance optimization
- Reproducibility
- Security

Miscompilation bugs and the complexity of achieving reproducible builds continue to pose significant issues.

In other words the Drawbacks and Challenges:
- Performance Bottlenecks ->Certain instructions present performance bottlenecks, devs optimize their code and use specialized hardware or accelerators to mitigate that. (Glue and Coprocessor solves that)
- Compiler bugs -> RISC-V assembly code does not accurately reflect the original high-level cod, because of miss-optimization bugs.
- Benchmarking Challenges -> ZKVMs that use different ISA’s, are hard to be compared to RISC-V architectures for performance

---

## Resources

- [RISC-V: The Good and The Bad](https://argument.xyz/blog/riscv-good-bad/)

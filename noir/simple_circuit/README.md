# Explanation

This document explains the logic and structure of the `simple_circuit` Noir circuit, as described in the source file `main.nr`.

## Inputs
- `x`: A private input to the circuit (inputs are private by default in Noir).
- `y`: A public input to the circuit (made public using the `pub` keyword).

## Circuit Logic
The main function enforces the following constraint:

- It asserts that `x` is not equal to `y`:
  ```noir
  assert(x != y);
  ```

## Proof Generation and Verification
- When creating a proof, both private (`x`) and public (`y`) inputs must be specified.
- When verifying proofs on-chain, only the public inputs (`y`) and the proof itself are required, since public inputs are known to everyone.


# Creating and Verifying Proofs Off-Chain

1. Create proof using: `nargo check` -> Checks if everything is fine and creates `Prover.toml` 
    - When i put some parameters for both `x` and `y` and then do `nargo execute`, executes the circuit with given inputs (compile to ACIR and executes our circuit with these provided inputs and it computes an witness)
    - Inside `target` i have both the witness saved and the ACIR IR with bytecode field inside that i can use to verify the proof.

2. Verify proof using your backend:
  - I can use `Sunspot`, solana specific
  - `Barretenberg` common used backend for circuits written on noir


  **Barretenberg Proof Generation Command:**

  ```sh
  bb prove \
    -b ./target/simple_circuit.json \
    -w ./target/simple_circuit.gz \
    -o ./target
  ```

  **Arguments:**
  - `-b` — Uses the bytecode field from the ACIR file (`./target/simple_circuit.json`).
  - `-w` — Loads the witness file generated during execution (`./target/simple_circuit.gz`).
  - `-o` — Specifies the output folder where the backend will generate the proof.

  Then with this proof i can submit to a verifier smart contract to verify the proof on-chain.

  **Validate off-chain**
  
// These two parameters are the inputs to our circuit.
// 'x' is a private input, while 'y' is a public input. (inputs by default are private in noir using 'pub' makes them public)

// When we are creating the proof we will specify both the private and public inputs.
// When we verify the proofs on-chain we have to specify the public inputs along with the proof, since they will be known by everyone.
fn main(x: Field, y: pub Field) {
    assert(x != y);
}

#[test]
fn test_main() {
    main(1, 2);
}

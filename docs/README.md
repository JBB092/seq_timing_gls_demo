# Docs directory

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

Reading order:

| Document | What it covers |
|---|---|
| [`theory.md`](theory.md) | tCO, tSU, tH, slack, setup and hold, skew, metastability, PVT corners, and RTL vs functional GLS vs GLS with delays |
| [`design.md`](design.md) | The problem, the circuit, the depth set with a `define`, approaches A and B, and where the delays come from |
| [`results.md`](results.md) | Tool versions, the board test, and the thresholds of the STA, approach A, approach B and the board |

The details of each part are in the README of its folder:

| Folder | Contents |
|---|---|
| [`rtl/`](../rtl/README.md) | The synthesizable design |
| [`cells/`](../cells/README.md) | The simulation cells of approach A |
| [`tb/`](../tb/README.md) | The testbench, the simulation modes and how to read the output |
| [`filelists/`](../filelists/README.md) | What each simulation mode compiles |
| [`quartus/`](../quartus/README.md) | The `board` and `core_sim` revisions, the PLL, building and programming |
| [`scripts/`](../scripts/README.md) | Every script and the flow from Quartus to the k x T tables |

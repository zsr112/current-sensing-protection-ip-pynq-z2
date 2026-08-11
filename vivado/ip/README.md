# Packaged IP

IP packaging is owned by `vivado/tcl/reconstruct_stage2_b1_safe_inert.tcl`. The adapter stages generated headers under `src/generated`, uses a relative `src` include dependency, and places both CDC XDC files once in the implementation file group. Generated IP output belongs outside this repository.

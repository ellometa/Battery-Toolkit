# magled

Set the MagSafe LED colour on Apple Silicon Macs. Fork of Battery-Toolkit, reduced to the `ACLC` SMC write.

    ./build.sh
    sudo ./magled green
    sudo ./magled orange-green 0.5   # alternate green/orange every 0.5s, Ctrl-C restores

`system` hands the LED back to macOS.

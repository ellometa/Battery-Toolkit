# MagLED

Customise the MagSafe LED and the plug-in sound on Apple Silicon MacBooks. Forked from
[Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit); reduced to the SMC `ACLC` (LED) write.

## Build

    ./build.sh          # build/magled (CLI) and build/MagLED.app (GUI)
    open build/MagLED.app

Needs the Xcode command line tools. No Xcode project.

## GUI

- **Events:** pick a sound (default: the bundled chime) and an LED profile for plug-in and unplug.
- **Profiles:** build your own sequence of LED states with a duration each, repeated N times, then hand the LED back to macOS.
- **LED helper:** writing the SMC needs root. "Install" asks for your admin password once and installs a small
  launchd daemon (`/usr/local/libexec/magled daemon <uid>`). It listens on `/var/run/magled.sock` (mode 0600, owned by you)
  and accepts only the values 0-7 for the one `ACLC` key. "Remove" uninstalls it.
- **Silence the built-in chime** disables Apple's `com.apple.powerchime` launch agent for your user (`launchctl disable`, reversible from the app). The system chime file is on the sealed volume and is not modified. On by default.

## LED states (`ACLC`)

Only 0-7 are kept by the SMC (measured with `magled scan`); higher values alias to the low three bits.

| Value | State |
|---|---|
| 0 | system control |
| 1 | off |
| 3 | green |
| 4 | orange |
| 6 | orange, slow blink |
| 7 | orange, fast blink |
| 2, 5 | accepted, effect untested |

Green and orange cannot be lit together by any known value, so mixed patterns are made by alternating steps.

## CLI

    sudo build/magled green            # system|off|green|orange|orange-slow|orange-fast|orange-blink-off
    sudo build/magled orange-green 0.5 # alternate, Ctrl-C restores
    sudo build/magled raw 0x05
    sudo build/magled scan 2 | tee scan.txt

Licensed BSD-3-Clause, see `LICENSE.txt`.

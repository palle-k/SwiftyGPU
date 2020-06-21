# SwiftyGPU

A command-line GPU usage monitor similar to `nvidia-smi` that runs on macOS with any GPU.

```
--------------------------------------------------------------------------------
| SwiftyGPU                                     21. June 2020 at 18:28:59 CEST |
--------------------------------------------------------------------------------
| ID | Name                            |          VRAM (used/total) | GPU Util |
--------------------------------------------------------------------------------
|  0 | Intel UHD Graphics 630          |        1537 MiB / 1536 MiB |     12 % |
--------------------------------------------------------------------------------
|  1 | AMD Radeon Pro 5500M            |        8037 MiB / 8176 MiB |     71 % |
--------------------------------------------------------------------------------
```

### Usage

#### Install

```bash
swift build -c release
cp .build/release/swifty-gpu /usr/local/bin/swifty-gpu
```

SwiftyGPU can then be invoked simply by typing `swifty-gpu` into your shell.

If you don't want to install SwiftyGPU permantently, you can also use `swift run swifty-gpu` instead of `swifty-gpu` in the subsequent examples.

#### Run once:

```bash
swifty-gpu
```

#### Run every x seconds

```bash
# replace <x> with a number of your choice
watch -n <x> swifty-gpu
```

#### Raw (JSON) Output

```bash
swifty-gpu --raw
```

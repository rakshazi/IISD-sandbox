# It Is So Dangerous sandbox

This is a tradeoff between full isolation and ability to actually work for AI agents.
The sandbox is configured with the stack *I* need to work with, so you may want to adapt it to your needs.

**NOTE**: this is not an ideal isolation, it is not intended to be. This sandbox is tailored for *my* specific use-cases,
and I need things like executables in `/tmp` for example. Feel free to adapt it to your needs.

By default sandbox is configured to run [Oh My Pi](https://omp.sh) agent.
You can change that, see [Optional](#optional) section.

<!-- vim-markdown-toc GFM -->

* [Prerequisites](#prerequisites)
    * [Understanding the threat model](#understanding-the-threat-model)
        * [Special instructions for UNCENSORED-ABLITERATED-HERETICKED-ULTRA-NEO-MAX-PRO-8K-244Hz enjoyers](#special-instructions-for-uncensored-abliterated-hereticked-ultra-neo-max-pro-8k-244hz-enjoyers)
    * [Optional](#optional)
* [Usage](#usage)
    * [Installation](#installation)
    * [Running](#running)
    * [Updates, modifications, rebuilds](#updates-modifications-rebuilds)

<!-- vim-markdown-toc -->

## Prerequisites

- [docker](https://docs.docker.com/get-docker/)
- [just](https://just.systems/manpage/)

### Understanding the threat model

The sandbox with default configuration is designed to be used with an agent that does "usual work"
like coding, writing, etc.
It might be used for read/blue teaming agents, but requires adjustments in `justfile` like disabling networking - don't be Anthropic, we're all sick of the FelonyBench already.

So, my main threat model is an agent going "oops, I accidentally nuked your system. That's on me" situations rather than you running a malicious agent asking it to hack pentagon.

#### Special instructions for UNCENSORED-ABLITERATED-HERETICKED-ULTRA-NEO-MAX-PRO-8K-244Hz enjoyers

**DISABLE**. **DAMN**. **NETWORKING**. `--network=none` <- this is the way.

Uncensored models *can* do anything. Depending on the prompt and model quality, it probably *will* do weird things.
Disable the networking. Don't try to claim a place in a felony bench ladder with your Qwen-Fable-ULTRA-MEGA-NEO-HACKER-HERETIC-8b. (Yes, it will be hilarious. No, it's not worth it anyway.)

### Optional

1. adapt [Dockerfile](Dockerfile) to your needs
2. adapt [justfile](justfile) to your needs (e.g., networking, mounts, etc.)

## Usage

### Installation

```bash
git clone https://github.com/rakshazi/IISD-sandbox.git ~/.omp/docker
```

Reminder: this is the moment you read [Prerequisites](#prerequisites) and do modifications.

Alias to use `omp` instead of `just -f ~/.omp/docker/justfile run`:

```bash
echo "alias omp='just -f ~/.omp/docker/justfile run'" >> ~/.bashrc
```

now `omp` your way.

### Running

```bash
just run
```

### Updates, modifications, rebuilds

```bash
# Wrapper designed after `omp update`: rebuild (update) and run after that
just run update

# OR do build separately from run
just build
```

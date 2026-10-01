# It Is So Dangerous sandbox

This is a tradeoff between full isolation and ability to actually work for AI agents.
The sandbox is configured with the stack *I* need to work with, so you may want to adapt it to your needs.

**NOTE**: this is not an ideal isolation. This sandbox is tailored for *my* specific use-cases,
and I need things like executables in `/tmp` for example. Feel free to adapt it to your needs.

By default sandbox is configured to run [Oh My Pi](https://omp.sh) agent.
You can change that, see [Optional](#optional) section.

Also, I wrote [You Don't Need A %Frontier LLM%](https://rakshazi.me/blog/you-dont-need-frontier-llm/) where the setup and purposes were explained.
(Just in case you might be interested in my ranting for some reason.)

<!-- vim-markdown-toc GFM -->

* [Prerequisites](#prerequisites)
    * [Understanding the threat model](#understanding-the-threat-model)
        * [Special instructions for UNCENSORED-ABLITERATED-HERETICKED-ULTRA-NEO-MAX-PRO-8K-244Hz enjoyers](#special-instructions-for-uncensored-abliterated-hereticked-ultra-neo-max-pro-8k-244hz-enjoyers)
    * [Optional](#optional)
* [Usage](#usage)
    * [Installation](#installation)
    * [Running](#running)
    * [Netless runs](#netless-runs)
    * [Updates, modifications, rebuilds](#updates-modifications-rebuilds)

<!-- vim-markdown-toc -->

## Prerequisites

- [docker](https://docs.docker.com/get-docker/)
- [just](https://just.systems/manpage/)

Additionally, for the ~~FelonyBench ladder~~ disabled networking runs:

- [tinyproxy](https://github.com/tinyproxy/tinyproxy)
- [socat](https://repo.or.cz/socat.git)

### Understanding the threat model

The sandbox with default configuration is designed to be used with an agent that does "usual work"
like coding, writing, etc.
It might be used for read/blue teaming agents, but requires adjustments in `justfile` like disabling networking - don't be Anthropic, we're all sick of the FelonyBench already.

So, my main threat model is an agent going "oops, I accidentally nuked your system. That's on me" situations rather than you running a malicious agent asking it to hack pentagon.

#### Special instructions for UNCENSORED-ABLITERATED-HERETICKED-ULTRA-NEO-MAX-PRO-8K-244Hz enjoyers

**DISABLE**. **DAMN**. **NETWORKING**. `--network=none` <- this is the way. [`just run netless`](#netless-runs) does the trick.

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

Disabled networking:

```bash
just run netless
```

_(Yes, I know you downloaded that ARA-SOMPOA-ABSOLUTE-HERESY finetune, the `netless` mode is for you.)_

### Netless runs

`--network=none` <- the thing the [threat model section](#special-instructions-for-uncensored-abliterated-hereticked-ultra-neo-max-pro-8k-244hz-enjoyers) yells about.
Except an agent with zero holes can't think, so exactly two get punched, both on the host side and both over unix sockets.
That's `just run netless`, or `omp netless` with the alias.

1. `api.venice.ai:443` through [tinyproxy](https://tinyproxy.github.io/) doing what a proxy should: allowlist, default deny, CONNECT to port 443 only. Inside the container it looks like a boring `HTTPS_PROXY=http://127.0.0.1:8118`. You are supposed to change it to your provider's host justfile, btw. Or keep [Venice](https://venice.ai/chat?ref=kpXDe6 "my personal ref link with $10 bonus") - this one is good (ZDR, unrestricted open-weight models, including deliberately uncensored ones).
2. Your local model server (`127.0.0.1:8899` on the host by default) for `local/*` models. Change it as well.

No egress.
Web search, direct connections, and whatever clever exfiltration route your model was about to invent: all dead.
Provider API endpoints stay reachable by design, because that's where your prompts go anyway, so that's the one pipe to watch.

Host side wants Linux with `tinyproxy` and `socat` (`pacman -S tinyproxy socat`, `apt install tinyproxy socat`, `dnf install tinyproxy socat`). Defaults sit at the top of the `netless` recipe in the [justfile](justfile), every one of them overridable via env var:

- `NETLESS_ALLOW` (default `api.venice.ai`): comma-separated hostnames allowed through the proxy, add your provider endpoints here
- `NETLESS_LOCAL_TARGET` (default `127.0.0.1:8899`): host address of your local model server
- `NETLESS_PROXY_PORT` / `NETLESS_LOCAL_PORT` (defaults `8118` / `8899`): loopback bridge ports inside the container

<details>
<summary>Notes</summary>

- `~/.omp/docker` stays writable in netless runs, so the agent can work on the sandbox itself (`justfile` / `Dockerfile` edits apply on the next host-side run)
- One netless session at a time: the recipe takes a lock, so a second `omp netless` gets told to come back later.
- `netless/` is runtime state (sockets, lock, logs), gitignored, sockets are recreated per run, logs append across sessions.
- The proxy keeps receipts in `~/.omp/docker/netless/tinyproxy.log`: session markers, allowed CONNECTs, refusals. First file to read when the agent starts mentioning something about internal documents of Australian government.

</details>

### Updates, modifications, rebuilds

```bash
# Wrapper designed after `omp update`: rebuild (update) and run after that
just run update

# OR do build separately from run
just build
```

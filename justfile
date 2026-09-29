# positional arguments: recipes read their arguments as $1..$n and pass them on as "$@"
set positional-arguments

uid := `id -u`
gid := `id -g`
home := `echo $HOME`
agent := "omp"

build *args:
    docker build -t {{ agent }} {{ args }} .

# run agent in docker sandbox
[no-cd]
run *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # explicit update
    if [ "${1:-}" = update ]; then
    	echo "[{{ agent }} sandbox] updating..."
    	{{ just_executable() }} -f {{ justfile() }} build --pull --no-cache
    	echo "[{{ agent }} sandbox] ready to run"
    	# re-run without args
    	exec {{ just_executable() }} -f {{ justfile() }} run
    fi
    # air-gapped run: no network; only allowlisted model APIs via unix sockets (see README)
    if [ "${1:-}" = netless ]; then
    	shift
    	exec {{ just_executable() }} -f {{ justfile() }} netless "$@"
    fi
    # potential first run when no image exists yet
    if ! docker image inspect {{ agent }} &> /dev/null; then
    	echo "[{{ agent }} sandbox] building..."
    	{{ just_executable() }} -f {{ justfile() }} build
    	echo "[{{ agent }} sandbox] ready to run"
    	exec {{ just_executable() }} -f {{ justfile() }} run "$@"
    fi

    # host network is needed for local models; `just run netless` is the air-gapped path
    exec {{ just_executable() }} -f {{ justfile() }} __docker host "" "" "$@"

# run the agent air-gapped: no network; only the allowlisted model API and the local model server are reachable
[no-cd]
netless *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # host-specific setup; every value can be overridden via the matching NETLESS_* env var
    ALLOW="${NETLESS_ALLOW:-api.venice.ai}"                # proxy allowlist: comma-separated hosts (CONNECT to 443 only)
    LOCAL_TARGET="${NETLESS_LOCAL_TARGET:-127.0.0.1:8899}" # host address of the local model server
    PROXY_PORT="${NETLESS_PROXY_PORT:-8118}"               # https proxy port; 8080 stays free for omp's llama.cpp probe
    LOCAL_PORT="${NETLESS_LOCAL_PORT:-8899}"               # container port bridged to the local model server
    TP_PORT="${NETLESS_TP_PORT:-18888}"                    # first host port candidate for tinyproxy

    for tool in docker tinyproxy socat flock; do
    	if ! command -v "$tool" >/dev/null 2>&1; then
    		echo "[netless] required host tool missing: $tool"
    		exit 1
    	fi
    done

    REPO="$(cd "$(dirname "{{ justfile() }}")" && pwd -P)"
    RUN_DIR="$REPO/netless"

    if ! docker image inspect "{{ agent }}" >/dev/null 2>&1; then
    	echo "[netless] image '{{ agent }}' missing, building..."
    	{{ just_executable() }} -f {{ justfile() }} build
    fi

    mkdir -p "$RUN_DIR"
    exec 9>"$RUN_DIR/lock"
    if ! flock -n 9; then
    	echo "[netless] another netless session is already running"
    	exit 1
    fi

    # the lock is ours: pids left behind belong to a killed session
    if [[ -f "$RUN_DIR/pids" ]]; then
    	while read -r pid; do
    		if [[ -n "$pid" && -r "/proc/$pid/comm" && "$(<"/proc/$pid/comm")" =~ ^(tinyproxy|socat)$ ]]; then
    			kill "$pid" 2>/dev/null || true
    		fi
    	done <"$RUN_DIR/pids"
    	rm -f "$RUN_DIR/pids"
    fi
    rm -f "$RUN_DIR"/*.sock

    # free host loopback port for the proxy; dynamic so a leftover proxy can never wedge a session
    TP_PORT_START="$TP_PORT"
    while (exec 3<>"/dev/tcp/127.0.0.1/$TP_PORT") 2>/dev/null; do
    	TP_PORT=$((TP_PORT + 1))
    	if ((TP_PORT > TP_PORT_START + 12)); then
    		echo "[netless] no free host port in range $TP_PORT_START-$((TP_PORT_START + 12))"
    		exit 1
    	fi
    done

    # tinyproxy: allowlist-only CONNECT proxy (default deny), reachable from host loopback only
    {
    	printf 'Port %s\n' "$TP_PORT"
    	printf 'Listen 127.0.0.1\n'
    	printf 'Timeout 1800\n'
    	printf 'LogLevel Connect\n'
    	printf 'LogFile "%s"\n' "$RUN_DIR/tinyproxy.log"
    	printf 'MaxClients 256\n'
    	printf 'Allow 127.0.0.1\n'
    	printf 'Filter "%s"\n' "$RUN_DIR/filter"
    	printf 'FilterType fnmatch\n'
    	printf 'FilterDefaultDeny Yes\n'
    	printf 'ConnectPort 443\n'
    } >"$RUN_DIR/tinyproxy.conf"
    printf '# allowlist: fnmatch patterns, one host per line; everything else is denied\n' >"$RUN_DIR/filter"
    IFS=',' read -r -a allow_entries <<<"$ALLOW"
    for entry in "${allow_entries[@]}"; do
    	entry="${entry//[[:space:]]/}"
    	entry="${entry%%:*}" # tolerate host:port entries; ports are fixed by ConnectPort
    	[[ -n "$entry" ]] && printf '%s\n' "$entry" >>"$RUN_DIR/filter"
    done

    printf '%s\n' "$(date -Is) netless session start: allow=$ALLOW local=$LOCAL_TARGET" >>"$RUN_DIR/tinyproxy.log"
    tinyproxy -dc "$RUN_DIR/tinyproxy.conf" >>"$RUN_DIR/tinyproxy.log" 2>&1 &
    TP_PID=$!
    socat "UNIX-LISTEN:$RUN_DIR/proxy.sock,fork,reuseaddr,mode=600" "TCP:127.0.0.1:$TP_PORT" >>"$RUN_DIR/socat.log" 2>&1 &
    PROXY_PID=$!
    socat "UNIX-LISTEN:$RUN_DIR/local.sock,fork,reuseaddr,mode=600" "TCP:$LOCAL_TARGET" >>"$RUN_DIR/socat.log" 2>&1 &
    LOCAL_PID=$!
    printf '%s %s %s\n' "$TP_PID" "$PROXY_PID" "$LOCAL_PID" >"$RUN_DIR/pids"

    cleanup() {
    	kill "$TP_PID" "$PROXY_PID" "$LOCAL_PID" 2>/dev/null || true
    	rm -f "$RUN_DIR"/*.sock "$RUN_DIR/pids"
    }
    trap cleanup EXIT

    for _ in $(seq 1 50); do
    	[[ -S "$RUN_DIR/proxy.sock" && -S "$RUN_DIR/local.sock" ]] && break
    	sleep 0.1
    done
    if [[ ! -S "$RUN_DIR/proxy.sock" || ! -S "$RUN_DIR/local.sock" ]]; then
    	echo "[netless] socat bridges failed to start (see $RUN_DIR/socat.log)"
    	exit 1
    fi
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$TP_PORT") 2>/dev/null; then
    	echo "[netless] tinyproxy did not come up on 127.0.0.1:$TP_PORT (see $RUN_DIR/tinyproxy.log)"
    	exit 1
    fi
    if ! (exec 3<>"/dev/tcp/${LOCAL_TARGET%:*}/${LOCAL_TARGET##*:}") 2>/dev/null; then
    	echo "[netless] warning: local model server $LOCAL_TARGET is not reachable from the host; local/* models will fail"
    fi

    echo "[netless] network: none; reachable: $ALLOW via https proxy, $LOCAL_TARGET via socket bridge"
    echo "[netless] audit log: $RUN_DIR/tinyproxy.log"

    # no exec here: the EXIT trap kills the host tunnels after the container stops
    {{ just_executable() }} -f {{ justfile() }} __docker none "$PROXY_PORT" "$LOCAL_PORT" "$@"

# private: shared `docker run`; args: <network> <proxy_port> <local_port> [command args...]
[no-cd]
__docker network="host" proxy_port="" local_port="" *args:
    #!/usr/bin/env bash
    set -euo pipefail

    export CWD="$(realpath -L "$PWD")"; export WSD="${CWD//\//-}"
    # repo path inside the container; netless sockets come in through the ~/.omp bind mount
    CONTAINER_DIR="/home/agent/.{{ agent }}/docker/netless"

    # WARNING: /tmp must be with exec permissions for just/go/etc. to work
    FLAGS=(
    	--tmpfs="/tmp:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g"
    	--tmpfs="/var/tmp:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m"
    	--tmpfs="/run:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m"
    	--tmpfs="/home/agent/.ansible:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g"
    	--tmpfs="/home/agent/.cache:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g"
    	--tmpfs="/home/agent/.config:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m"
    	--tmpfs="/home/agent/.local/state:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m"
    	--tmpfs="/home/agent/.yarn:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g"
    	--tmpfs="/home/agent/.rustup:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=4g"
    	--tmpfs="/home/agent/.cargo:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=4g"
    	--tmpfs="/home/agent/go:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g"
    	--ipc=private
    	--read-only
    	--security-opt=no-new-privileges:true
    	--cap-drop=ALL
    	--memory=8g
    	--memory-swap=8g
    	--cpus=8
    	--pids-limit=1024
    	--user="{{ uid }}:{{ gid }}"
    	--mount "type=bind,src={{ home }}/.{{ agent }},dst=/home/agent/.{{ agent }}"
    	--mount "type=bind,src=$CWD,dst=/home/agent/workspace/$WSD"
    	--workdir "/home/agent/workspace/$WSD"
    	--health-cmd="ps aux | grep -q {{ agent }} || exit 1"
    	--health-interval=30s
    	--network="{{ network }}"
    )

    CMD=("{{ agent }}")
    if [[ -n "{{ proxy_port }}" ]]; then
    	FLAGS+=(
    		--env "HTTPS_PROXY=http://127.0.0.1:{{ proxy_port }}"
    		--env "https_proxy=http://127.0.0.1:{{ proxy_port }}"
    		--env "NO_PROXY=127.0.0.1,localhost,::1"
    		--env "no_proxy=127.0.0.1,localhost,::1"
    	)
    	CONTAINER_SCRIPT="$(printf '%s\n' \
    		"socat TCP-LISTEN:{{ proxy_port }},bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:$CONTAINER_DIR/proxy.sock 2>>/tmp/netless-socat.log &" \
    		"socat TCP-LISTEN:{{ local_port }},bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:$CONTAINER_DIR/local.sock 2>>/tmp/netless-socat.log &" \
    		'exec "$@"')"
    	CMD=(sh -c "$CONTAINER_SCRIPT" sh "{{ agent }}")
    fi

    docker run -it --rm "${FLAGS[@]}" "{{ agent }}" "${CMD[@]}" "${@:4}"

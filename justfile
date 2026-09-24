uid := `id -u`
gid := `id -g`
home := `echo $HOME`
agent := "omp"

build *args:
	docker build -t {{ agent }} {{ args }} .

# run agent in docker sandbox
[no-cd]
run *args:
	#!/usr/bin/env sh
	set -euo pipefail
	# explicit update
	if [[ "{{ args }}" == "update" ]]; then
		echo "[{{ agent }} sandbox] updating..."
		{{ just_executable() }} -f {{ justfile() }} build --pull --no-cache
		echo "[{{ agent }} sandbox] ready to run"
		# re-run without args
		{{ just_executable() }} -f {{ justfile() }} run
		exit
	fi
	# potential first run when no image exists yet
	if ! docker image inspect {{ agent }} &> /dev/null; then
		echo "[{{ agent }} sandbox] building..."
		{{ just_executable() }} -f {{ justfile() }} build
		echo "[{{ agent }} sandbox] ready to run"
		# re-run
		{{ just_executable() }} -f {{ justfile() }} run {{ args }}
	fi

	# avoid missing sessions between symlink vs real path working dir
	export CWD=$(realpath -L $PWD)
	export WSD=${CWD//\//-}

	# WARNING1: --network=host is required for local models only. REPLACE with `--network=none`
	# WARNING2: /tmp must be with exec permissions for just/go/etc. to work
	docker run -it --rm \
	--tmpfs=/tmp:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/var/tmp:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/run:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/home/agent/.ansible:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/.cache:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/.config:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/home/agent/.local/state:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/home/agent/.yarn:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/.cargo:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/go:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--ipc=private \
	--read-only \
	--security-opt=no-new-privileges:true \
	--cap-drop=ALL \
	--network=host \
	--memory=8g \
	--memory-swap=8g \
	--cpus=8 \
	--pids-limit=1024 \
	--user={{ uid }}:{{ gid }} \
	--mount type=bind,src={{ home }}/.{{ agent }},dst=/home/agent/.{{ agent }} \
	--mount type=bind,src=$CWD,dst=/home/agent/workspace/$WSD \
	--workdir /home/agent/workspace/$WSD \
	--health-cmd="ps aux | grep -q {{ agent }} || exit 1" \
	--health-interval=30s \
	{{ agent }} {{ agent }} {{ args }}

uid := `id -u`
gid := `id -g`
home := `echo $HOME`
agent := "omp"

build:
	docker build -t {{ agent }} .

# run agent in docker sandbox
[no-cd]
run *args:
	#!/usr/bin/env sh
	set -euo pipefail
	# explicit update
	if [[ "{{ args }}" == "update" ]]; then
		echo "[{{ agent }} sandbox] updating..."
		{{ just_executable() }} -f {{ justfile() }} build
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

	# WARNING1: --network=host is required for local models only. REPLACE with `--network=none`
	# WARNING2: /tmp must be with exec permissions for just/go/etc. to work
	docker run -it --rm \
	--tmpfs=/tmp:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/var/tmp:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/run:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/home/agent/.ansible:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/.cache:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--tmpfs=/home/agent/.config:rw,noexec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=100m \
	--tmpfs=/home/agent/go:rw,exec,nosuid,nodev,uid={{ uid }},gid={{ gid }},size=2g \
	--ipc=private \
	--read-only \
	--security-opt=no-new-privileges:true \
	--cap-drop=ALL \
	--network=host \
	--memory=4g \
	--memory-swap=4g \
	--cpus=4 \
	--pids-limit=512 \
	--user={{ uid }}:{{ gid }} \
	--mount type=bind,src={{ home }}/.{{ agent }},dst=/home/agent/.{{ agent }} \
	--mount type=bind,src=$PWD,dst=/home/agent/workspace/${PWD//\//-} \
	--workdir /home/agent/workspace/${PWD//\//-} \
	--health-cmd="ps aux | grep -q {{ agent }} || exit 1" \
	--health-interval=30s \
	{{ agent }} {{ agent }} {{ args }}

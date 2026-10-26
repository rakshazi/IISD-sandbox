FROM fedora:latest

ARG HOST_UID=1000
ARG HOST_GID=1000

# arbitrary system deps
ARG DNF_DEPS_SYSTEM="unzip jq git just hugo reuse socat procps-ng"
# agent (omp by default) deps (like chrome deps)
ARG DNF_DEPS_AGENT="nss nss-util nspr atk at-spi2-atk at-spi2-core cairo cups-libs dbus-libs \
	libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb libxkbcommon \
		alsa-lib pango fontconfig liberation-fonts"
# go deps
ARG DNF_DEPS_GO="golang gopls golangci-lint libolm libolm-devel"
# ansible deps
ARG DNF_DEPS_ANSIBLE="python3 python3-pip python3-lsp-server ansible-core ansible-lint ansible"
# node deps
ARG DNF_DEPS_NODE="nodejs24 typescript yarnpkg"
# rust deps. rustup manages toolchains: auto-downloaded on first use, honors rust-toolchain.toml
ARG DNF_DEPS_RUST="rustup clang cmake ninja gcc-c++ pkgconf sqlite-devel"
# qt6 deps. -devel provides cmake configs + headers and pulls the runtime twin
ARG DNF_DEPS_QT6="qt6-qtbase-devel qt6-qtbase-private-devel \
	qt6-qtdeclarative-devel qt6-qtmultimedia-devel qt6-qtsvg-devel qt6-qttools-devel \
	libsecret-devel"
# security deps: scanners, secret detection, structural search, etc.
ARG DNF_DEPS_SECURITY="gosec staticcheck govulncheck gitleaks trivy grype hadolint ShellCheck ripgrep bubblewrap openssl openssh-clients openssh-server"
# all deps to install. If you don't need something, just remove it from the list
ENV DNF_DEPS="$DNF_DEPS_SYSTEM $DNF_DEPS_AGENT $DNF_DEPS_GO $DNF_DEPS_ANSIBLE $DNF_DEPS_NODE $DNF_DEPS_RUST $DNF_DEPS_QT6 $DNF_DEPS_SECURITY"

ENV HOME=/home/agent
ENV GOPATH=$HOME/go
ENV CARGO_HOME=$HOME/.cargo
ENV RUSTUP_HOME=$HOME/.rustup
ENV GOCACHE=/tmp
ENV PATH=$CARGO_HOME/bin:$GOPATH/bin:$HOME/.local/bin:$PATH

# Security databases live on the host mount ~/.omp/cache, not in the image.
# Refresh them with the commands in README.md while the sandbox has network access.
ENV TRIVY_CACHE_DIR=/home/agent/.omp/cache/trivy
ENV GRYPE_DB_CACHE_DIR=/home/agent/.omp/cache/grype
ENV GOVULNDB=/home/agent/.omp/cache/govulndb
ENV TRIVY_SKIP_DB_UPDATE=true
ENV TRIVY_SKIP_JAVA_DB_UPDATE=true
ENV GRYPE_DB_AUTO_UPDATE=false
ENV GRYPE_DB_VALIDATE_AGE=false
ENV SEMGREP_SETTINGS_FILE=/home/agent/.omp/cache/semgrep/settings.yml
ENV SEMGREP_LOG_FILE=/home/agent/.omp/logs/semgrep.log

RUN (getent group "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" agent) && \
	(getent passwd "${HOST_UID}" >/dev/null || useradd -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/bash -M -d "$HOME" agent) && \
	getent passwd "${HOST_UID}" >/dev/null && \
	mkdir -p $HOME/workspace && \
	mkdir -p $HOME/.local/bin && \
	mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN echo "Installing system packages..." && \
	dnf install -yq $DNF_DEPS && \
	echo "Cleaning up..." && \
	dnf clean all -q && \
	echo "[agent] Installing oh-my-pi..." && \
	export BINARY_URL="https://github.com/can1357/oh-my-pi/releases/latest/download/omp-linux-x64" && \
	curl -fsSL --connect-timeout 10 "$BINARY_URL" -o "${HOME}/.local/bin/omp" && \
	chmod +x "${HOME}/.local/bin/omp" && \
	echo "[qt6] Installing mise (tool version manager for prek)..." && \
	curl -fsSL https://mise.run | sh && \
	echo "[go] Installing mockery..." && \
	go install github.com/vektra/mockery/v3@latest && \
	echo "[go] Installing swag..." && \
	go install github.com/swaggo/swag/cmd/swag@latest && \
	echo "[security] Installing semgrep..." && \
	mkdir -p $HOME/.local/venvs && \
	python3 -m venv $HOME/.local/venvs/semgrep && \
	$HOME/.local/venvs/semgrep/bin/pip install --no-cache-dir semgrep==1.182.1 && \
	ln -s $HOME/.local/venvs/semgrep/bin/semgrep $HOME/.local/bin/semgrep && \
	echo "[security] Installing actionlint..." && \
	go install github.com/rhysd/actionlint/cmd/actionlint@latest && \
	mv $GOPATH/bin/swag $HOME/.local/bin/swag && \
	mv $GOPATH/bin/mockery $HOME/.local/bin/mockery && \
	mv $GOPATH/bin/actionlint $HOME/.local/bin/actionlint && \
	printf '%s\n' '#!/bin/sh' 'set -eu' 'if [ ! -d "${GOVULNDB:-}" ]; then' '  echo "Go vulnerability database missing at ${GOVULNDB:-<unset>}; run the README security DB update command." >&2' '  exit 2' 'fi' 'exec /usr/bin/govulncheck -db "file://${GOVULNDB}" "$@"' > $HOME/.local/bin/govulncheck && \
	chmod +x $HOME/.local/bin/govulncheck && \
	chown -R "${HOST_UID}:${HOST_GID}" $HOME

WORKDIR /home/agent/workspace
USER ${HOST_UID}:${HOST_GID}

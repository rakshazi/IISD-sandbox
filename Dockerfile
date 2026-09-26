FROM fedora:latest

# arbitrary system deps
ARG DNF_DEPS_SYSTEM="unzip jq git just hugo reuse"
# agent (omp by default) deps (like chrome deps)
ARG DNF_DEPS_AGENT="nss nss-util nspr atk at-spi2-atk at-spi2-core cairo cups-libs dbus-libs \
	libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb libxkbcommon \
		alsa-lib pango fontconfig liberation-fonts"
# go deps
ARG DNF_DEPS_GO="golang golangci-lint libolm libolm-devel"
# ansible deps
ARG DNF_DEPS_ANSIBLE="python3 python3-pip ansible-core ansible-lint ansible"
# node deps
ARG DNF_DEPS_NODE="nodejs24 yarnpkg"
# rust deps. rustup manages toolchains: auto-downloaded on first use, honors rust-toolchain.toml
ARG DNF_DEPS_RUST="rustup cmake ninja gcc-c++ pkgconf sqlite-devel"
# qt6 deps. -devel provides cmake configs + headers and pulls the runtime twin
ARG DNF_DEPS_QT6="qt6-qtbase-devel qt6-qtbase-private-devel \
	qt6-qtdeclarative-devel qt6-qtmultimedia-devel qt6-qtsvg-devel qt6-qttools-devel \
	libsecret-devel"
# all deps to install. If you don't need something, just remove it from the list
ENV DNF_DEPS="$DNF_DEPS_SYSTEM $DNF_DEPS_AGENT $DNF_DEPS_GO $DNF_DEPS_ANSIBLE $DNF_DEPS_NODE $DNF_DEPS_RUST $DNF_DEPS_QT6"

ENV HOME=/home/agent
ENV GOPATH=$HOME/go
ENV CARGO_HOME=$HOME/.cargo
ENV RUSTUP_HOME=$HOME/.rustup
ENV GOCACHE=/tmp
ENV PATH=$CARGO_HOME/bin:$GOPATH/bin:$HOME/.local/bin:$PATH

RUN groupadd -g 10001 agent && \
	useradd -u 10001 -g agent -s /bin/bash -M -d $HOME agent && \
	mkdir -p $HOME/workspace && \
	mkdir -p $HOME/.local/bin && \
	mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN echo "Installing system packages..." && \
	dnf install -yq $DNF_DEPS && \
	echo "Cleaning up..." && \
	dnf clean all -q && \
	echo "[agent] Installing oh-my-pi..." && \
	export RELEASE_JSON=$(curl -fsSL --connect-timeout 10 --max-time 60 "https://api.github.com/repos/can1357/oh-my-pi/releases/latest") && \
  export LATEST=$(echo "$RELEASE_JSON" | grep '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') && \
	export BINARY_URL="https://github.com/can1357/oh-my-pi/releases/download/${LATEST}/omp-linux-x64" && \
	curl -fsSL --connect-timeout 10 "$BINARY_URL" -o "${HOME}/.local/bin/omp" && \
	chmod +x "${HOME}/.local/bin/omp" && \
	echo "[qt6] Installing mise (tool version manager for prek)..." && \
	curl -fsSL https://mise.run | sh && \
	echo "[go] Installing mockery..." && \
	go install github.com/vektra/mockery/v3@latest && \
	echo "[go] Installing swag..." && \
	go install github.com/swaggo/swag/cmd/swag@latest && \
	mv $GOPATH/bin/swag $HOME/.local/bin/swag && \
	mv $GOPATH/bin/mockery $HOME/.local/bin/mockery && \
	chown -R agent:agent $HOME

WORKDIR /home/agent/workspace
USER agent

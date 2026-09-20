FROM fedora:latest

ENV HOME=/home/agent
ENV GOPATH=$HOME/go
ENV GOCACHE=/tmp
ENV PATH=$GOPATH/bin:$HOME/.local/bin:$PATH

RUN groupadd -g 10001 agent && \
	useradd -u 10001 -g agent -s /bin/bash -M -d $HOME agent && \
	mkdir -p $HOME/workspace && \
	mkdir -p $HOME/.local/bin && \
	mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN echo "Installing system packages..." && \
	dnf install -yq golang python3 python3-pip nodejs libarchive tar unzip jq git just \
	golangci-lint ansible-core ansible ansible-lint && \
	echo "Installing Chrome runtime deps (OMP browser tool, headless Chrome-for-Testing)..." && \
	dnf install -yq nss nss-util nspr atk at-spi2-atk at-spi2-core cairo cups-libs dbus-libs \
		libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb libxkbcommon \
		mesa-libgbm alsa-lib pango fontconfig liberation-fonts && \
	dnf clean all -q && \
	echo "Installing oh-my-pi..." && \
	export RELEASE_JSON=$(curl -fsSL --connect-timeout 10 --max-time 60 "https://api.github.com/repos/can1357/oh-my-pi/releases/latest") && \
  export LATEST=$(echo "$RELEASE_JSON" | grep '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') && \
	export BINARY_URL="https://github.com/can1357/oh-my-pi/releases/download/${LATEST}/omp-linux-x64" && \
	curl -fsSL --connect-timeout 10 "$BINARY_URL" -o "${HOME}/.local/bin/omp" && \
	chmod +x "${HOME}/.local/bin/omp" && \
	echo "Installing mockery..." && \
	go install github.com/vektra/mockery/v3@latest && \
	echo "Installing swag..." && \
	go install github.com/swaggo/swag/cmd/swag@latest && \
	mv $GOPATH/bin/swag $HOME/.local/bin/swag && \
	mv $GOPATH/bin/mockery $HOME/.local/bin/mockery && \
	chown -R agent:agent $HOME

WORKDIR /home/agent/workspace
USER agent

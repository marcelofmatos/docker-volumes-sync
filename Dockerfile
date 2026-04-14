FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        rsync \
        openssh-client \
        curl \
        ca-certificates \
    && DPKG_ARCH=$(dpkg --print-architecture) \
    && case "$DPKG_ARCH" in \
        amd64)         GUM_ARCH="x86_64" ;; \
        arm64)         GUM_ARCH="arm64"  ;; \
        armhf|armv7l)  GUM_ARCH="armv7"  ;; \
        *)             echo "Arquitetura não suportada: $DPKG_ARCH" && exit 1 ;; \
       esac \
    && GUM_VERSION=$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/') \
    && curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${GUM_ARCH}.tar.gz" \
        | tar xz -C /usr/local/bin gum \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY usr /usr

RUN chmod +x /usr/local/bin/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/volumes-sync-tui.sh"]

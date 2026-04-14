FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        rsync \
        openssh-client \
        curl \
        ca-certificates \
    && DPKG_ARCH=$(dpkg --print-architecture) \
    && GUM_VERSION=$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/') \
    && curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_${DPKG_ARCH}.deb" \
        -o /tmp/gum.deb \
    && dpkg -i /tmp/gum.deb \
    && rm /tmp/gum.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY usr /usr

RUN chmod +x /usr/local/bin/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/volumes-sync-tui.sh"]

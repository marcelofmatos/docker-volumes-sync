FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        rsync \
        openssh-client \
        dialog \
        whiptail \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY usr /usr

RUN chmod +x /usr/local/bin/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/volumes-sync.sh"]

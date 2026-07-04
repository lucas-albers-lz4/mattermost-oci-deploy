FROM ubuntu:noble

ARG MM_VERSION=11.8.2
ARG MM_TARBALL_SHA256=
ENV PATH="/mattermost/bin:${PATH}" \
    MM_INSTALL_TYPE=docker \
    MM_CONFIG=/mattermost/config/config.json

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        netcat-openbsd \
        tzdata \
        mailcap \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL "https://releases.mattermost.com/${MM_VERSION}/mattermost-${MM_VERSION}-linux-arm64.tar.gz?src=oci-arm64" -o /tmp/mattermost.tar.gz; \
    if [ -n "$MM_TARBALL_SHA256" ]; then echo "$MM_TARBALL_SHA256  /tmp/mattermost.tar.gz" | sha256sum -c -; fi; \
    tar -xzf /tmp/mattermost.tar.gz -C /; \
    rm -f /tmp/mattermost.tar.gz; \
    mkdir -p /mattermost/data /mattermost/logs /mattermost/config /mattermost/plugins /mattermost/client/plugins /mattermost/bleve-indexes; \
    cp /mattermost/config/config.json /config.json.save; \
    rm -f /mattermost/config/config.json; \
    groupadd -g 2000 mattermost; \
    useradd -u 2000 -g 2000 -d /mattermost -s /usr/sbin/nologin mattermost; \
    chown -R mattermost:mattermost /mattermost /config.json.save

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

USER mattermost
WORKDIR /mattermost
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
CMD ["mattermost"]

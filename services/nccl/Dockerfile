FROM nvidia/cuda:13.0.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive

# Container user
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_NAME=ubuntu

# uv version. Pin this so image builds are reproducible.
ARG UV_VERSION=0.12.13

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/home/app/.local/bin:/opt/venv/bin:$PATH \
    VIRTUAL_ENV=/opt/venv

# ---------------------------------------------------------------------------
# Base OS
# ---------------------------------------------------------------------------

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        ca-certificates \
        curl \
        git \
        sudo \
        zsh \
        tini \
        procps \
        iproute2 \
        less \
        nano \
        vim-tiny \
        && \
    rm -rf /var/lib/apt/lists/*


# ---------------------------------------------------------------------------
# uv
#
# Install uv system-wide. The standalone installer is the official
# installation method.
# ---------------------------------------------------------------------------

RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh \
        | env UV_UNMANAGED_INSTALL=/usr/local/bin sh && \
    uv --version


# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------

RUN mkdir -p /run/sshd /etc/ssh/authorized_keys && \
    chmod 755 /run/sshd && \
    chown ${USER_UID}:${USER_GID} /home/${USER_NAME}

# Host keys are generated at container startup rather than being baked into
# the image.

# SSH configuration:
# - root cannot log in
# - password authentication is disabled
# - public-key authentication is enabled
# - user 1000 gets a normal interactive shell
RUN printf '%s\n' \
        'PermitRootLogin no' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'PubkeyAuthentication yes' \
        'UsePAM no' \
        'X11Forwarding no' \
        'AllowAgentForwarding yes' \
        'AllowTcpForwarding yes' \
        'PrintMotd no' \
        'UseDNS no' \
        > /etc/ssh/sshd_config.d/container.conf

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /apps

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
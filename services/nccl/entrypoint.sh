#!/usr/bin/env bash

set -euo pipefail

USER_NAME="ubuntu"
USER_UID="1000"
USER_HOME="/home/${USER_NAME}"

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A
fi

if [ -f /etc/ssh/authorized_keys/$USER_NAME ]; then
    install -d -m 700 \
        -o "${USER_UID}" \
        -g "${USER_UID}" \
        "${USER_HOME}/.ssh"

    install -m 600 \
        -o "${USER_UID}" \
        -g "${USER_UID}" \
        /etc/ssh/authorized_keys/$USER_NAME \
        "${USER_HOME}/.ssh/authorized_keys"
fi

chown "${USER_UID}:${USER_UID}" "${USER_HOME}"

if [ -d "${USER_HOME}/.ssh" ]; then
    chown "${USER_UID}:${USER_UID}" "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
fi

if passwd -S ubuntu | awk '{print $2}' | grep -q '^L$'; then
    RANDOM_PASSWORD="$(head -c 48 /dev/urandom | base64 -w0)"
    PASSWORD_HASH="$(openssl passwd -6 "$RANDOM_PASSWORD")"
    usermod -p "$PASSWORD_HASH" ubuntu
fi

/usr/sbin/sshd -t

echo "Starting SSH server..."
echo "User: ${USER_NAME} (UID ${USER_UID})"
echo "Listening on port 22"

/usr/sbin/sshd -D -e
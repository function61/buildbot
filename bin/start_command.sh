#!/bin/bash -eu

echo "# Generating host key"

ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -b 4096 -t rsa

echo "# Setting up inbound SSH key (used to initiate builds)"

echo "$SSH_PUBKEY_IN_INITIATE_BUILDS" >> /root/.ssh/authorized_keys

echo "# exec()'ing sshd"

echo "Expect further output to be from SSH daemon"

exec /usr/sbin/sshd -D

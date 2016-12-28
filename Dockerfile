FROM joonas/alpine:f4fddc471ec2

# grep is needed because busybox's grep does not support --line-buffered
# busybox's grep outputs results in huge chunks, which is not ok for interactively viewing the build output

# this shit needs to be cached aggressively
RUN apk add --update curl mercurial git bash openssh openssh-client grep

# RUN apk add python py-pip && pip install docker-squash==1.0.0rc5

# we could do tar --strip-components=1 but busybox's tar does not support that
RUN mkdir /tmp/dkrinst \
	&& curl --fail -s https://get.docker.com/builds/Linux/x86_64/docker-1.12.1.tgz | tar -C /tmp/dkrinst -xz \
	&& mv /tmp/dkrinst/docker/* /usr/bin \
	&& rm -rf /tmp/dkrinst

RUN mkdir /var/run/sshd \
	&& mkdir -p /root/.ssh \
	&& chmod 700 /root/.ssh \
	&& touch /root/.ssh/authorized_keys \
	&& touch /root/.ssh/id_rsa \
	&& chmod 600 /root/.ssh/* \
	&& chown -Rf root:root /root/.ssh

EXPOSE 22

ADD bin/start_command.sh bin/buildbot.sh /bin/

RUN chmod +x /bin/start_command.sh /bin/buildbot.sh

CMD start_command.sh

VOLUME ["/buildbot-work"]

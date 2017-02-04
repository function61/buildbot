Buildbot?
---------

Buildbot is a build server like Jenkins, but stateless, **super lightweight** and aimed for building Dockerized apps.

All state management is left to the party that starts the build job, e.g. supplying repository address & credentials,
Docker registry credentials etc.

Optional build-in-a-separate-container -feature
-----------------------------------------------

Buildbot supports a model where the build environment is separated from the resulting Docker image.

A simple example: you have a static website generator (based on [Jekyll](https://jekyllrb.com/)
or [Hugo](https://gohugo.io/)). Ubuntu image + Jekyll is 359.9 MB so add your HTTP server and website content on top of that.

With Buildbot you can build your website inside that 359.9 MB Jekyll-based **build container**, BUT take the
resulting artifact (= static website) and put it in the resulting container with only a HTTP server and the website content
(my blog weighs in at 19.93 MB).


Running it
----------

```
$ docker run -d --name buildbot \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v /data/buildbot-work:/buildbot-work \
	-e "SSH_PUBKEY_IN_INITIATE_BUILDS=ssh-rsa AAAA....lQ7+Dja3Q==" \
	fn61/buildbot
```

Notes:

- `SSH_PUBKEY_IN_INITIATE_BUILDS` is SSH public key of the account that dials in via SSH to run builds
- `/var/run/docker.sock` is required for image pulls/builds/pushes AND for in-container builds
- `/data/buildbot-work` is required for in-container builds

Usage:

```
$ docker exec -it buildbot buildbot.sh
Usage:
        --service_id hello-world

        Repo
        --repo ssh://hg@bitbucket.org/joonas_fi/hello-repo
        --repo_auth_key AAAAB3NzaC1yc2EAAAADAQABAAACAQDN... (RSA PRIVATE KEY as base64)
        --revision 31c7fda7aa51d1e289a1e8bd4077506c93fa9820

        Docker image
        --image 329074924855.dkr.ecr.us-east-1.amazonaws.com/hello-world
        --tag latest

        Docker registry
        --docker_login_cmd "docker login -u ... -p ... 329074924855.dkr.ecr.us-east-1.amazonaws.com"
        --docker_login_cache eW91ciBtb20gaXMgYSBmYXQgc2xvYgo= (base64-encoded chunk from ~/.docker/config.json)

# actual job submit
$ ssh root@ip-of-buildbot buildbot.sh --service_id foo --repo git@github.com:function61/sql2json.git --revision ....
```


TODO / roadmap
--------------

- Push additional tags at the same time (think exact revision tag AND "latest" release)
- instead of SSH connectivity, implement as HTTP API? The hardest part would be streaming
  stdout/stderr while build progresses, and return code at the end.


Support / contact
-----------------

Basic support (no guarantees) for issues / feature requests via GitHub issues.

Paid support is available via [function61.com/consulting](https://function61.com/consulting/)

Contact options (email, Twitter etc.) at [function61.com](https://function61.com/)

#!/bin/bash -eu

# FIXME: for some reason, we've to fix $PATH
# this seems not be an issue when interactively logging in via SSH, which is a WTF
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# thanks https://gist.github.com/cosimo/3760587
OPTS=`getopt -n 'parse-options' --options : --long image:,docker_login_cmd:,docker_login_cache:,tag:,repo:,repo_auth_key:,revision:,service_id: -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

eval set -- "$OPTS"

service_id=""
revision=""
image=""
docker_tag=""
repo=""
repo_auth_key=""
docker_login_cache="" # base64-encoded chunk to search from Docker config file to see if the login is already stored
docker_login_cmd=""

while true; do
  case "$1" in
    --service_id ) service_id="$2"; shift; shift ;;
    --revision ) revision="$2"; shift; shift ;;
    --image ) image="$2"; shift; shift ;;
    --tag ) docker_tag="$2"; shift; shift ;;
    --repo ) repo="$2"; shift; shift ;;
    --repo_auth_key ) repo_auth_key="$2"; shift; shift ;;
    --docker_login_cache ) docker_login_cache="$2"; shift; shift ;;
    --docker_login_cmd ) docker_login_cmd="$2"; shift; shift ;;
    -- ) shift; break ;;
    * ) echo "invalid args"; break ;;
  esac
done

if [ -z "$service_id" ] || [ -z "$revision" ] || [ -z "$docker_tag" ] || [ -z "$image" ] || [ -z "$docker_login_cache" ] || [ -z "$docker_login_cmd" ] || [ -z "$repo_auth_key" ]; then
	echo -e "Usage:" \
		"\n	--service_id hello-world" \
		"\n" \
		"\n	Repo" \
		"\n	--repo ssh://hg@bitbucket.org/joonas_fi/hello-repo" \
		"\n	--repo_auth_key AAAAB3NzaC1yc2EAAAADAQABAAACAQDN... (RSA PRIVATE KEY as base64)" \
		"\n	--revision 31c7fda7aa51d1e289a1e8bd4077506c93fa9820" \
		"\n" \
		"\n	Docker image" \
		"\n	--image 329074924855.dkr.ecr.us-east-1.amazonaws.com/hello-world" \
		"\n	--tag latest" \
		"\n" \
		"\n	Docker registry" \
		'\n	--docker_login_cmd "docker login -u ... -p ... 329074924855.dkr.ecr.us-east-1.amazonaws.com"' \
		"\n	--docker_login_cache eW91ciBtb20gaXMgYSBmYXQgc2xvYgo= (base64-encoded chunk from ~/.docker/config.json)" \
		"\n"
	exit 1
fi

# const config
vcs_privkey_path="/buildbot-work/$service_id.id_rsa"
ssh_command_for_hg="ssh -i $vcs_privkey_path -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# computed variables
workdir_location="/buildbot-work/$service_id"
workdir_location_host_perspective="/data${workdir_location}"
fully_qualified_image_name="$image:$docker_tag"

if [[ $repo == *"git"* ]] # FIXME
then
	repotype="git"
else
	repotype="hg"
fi

# these variables are written to later
builder_image_name=""
squash_until_from_layer=""
image_from=""
test_in_container_entrypoint=""
have_build_script=0

function log_seconds {
	echo -n "${SECONDS}s | "
}

function print_work_summary {
	log_seconds
	echo "# print_work_summary: $fully_qualified_image_name"

	echo "Building $revision from $repo"

	# sensitive fields
	# echo repo_auth_key=$repo_auth_key
	# echo docker_login_cache=$docker_login_cache
	# echo docker_login_cmd=$docker_login_cmd
}

function configure_repo_auth_key {
	log_seconds
	echo "# configure_repo_auth_key"

	echo -n "$repo_auth_key" | base64 -d > "$vcs_privkey_path"
	chmod 700 "$vcs_privkey_path"
}

function login_to_docker_registry {
	log_seconds
	echo -n "# login_to_docker_registry: "

	# have Docker config?
	if [ -f ~/.docker/config.json ]; then
		# our cache string is found on it?
		if [[ -n $(grep "$docker_login_cache" ~/.docker/config.json) ]]; then
			echo "auth cached -> skip"
			return
		fi
	fi

	echo "running $ docker login ..."
	eval "$docker_login_cmd"
}

function hg_clone {
	echo hg clone --ssh "$ssh_command_for_hg" --noupdate "$repo" "$workdir_location"
	hg clone --ssh "$ssh_command_for_hg" --noupdate "$repo" "$workdir_location"
}

function git_clone {
	echo GIT_SSH_COMMAND="$ssh_command_for_hg" git clone --no-checkout "$repo" "$workdir_location"
	GIT_SSH_COMMAND="$ssh_command_for_hg" git clone --no-checkout "$repo" "$workdir_location"
}

function clone_if_required {
	log_seconds
	echo -n "# clone_if_required: "

	if [ ! -d "$workdir_location" ]; then
		echo "repo does not exist. Cloning..."
		"${repotype}_clone"
	else
		echo "repo exists -> skip"
	fi
}

function cd_to_workdir {
	log_seconds
	echo "# cd_to_workdir: $workdir_location"
	cd "$workdir_location"
}

function hg_pull {
	set +e
	hg log -r "$revision" > /dev/null 2>/dev/null
	exists_rc=$?
	set -e

	if [ $exists_rc == 0 ]
	then
		echo "rev exists locally -> skip"
	else
		echo "pulling"

		# do not use the location stored in repo's metadata (= stored at clone-time),
		# because it might've been changed after that
		hg pull --ssh "$ssh_command_for_hg" "$repo"
	fi
}

function git_pull {
	if git cat-file -e "$revision^{commit}"; then
		echo "rev exists locally -> skip"
	else
		echo "pulling"

		GIT_SSH_COMMAND="$ssh_command_for_hg" git fetch
	fi
}

function pull_newest_changesets_if_required {
	log_seconds
	echo -n "# pull_newest_changesets_if_required: "
	"${repotype}_pull"
}

function hg_update_clean {
	hg update --clean "$revision" > /dev/null

	hg --config "extensions.purge=" purge --all
}

function git_update_clean {
	git clean --force -dx # -d = untracked files and directories, -x = do not respect .gitignore rules
	git checkout --force "$revision"
}

function update_and_clean_workdir_to_rev {
	log_seconds
	echo "# update_and_clean_workdir_to_rev"
	"${repotype}_update_clean"
}

# outputs file /VERSION at repo root
# if you want, you can have that file in your repo default to "latest" for example, so
# if you mount your host's dir inside the container it will always display "latest", but
# when running "pure" Docker image without any mounts for source code "live reload" purposes
# it will display the correct version
function provide_metadata_for_build {
	log_seconds
	echo "# provide_metadata_for_build"

	echo -n "$docker_tag" > VERSION
}

function detect_build_metadata {
	log_seconds
	echo "# detect_build_metadata"

	if [[ -f "$workdir_location/build.sh" ]]
	then
		have_build_script=1

		# temporary workaround for editing files on Windows with Mercurial will not allow to set the execute bit
		# http://stackoverflow.com/questions/4957721/mercurial-how-to-discard-all-local-changes-including-to-unversioned-files
		chmod +x "$workdir_location/build.sh"

		build_script_contents=$(cat "$workdir_location/build.sh")
		# http://stackoverflow.com/questions/12619720/multiline-regexp-matching-in-bash
		image_re='#build_inside_docker_image=([^
]+)'

		if [[ ! $build_script_contents =~ $image_re ]]; then echo "Unable to resolve: build_inside_docker_image" 1>&2; exit 1; fi

		builder_image_name="${BASH_REMATCH[1]}"
	fi

	dockerfile_contents=$(cat "$workdir_location/Dockerfile")

	test_in_container_entrypoint_re='#test_in_container_entrypoint=([^
]+)'

	if [[ $dockerfile_contents =~ $test_in_container_entrypoint_re ]]
	then
		test_in_container_entrypoint="${BASH_REMATCH[1]}"

		echo "found test_in_container_entrypoint=<$test_in_container_entrypoint>"
	fi

	# thanks https://github.com/goldmann/docker-squash/issues/96#issuecomment-222156314
	image_from=$(grep "^FROM" Dockerfile | awk '{print $2}')

	squash_until_from_layer="$image_from"
}

function run_build_in_container {
	log_seconds
	echo "# run_build_in_container"

	if [[ $have_build_script == 0 ]]
	then
		echo "No build script found (/build.sh) -> skipping in-container build"
		return
	fi

	docker run --rm -v "${workdir_location_host_perspective}/:/project" -w /project "$builder_image_name" ./build.sh
}

function build_docker_image {
	log_seconds
	echo "# build_docker_image"

	# exclude "sending build context" lines as it will spam the build log.
	# I didn't find any way to suppress those, even with $ docker build --quiet

	# do not allow continuing if "docker build" fails (grep returns 0 (=ok) exit code anyway)
	set -o pipefail

	docker build --tag "$fully_qualified_image_name" . | grep --line-buffered -v 'Sending build context to Docker daemon'
}

function test_in_container {
	log_seconds
	echo -n "# test_in_container: "

	if [[ -n "$test_in_container_entrypoint" ]]; then
		echo "invoking $test_in_container_entrypoint"
		docker run --rm "$fully_qualified_image_name" "$test_in_container_entrypoint"
	else
		echo "no in-container test entrypoint -> skip"
	fi
}

# this shit should've been built-in to Docker
function squash_redundant_layers {
	log_seconds
	echo "# squash_redundant_layers"

	# -t is the squashed tag name. if that is the same as the final argument,
	# the tag will be relocated to the squashed image

	docker-squash -f "$squash_until_from_layer" -t "$fully_qualified_image_name" "$fully_qualified_image_name" || true
}

function push_to_docker_registry {
	log_seconds
	echo "# push_to_docker_registry"
	docker push "$fully_qualified_image_name"
}

function build_result {
	log_seconds
	echo "# build_result"
	echo "Completed build of $fully_qualified_image_name"

	image_size=$(docker images --format '{{.Size}}' "$fully_qualified_image_name")
	echo "__build_result_meta {\"image_size\": \"$image_size\", \"image_from\": \"$image_from\"}"
}

# --- execute the actual workflow

print_work_summary
configure_repo_auth_key
login_to_docker_registry
clone_if_required
cd_to_workdir
pull_newest_changesets_if_required
update_and_clean_workdir_to_rev
detect_build_metadata
provide_metadata_for_build
run_build_in_container
build_docker_image

# before squash_redundant_layers for fail-fast reasons (squashing would be unnecessary if the test fails anyway)
test_in_container

# disable squashing for now, as there seem to be some fringe issues when pushing to AWS ECR
# squash_redundant_layers
push_to_docker_registry
build_result

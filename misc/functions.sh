#!/bin/sh
# functions.sh

error()
{
	local message=$1
	echo "$0: error: $message"
	exit 1
}

run_cmd()
{
	local may_fail=false
	if [ "_$1" = _--may-fail ]
	then
		may_fail=true
		shift
	fi

	echo "+ $*" >&2

	local ret=0
	"$@" || ret=$?

	test $ret -eq 0 \
	|| $may_fail && return $ret \
	|| error "command exited with status $ret"
}

apt_get_install()
{
	local sudo=$(test $(id -u) -eq 0 || echo sudo)

	# Lighten the "apt-get update" load
	$sudo rm -fv /etc/apt/apt.conf.d/50appstream
	$sudo rm -fv /etc/apt/apt.conf.d/50command-not-found
	$sudo rm -fv /etc/apt/sources.list.d/*{azure,microsoft}*

	local cfg=/etc/apt/apt.conf.d/95xtradeb
	test -f $cfg || $sudo tee $cfg << END
# Don't download translations
Acquire::Languages "none";

# Don't install recommended packages
APT::Install-Recommends "0";

# Don't use "Reading database ... X%" progress indicator
Dpkg::Use-Pty "false";
END

	echo ' '

	if [ "_$1" = _--update ]
	then
		run_cmd $sudo apt-get --error-on=any update
		echo ' '
		shift
	fi

	if ! run_cmd --may-fail $sudo apt-get -y --no-install-recommends install "$@"
	then
		# If the initial install fails, then we presume that the
		# package index is stale and needs updating.
		echo ' '
		run_cmd $sudo apt-get --error-on=any update
		echo ' '
		run_cmd $sudo apt-get -y --no-install-recommends install "$@"
	fi
}

check_changelog_version()
{
	local changelog=$1
	local expected_package=$2
	local expected_version=$3

	local dch_package=$(dpkg-parsechangelog -l $changelog -S Source)
	local dch_version=$(dpkg-parsechangelog -l $changelog -S Version)

	if [ "_$dch_package" != "_$expected_package" ]
	then
		echo 'error: name of package in changelog is not as expected:'
		echo "  expected: $expected_package"
		echo "     found: $dch_package"
		exit 1
	fi

	# The changelog version always includes the epoch, but the
	# expected version we were given might not
	local dch_version_noepoch=$(sed -r 's/^[0-9]+://' <<< $dch_version)

	if [ "_$dch_version" != "_$expected_version" -a "_$dch_version_noepoch" != "_$expected_version" ]
	then
		echo 'error: version in changelog is not as expected:'
		echo "  expected: $expected_version"
		echo "     found: $dch_version"
		exit 1
	fi
}

get_git_commit_id()
{
	local repo_path=$1
	git -C $repo_path log -n1 --pretty='format:%H' 2>/dev/null \
	|| echo UNKNOWN
}

# Delete unnecessary files on the runner to free up space
# (cf. https://github.com/jlumbroso/free-disk-space)
purge_runner()
{
	local sudo=$(test $(id -u) -eq 0 || echo sudo)

	test -d /HOST && cd /HOST || cd /

	local avail=$(df --block-size=1M --output=avail . | tail -n1)
	if [ $avail -gt 51200 ]
	then
		df -m .
		echo ' '
		echo "$FUNCNAME(): Skipping as more than 50 GB of disk space is available."
		return 0
	fi

	echo 'Before:'
	df -m .

	echo ' '

	for dir in \
		etc/skel/.rustup \
		home/*/.rustup \
		opt/hostedtoolcache/* \
		usr/lib/google-cloud-sdk \
		usr/lib/jvm \
		usr/local/.ghcup \
		usr/local/julia* \
		usr/local/lib/android \
		usr/local/lib/node_modules \
		usr/local/share/chromium \
		usr/local/share/powershell \
		usr/share/dotnet \
		usr/share/miniconda \
		usr/share/swift
	do
		$sudo find $dir -type f -exec truncate -s0 {} + || true
		run_cmd $sudo rm -rf $dir
	done

	echo ' '

	echo 'After:'
	df -m .
}

# Run a command as a regular user (and create said regular user if it
# doesn't already exist)
run_as_user()
{
	local user=build

	if [ $(id -u) -ne 0 ]
	then
		echo "$FUNCNAME(): error: this function must run as root"
		exit 1
	fi

	if ! grep -q "^$user:" /etc/passwd
	then
		run_cmd useradd \
			--comment 'Build User' \
			--gid users \
			--create-home \
			$user
	fi

	test -n "$*" || return 0

	setpriv \
		--reuid=$user \
		--regid=users \
		--init-groups \
		--no-new-privs \
		--reset-env \
		/bin/sh -ex -c "$@"
}

# Use to organize the terminal output of scripts
section()
{
	local name=$1
	local stamp=/tmp/.xtradeb-group-open.stamp

	if [ -z "$name" ]
	then
		if [ -n "${GITHUB_OUTPUT:-}" -a -f $stamp ]
		then
			echo '::endgroup::'
			rm $stamp
		fi
	elif [ -n "${GITHUB_OUTPUT:-}" ]
	then
		echo "::group::$name"
		touch $stamp
	else
		echo '##'
		echo "## $name"
		echo '##'
		echo ' '
	fi
}

# Limit a command's read-write access, hide a few sensitive areas, and cut
# off network access
secure_wrap()
{
	local share_net=
	test "_${SECURE_WRAP_ALLOW_NETWORK:-}" != _yes \
	|| share_net=--share-net

	local disable_userns=
	test -z "${GITHUB_JOB:-}" \
	|| disable_userns='--unshare-user --disable-userns'

	local addl_bind_list=

	# Directories to hide altogether (sensitive material)
	#
	for dir in \
		/github/workflow \
		$HOME/.gnupg \
		$HOME/.ssh \
		${RUNNER_TEMP:-} \
		${XDG_RUNTIME_DIR:-} \
		${SECURE_WRAP_HIDE_DIRS:-}
	do
		test ! -d $dir || addl_bind_list+=" --tmpfs $dir"
	done

	# Allow read/write access to these directories
	#
	for dir in ${SECURE_WRAP_RW_DIRS:-}
	do
		test ! -d $dir || addl_bind_list+=" --bind $dir $(realpath $dir)"
	done

	echo + "$@" >&2

	bwrap \
		--ro-bind / / \
		--dev /dev \
		--tmpfs /tmp \
		--unshare-all \
		$disable_userns \
		$share_net \
		--new-session \
		$addl_bind_list \
		"$@"
}

# end functions.sh

#!/bin/sh
# functions.sh

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
		(set -x; $sudo apt-get --error-on=any update)
		echo ' '
		shift
	fi

	if ! (set -x; $sudo apt-get -y --no-install-recommends install "$@")
	then
		# If the initial install fails, then we presume that the
		# package index is stale and needs updating.
		echo ' '
		(set -x; $sudo apt-get --error-on=any update)
		echo ' '
		(set -x; $sudo apt-get -y --no-install-recommends install "$@")
	fi
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
		(set -x; $sudo rm -rf $dir)
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
		(set -x; useradd \
			--comment 'Build User' \
			--gid users \
			--create-home \
			$user
		)
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

# Limit a command's read-write access, hide a few sensitive areas, and cut
# off network access
secure_wrap()
{
	local addl_bind_list=

	# Directories to hide altogether (sensitive material)
	#
	for dir in \
		$HOME/.gnupg \
		$HOME/.ssh \
		$XDG_RUNTIME_DIR \
		$SECURE_WRAP_HIDE_DIRS
	do
		test ! -d $dir || addl_bind_list+=" --tmpfs $dir"
	done

	# Allow read/write access to these directories
	#
	for dir in $SECURE_WRAP_RW_DIRS
	do
		test ! -d $dir || addl_bind_list+=" --bind $dir $(realpath $dir)"
	done

	echo + "$@" >&2

	bwrap \
		--ro-bind / / \
		--dev /dev \
		--tmpfs /tmp \
		--unshare-net \
		$addl_bind_list \
		"$@"
}

# end functions.sh

#!/bin/sh
# _container-init.sh
#
# Script to initialize a raw "debian" or "ubuntu" container
#

set -e

test -n "$APT_MIRROR" || APT_MIRROR=NONE
test -n "$REG_UID"    || REG_UID=1000

run() {
	echo "+ $*"
	env "$@" 2>&1
	echo ' '
}

export DEBIAN_FRONTEND=noninteractive

# Adjust APT configuration
run tee /etc/apt/apt.conf.d/95custom << END
# Don't install recommended packages
APT::Install-Recommends "0";

# Don't use "Reading database ... X%" progress indicator
Dpkg::Use-Pty "false";
END

# Set up APT package repositories
if [ "_$APT_MIRROR" != _NONE ]
then
	run perl -pi \
		-e 's!http://deb.debian.org/debian!<APT>!;' \
		-e 's!http://archive.ubuntu.com/ubuntu!<APT>!;' \
		-e "s!<APT>!$APT_MIRROR!;" \
		/etc/apt/sources.list.d/*.sources
fi

run apt-get --error-on=any update
run apt-get -y dist-upgrade

# Avoid installing this one
run apt-mark hold systemd

run apt-get -y install \
	bubblewrap \
	ca-certificates \
	debhelper \
	devscripts \
	dpkg-dev \
	equivs \
	file \
	git \
	jq \
	less \
	nano \
	netcat-openbsd \
	procps \
	python3 \
	quilt \
	rsync \
	time \
	unzip \
	wget \
	xz-utils \
	zip \
	zstd

# Create regular user
run useradd \
	--comment 'Tux the Penguin' \
	--uid $REG_UID \
	--create-home \
	--key HOME_MODE=0755 \
	--shell /bin/bash \
	tux

echo 'Initialization complete.'

# end _container-init.sh

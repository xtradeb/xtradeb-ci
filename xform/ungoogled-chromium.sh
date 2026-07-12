#!/bin/bash
# ungoogled-chromium.sh

chromium_deb_version=$1

if [ -z "$chromium_deb_version" ]
then
	echo "usage: $0 CHROMIUM_DEB_VERSION"
	exit 1
fi

set -eu

top_dir=$(cd $(dirname $0) && cd .. && pwd)
. $top_dir/misc/functions.sh

base_dir=$PWD
orig_version=${chromium_deb_version%-*}
xtradeb_ci_commit=$(get_git_commit_id $top_dir)

##
section 'Get ungoogled-chromium Git tree'
## (source patches and scripts)
##

test -d ungoogled-chromium \
|| run_cmd git clone --depth=10 https://github.com/ungoogled-software/ungoogled-chromium.git

uc_commit=$(get_git_commit_id ungoogled-chromium)

uc_tag=$(git -C ungoogled-chromium tag --list --sort=version:refname "$orig_version-*" | tail -n1)
test -n "$uc_tag" || error "Cannot find matching tag for $orig_version"

uc_rev=${uc_tag##*-}

echo ' '

echo "Using ungoogled-chromium tag \"$uc_tag\""
run_cmd git -C ungoogled-chromium switch -d $uc_tag

echo ' '

##
section 'Get ungoogled-chromium-debian Git tree'
## (conversion framework)
##

test -d ungoogled-chromium-debian \
|| run_cmd git clone --depth=1 https://github.com/ungoogled-software/ungoogled-chromium-debian.git

test -f ungoogled-chromium-debian/convert/Makefile \
|| error 'Cannot find ungoogled-chromium-debian conversion framework'

ucd_commit=$(get_git_commit_id ungoogled-chromium-debian)

echo ' '

##
section 'Get and unpack Chromium source'
## (as shipped by Debian)
##

(cd source && run_cmd ${APT_GET:-apt-get} --download-only source chromium=$chromium_deb_version)

dsc_file=$(cd source && echo chromium_*.dsc)
test -f source/$dsc_file \
|| error 'Cannot find Chromium source package .dsc file'

debian_tar_file=$(cd source && echo chromium_*.debian.tar.xz)
test -f source/$debian_tar_file \
|| error 'Cannot find Chromium source package .debian.tar.xz file'

orig_tar_file=$(cd source && echo chromium_*.orig.tar.xz)
test -f source/$orig_tar_file \
|| error 'Cannot find Chromium source package .orig.tar.xz file'

echo ' '

run_cmd dscverify --verbose source/$dsc_file

echo ' '

rm -rf _work
mkdir  _work

# Unpack source package
(cd _work && run_cmd dpkg-source \
	--no-copy \
	--skip-patches \
	--extract \
	../source/$dsc_file
)

chromium_dir=$(cd _work && echo chromium-*/debian/control | cut -d/ -f1)

test -d _work/$chromium_dir/chrome \
|| error 'Cannot find unpacked Chromium source package dir'

echo ' '

##
section 'Transform chromium -> ungoogled-chromium'
##

SECURE_WRAP_RW_DIRS=$base_dir/_work

(cd _work && secure_wrap make -f ../ungoogled-chromium-debian/convert/Makefile \
	check-git source-package \
	VERSION=$orig_version \
	ORIG_SOURCE=$chromium_dir \
	ORIG_TARBALL=../source/$orig_tar_file \
	INPLACE=1 \
	UNGOOGLED=../ungoogled-chromium \
	DEBIAN_CONVERT=../ungoogled-chromium-debian/convert \
	ADD_VERSION_SUFFIX=.$uc_rev \
	DISTRIBUTION=
)

uc_deb_version=$(sed -n 's/^Version: *// p' _work/ungoogled-chromium_*.dsc)
test -n "$uc_deb_version" \
|| error 'Could not determine version of new ungoogled-chromium package'

section ''
echo ' '

rm -rf output
mkdir output
mv _work/ungoogled-chromium_* output/

checksums=
tab='	'
for file in output/*
do
	size=$(stat -Lc '%s' $file)
	sum=$(sha256sum $file | awk '{print $1}')
	checksums+="$tab$sum $size $(basename $file)
"
done

hr='================================================================'
echo $hr
tee output/INFO << END
# XtraDeb source package artifact info
Source: ungoogled-chromium
Version: $uc_deb_version
Transform-Base-Source: chromium
Transform-Base-Version: $chromium_deb_version
Transform-Source-Refs:
	xtradeb-ci@$xtradeb_ci_commit
	ungoogled-chromium@$uc_commit # $uc_tag
	ungoogled-chromium-debian@$ucd_commit
Checksums-Sha256:
$checksums
END
echo $hr

echo ' '

run_cmd ls -Ll output

# end ungoogled-chromium.sh

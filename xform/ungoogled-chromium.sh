#!/bin/bash
# ungoogled-chromium.sh
#
# Requires-System-Setup: yes
#

set -eu

top_dir=$(cd $(dirname $0) && cd .. && pwd)
. $top_dir/misc/functions.sh

base_dir=$PWD
xtradeb_ci_commit=$(get_git_commit_id $top_dir)

##
section 'Examine Chromium source'
##

chromium_dir=$(cd source && echo chromium-*/debian/control | cut -d/ -f1)
test -d source/$chromium_dir \
|| error 'Cannot find Chromium source tree in source/chromium-*/'

orig_tar_file=$(cd source && echo chromium_*.orig.tar.xz)
test -f source/$orig_tar_file \
|| error 'Cannot find Chromium source package .orig.tar.xz file'

deb_version=$(cd source/$chromium_dir && dpkg-parsechangelog -S Version)
orig_version=${deb_version%-*}

cat << END
Source tree: source/$chromium_dir/
Orig source: source/$orig_tar_file

 Package version: $deb_version
Upstream version: $orig_version

END

if [ "_${1:-}" = _--setup ]
then
	test $(id -u) -eq 0 \
	|| error 'The --setup action must run as root'

	##
	section 'Install Chromium build dependencies'
	##

	(cd /tmp && run_cmd mk-build-deps $base_dir/source/$chromium_dir/debian/control)
	echo ' '
	apt_get_install /tmp/chromium-build-deps_*_all.deb

	##
	section 'Install additional dependencies for init-pre-gen'
	##

	# Copied from $chromium_dir/debian/scripts/init-pre-gen.sh
	arch_list=$(sed -n 's/^Architecture: *// p' source/$chromium_dir/debian/control | head -n1)
	gcc_ver=$(apt-cache --no-all-versions show gcc | grep '^Depends:' | grep -Po ' gcc-\d\d ' | tr -cd 0-9)
	pkg_list=$(for arch in $arch_list; do echo libc6-dev-$arch-cross libgcc-$gcc_ver-dev-$arch-cross; done)

	apt_get_install $pkg_list

	section ''
	exit 0
fi

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
echo "HEAD: ${ucd_commit:0:8}"

echo ' '

##
section 'Transform chromium -> ungoogled-chromium'
##

rm -rf inner-work
mkdir  inner-work

SECURE_WRAP_RW_DIRS=$base_dir/inner-work

(cd inner-work && secure_wrap make -f ../ungoogled-chromium-debian/convert/Makefile \
	check-git source-package \
	VERSION=$orig_version \
	ORIG_SOURCE=../source/$chromium_dir \
	ORIG_TARBALL=../source/$orig_tar_file \
	INIT_PRE_GEN=1 \
	UNGOOGLED=../ungoogled-chromium \
	DEBIAN_CONVERT=../ungoogled-chromium-debian/convert \
	ADD_VERSION_SUFFIX=.$uc_rev \
	DISTRIBUTION=
)

uc_deb_version=$(sed -n 's/^Version: *// p' inner-work/ungoogled-chromium_*.dsc)
test -n "$uc_deb_version" \
|| error 'Could not determine version of new ungoogled-chromium package'

section ''
echo ' '

rm -rf output
mkdir output
mv inner-work/ungoogled-chromium_* output/

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
Transform-Base-Version: $deb_version
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

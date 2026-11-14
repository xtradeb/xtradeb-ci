#!/bin/bash
# betterbird.sh
#

set -eu

top_dir=$(cd $(dirname $0) && cd .. && pwd)
. $top_dir/misc/functions.sh

base_dir=$PWD
xtradeb_ci_commit=$(get_git_commit_id $top_dir)

##
section 'Examine Thunderbird source'
##

thunderbird_dir=$(cd source && echo thunderbird-*/debian/control | cut -d/ -f1)
test -d source/$thunderbird_dir \
|| error 'Cannot find Thunderbird source tree in source/thunderbird-*/'

orig_tar_main_file=$(cd source && echo thunderbird_*.orig.tar.xz)
test -f source/$orig_tar_main_file \
|| error 'Cannot find Thunderbird source package .orig.tar.xz file in source/'

orig_tar_l10n_file=$(cd source && echo thunderbird_*.orig-thunderbird-l10n.tar.xz)
test -f source/$orig_tar_l10n_file \
|| error 'Cannot find Thunderbird source package .orig-thunderbird-l10n.tar.xz file in source/'

deb_version=$(cd source/$thunderbird_dir && dpkg-parsechangelog -S Version | sed 's/^1://')
orig_version=${deb_version%-*}

cat << END
Source tree: source/$thunderbird_dir/
Orig source: source/$orig_tar_main_file
             source/$orig_tar_l10n_file

 Package version: $deb_version
Upstream version: $orig_version

END

##
section 'Get thunderbird-patches Git tree'
## (source patches and scripts)
##

test -d thunderbird-patches \
|| run_cmd git clone --depth=50 https://github.com/Betterbird/thunderbird-patches.git

bb_tag=$(git -C thunderbird-patches tag --list --sort=version:refname "$orig_version-bb*" | tail -n1)
test -n "$bb_tag" || error "Cannot find matching tag for $orig_version"

bb_rev=${bb_tag#*-}

echo ' '

echo "Using thunderbird-patches tag \"$bb_tag\""
run_cmd git -C thunderbird-patches switch -d $bb_tag

bb_commit=$(get_git_commit_id thunderbird-patches)

echo ' '

##
section 'Get betterbird-debian Git tree'
## (conversion framework)
##

test -d betterbird-debian \
|| run_cmd git clone --depth=1 https://salsa.debian.org/iskunk/betterbird-debian.git

bbd_commit=$(get_git_commit_id betterbird-debian)
echo "HEAD: ${bbd_commit:0:8}"

echo ' '

##
section 'Transform thunderbird -> betterbird'
##

rm -rf inner-work
mkdir  inner-work

ln -sr source/$orig_tar_main_file inner-work/
ln -sr source/$orig_tar_l10n_file inner-work/

SECURE_WRAP_RW_DIRS=$base_dir/inner-work

(cd inner-work && secure_wrap make -f ../betterbird-debian/Makefile \
	check source-package \
	THUNDERBIRD_SOURCE=../source/$thunderbird_dir \
	THUNDERBIRD_PATCHES=../thunderbird-patches \
	DEBIAN_CONVERT=../betterbird-debian \
	ADD_VERSION_SUFFIX=.$bb_rev \
	DISTRIBUTION=
)

# Adjust orig-source symlinks
for orig in inner-work/betterbird_*.orig*
do
	test -L $orig || continue
	ln -sf $PWD/source/$(readlink $orig) $orig
done

bb_deb_version=$(sed -n 's/^Version: *// p' inner-work/betterbird_*.dsc)
test -n "$bb_deb_version" \
|| error 'Could not determine version of new betterbird package'

section ''
echo ' '

rm -rf output
mkdir output
mv inner-work/betterbird_* output/

checksums=
tab='	'
for file in output/*
do
	size=$(stat -Lc '%s' $file)
	sum=$(sha256sum $file | awk '{print $1}')
	checksums+="$tab$sum $size $(basename $file)
"
done
checksums=${checksums:0:-1}  # strip final newline

hr='================================================================'
echo $hr
tee output/INFO << END
# XtraDeb source package artifact info
Source: betterbird
Version: $bb_deb_version
Transform-Base-Source: thunderbird
Transform-Base-Version: $deb_version
Transform-Source-Refs:
	xtradeb-ci@$xtradeb_ci_commit
	thunderbird-patches@$bb_commit # $bb_tag
	betterbird-debian@$bbd_commit
Checksums-Sha256:
$checksums
END
echo $hr

echo ' '

run_cmd ls -Ll output

# end betterbird.sh

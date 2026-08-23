#!/bin/sh
# net-wrap.sh
#
# Command wrapper to create a new network namespace with a working
# loopback interface, and run the specified command therein. This
# disallows network access, while still allowing basic loopback
# functionality.
#
# Usage: net-wrap.sh COMMAND [ARG] ...
#
# Must run as root, and requires the SYS_ADMIN capability (for
# "unshare -n") as well as NET_ADMIN (for "ip link ...").
#

echo "$0: creating restricted network namespace" >&2

exec unshare -n sh -c 'ip link set lo up && exec "$0" "$@"' "$@"

# end net-wrap.sh

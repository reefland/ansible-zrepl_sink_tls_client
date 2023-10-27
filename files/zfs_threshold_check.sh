#!/usr/bin/env bash
set -e

# Checks the data-written threshold of a zfs dataset for use with zrepl. At minimum this
# script will prevent zero-byte snapshots.
#
# Returns 0 if amount written is over a defined threshold (zero by default)
# Returns 1 if not over (do not take snapshot)

# Set threshold in bytes like this :
# zfs set com.zrepl:snapshot-threshold=6000000 pool/dataset

WRITTEN=$(zfs get -Hpo value written "${ZREPL_FS}")
THRESH=$(zfs get -Hpo value com.zrepl:snapshot-threshold "${ZREPL_FS}")

[ "$ZREPL_DRYRUN" = "true" ] && DRYRUN="echo DRYRUN (WRITTEN ${WRITTEN} THRESH ${THRESH}) : "

pre_snapshot() {
    echo -n "pre_snap "
    $DRYRUN date
    # If not a DRYRUN try to calculate
    if [ "$ZREPL_DRYRUN" != "true" ] ; then
    	[[ $((${THRESH} +0)) -lt $((${WRITTEN} +0)) ]] && RC=0 || RC=1
    fi
}

post_snapshot() {
    echo -n "post_snap "
    $DRYRUN date
}

case "$ZREPL_HOOKTYPE" in
    pre_snapshot|post_snapshot)
        "$ZREPL_HOOKTYPE"
        ;;
    *)
        printf 'Unrecognized hook type: %s\n' "$ZREPL_HOOKTYPE"
        exit 255
        ;;
esac

exit "$RC"

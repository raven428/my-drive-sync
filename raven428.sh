#!/usr/bin/env bash
#
# $Id: raven428.sh,v 1.2 2016/10/21 13:43:16 raven Exp $
#
. /usr/local/raven/etc/no_self_double.sh
. /usr/local/raven/sync/google-drive/functions.sh
rm -f ${token}
ln -s ${tokens}/raven428.yml ${token}
perlbrew exec \
 --with perl-5.18.4@gdrive \
 /usr/local/raven/sync/google-drive/my-drive-sync.pl \
 --delete \
 --exclude acr \
 --exclude ACRRecordings_NEW \
 --dstdir /usr/nfs/google-drive/raven428
rm -f ${token}

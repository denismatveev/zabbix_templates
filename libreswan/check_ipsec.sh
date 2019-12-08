#!/bin/bash
IPSEC=/usr/sbin/ipsec
FPING=/usr/bin/fping
basename=`basename $0`
help_message="
Check addresses availability inside tunnel.
If at least one address in specified network is available, script returns 0(OK) otherwise is 1.
Usage: $basename [networks] 
where netwok in a.b.c.d/mask view.
"

if [[ $# -lt 1 ]] ; then
  echo "$help_message"
  exit 1
fi


test_network()
{ 
       "$FPING" -g $1 2>/dev/null | grep alive 2>&1 1>/dev/null
}


for network in $@;do
    test_network "$network"
    if [[ $? -ne 0 ]];then 
      echo 1;
      exit 1;
    fi
done
echo 0;

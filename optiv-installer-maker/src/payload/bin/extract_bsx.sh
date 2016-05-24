#!/bin/bash

BSXFILE=`cat work/install.sh | grep -m1 AGENT_BSX_NAME_IN_ZIP | cut -d "=" -f 2`
echo $BSXFILE

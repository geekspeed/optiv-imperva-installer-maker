VERS=11.5.0
AGENTDIR="./agent/"
LATEST=`./bin/which_ragent_package_0089.sh -v $VERS | grep Latest`
FILEA=($LATEST)
FILE=${FILEA[5-1]}
if [ -f $AGENTDIR$FILE ]
then
	echo "$AGENTDIR$FILE"
else
	exit 1
fi

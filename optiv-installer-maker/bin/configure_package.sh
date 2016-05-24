#!/bin/bash
	source ./lib/logo.pack
	reset
	logo
        echo -n "Installer name: "
        read PACKAGE
        echo -n "Gateway: "
        read GATEWAY1
        echo -n "Password: "
	read PASSWORD1
	echo $PACKAGE > .package
	echo $GATEWAY1 > .gateway
	echo $PASSWORD1 > .secure

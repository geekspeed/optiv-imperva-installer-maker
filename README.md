# optiv-imperva-installer-maker
This tool was created to bundle up Imperva Agents for a hands-free install. While Imperva ships bsx files for agent installs, the install requires running multiple scripts in a certain sequence to make sure everything is normal. This installer maker packages up a single bsx that will choose the correct agent file to install, installs it, installs the installation manager, registers the agent with a single primary gateway, and then starts the agent. This was created for a client who had a very particular need, but I found that it could be usefull to others. The only requirements are having Make installed to run the makefiles.

##Creating the installer
In the current directory:
```
make
```
This will start the installer builder.
![Make Screen](images/image1.png?raw=true "Make Screen")

Type in the name for the installation package. The name will be prepended with -installer.bsx and placed in the current directory when the script is finished.

![Input Screen](images/image2.png?raw=true "Input Screen")

Type in the ip (or hostname) of the gateway the agent will auto-register to. All agents deployed via this script will auto-register to a single gateway. It works best to create packages for each gateway.
Type in the password for the gateway. The password WILL be echo'd to the terminal.

![Action Screen](images/image3.png?raw=true "Action Screen")

The installer maker will do it's thing and build your bsx file. This file will contain all the latest agents (as of 5/20/2016) - it does not fetch the current ones -- just a static set I compiled. When it's done it will show you the bsx name, the gateway and the password.

##Running the installer package
Once the installer has been uploaded to your database server
```
./installer-name.bsx
```
![Decompress Screen](images/image4.png?raw=true "Decompress Screen")

The archive will start to decompress into a tmp directory in /tmp. Once decompression is done, the installer will start.

![Installer Screen](images/image5.png?raw=true "Installer Screen")

From here the installer will run ```which_ragent_package_0089.sh``` script to determine the appropriate agent. Once an agent has been identified, the agent will be pulled from the 'agent' directory and untar'd into the 'work' directory. The agent bsx file will be executed in silent mode with a destination dir set to '/opt/imperva' e.g:
```
./work/Imperva-ragent-RHEL-v7-kSMP-px86_64-b11.5.0.2032.bsx -n -d /opt/imperva
```

When that completes successfully the installation manager will be installed as well:
```
./work/Imperva-ragentinstaller-RHEL-v7-kSMP-px86_64-b1.0.0.5009.bsx -n -d /opt/imperva
```

After that is completed, the agents are then registered. The ragent-name is supplied with the value of the ```hostname``` command. The Gateway and Password are the values supplied during the installer maker.
```
/opt/imperva/ragent/bin/cli --dcfg /opt/imperva/ragent/etc --dtarget /opt/imperva/ragent/etc --dlog /opt/imperva/ragent/etc/logs/cli --dvar /opt/imperva/ragent/var registration advanced-register registration-type=Primary ragent-name=$HOSTNAME gw-ip=10.10.10.1 gw-port=443 manual-settings-activation=Automatic monitor-network-channels=Local password=password1
```

When that has completed successfully. The agent is turned on with:
```
/opt/imperva/ragent/bin/rainit start
```

And we exit. Pretty simple.

##Next steps
Feel free to issue pull requests, or fix any glaring errors i have. This has only been tested on RHEL boxes in my lab, so who knows what bugs might be in it.

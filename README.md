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

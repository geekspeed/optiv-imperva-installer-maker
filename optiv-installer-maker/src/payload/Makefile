FILE = $(shell ./bin/ragent.sh)

WORK = ./work
IMPERVADIR = /opt/imperva
DOMAGENTINSTALL = ./agent
HOSTNAME = $(shell hostname)
SECURE = 


all: pkg ragent installragent ragentinstaller installinstaller securepwd register startservice


pkg:

ifneq ($(FILE),)
	@echo Using $(FILE)
	cd $(DOMAGENTINSTALL)
	tar -xzvf $(FILE) -C $(WORK)
else
	@echo The correct Imperva Agent was not found for this kernel. Please check the Imperva FTP site for the correct agent.
	exit 1
endif

ragent:
	$(eval BSXFILE := $(shell ./bin/extract_bsx.sh))
	@echo Extracted $(BSXFILE)
	@echo Executng $(BSXFILE) -n -d $(IMPERVADIR)	

installragent:
	$(WORK)/$(BSXFILE) -n -d $(IMPERVADIR)
	$(eval LISTENER := $(shell ./bin/get_gateway.sh))

ragentinstaller:
	$(eval RINSTALLER := $(shell ls $(WORK) | grep installer))

installinstaller:
	$(WORK)/$(RINSTALLER) -n -d $(IMPERVADIR)

securepwd: 
	@echo [[$(shell pwd)]]
	$(eval SECURE := $(shell ./bin/get_secure.sh))

register:
ifeq ($(SECURE),'') 
	@echo Could not locate the gw password. Aborting. [$(shell pwd)]
	exit 1
else
	@echo Found secure password
endif	

ifneq ($(LISTENER),'')
	$(IMPERVADIR)/ragent/bin/cli --dcfg $(IMPERVADIR)/ragent/etc --dtarget $(IMPERVADIR)/ragent/etc --dlog $(IMPERVADIR)/ragent/etc/logs/cli --dvar $(IMPERVADIR)/ragent/var registration advanced-register registration-type=Primary ragent-name=$(HOSTNAME) gw-ip=$(LISTENER) gw-port=443 manual-settings-activation=Automatic monitor-network-channels=Local password=$(SECURE)

else
	@echo Could not locate the listener file. Aborting
	exit 1
endif

startservice:
	$(IMPERVADIR)/ragent/bin/rainit start


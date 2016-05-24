


all: pkg pkgname gateway secure buildinstaller buildbsx cleanup present

INSTALLSHELL := ./installer_shell.sh

pkg: 
	./bin/configure_package.sh

pkgname:
	$(eval PKG := $(shell cat ./.package))

gateway:
	$(eval GATEWAY1 := $(shell cat ./.gateway))
	@cp .gateway src/payload/.gateway

secure:
	$(eval PASSWORD1 := $(shell cat ./.secure))
	@cp .secure src/payload/.secure

buildinstaller:
	@echo -e "\e[1mBundling up installer...\e[0m"
	@echo -e "\e[1mCleaning WORK dir...\e[0m"
	@rm -rf src/payload/work/*
	@echo -e "\e[1mCreating Agent tarball...\e[0m"
	@cd src/payload && tar -czvf ../$(PKG)-agent.tar.gz .

buildbsx:
	@echo -e "\e[1mCreating bsx...\e[0m"
	@cp src/$(INSTALLSHELL) $(PKG)-installer.bsx
	@cat src/$(PKG)-agent.tar.gz >> $(PKG)-installer.bsx
	@chmod +x $(PKG)-installer.bsx

cleanup:
	@echo -e "\e[1mCleaning up...\e[0m"
	@rm src/$(PKG)-agent.tar.gz
	@rm src/payload/.gateway
	@rm src/payload/.secure
	@rm .package
	@rm .secure
	@rm .gateway

present:
	@echo -e "\e[1m\e[31mInstaller Package:\e[0m ./$(PKG)-installer.bsx \e[0m"
	@echo -e "\e[1m\e[31mGateway:\e[0m $(GATEWAY1) \e[0m"
	@echo -e "\e[1m\e[31mPassword:\e[0m $(PASSWORD1) \e[0m"


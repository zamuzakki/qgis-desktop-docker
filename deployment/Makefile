# Kept separate from the repo-root Makefile, which drives the Nix-based build.

.PHONY: volumes-dir-local up down

LOCAL_IMAGE_NAME := qgis-desktop-docker
LOCAL_IMAGE_TAG := local

INSTANCE ?= main
SERVICE := qgis-$(INSTANCE)

volumes-dir-local: ## Create + chown ./.volumes/$(INSTANCE) (default INSTANCE=main; override with INSTANCE=<name>)
	mkdir -p .volumes/$(INSTANCE)
	@if ! chown 1000:1000 .volumes/$(INSTANCE) 2>/dev/null; then \
		echo "chown needs privileges -- retrying with sudo (uid 1000 = container's 'user' account)"; \
		sudo chown 1000:1000 .volumes/$(INSTANCE); \
	fi

up: volumes-dir-local ## Build + start one instance (default INSTANCE=main; override with INSTANCE=<name>)
	docker compose up -d --build $(SERVICE)

down: ## Stop + remove one instance (default INSTANCE=main; override with INSTANCE=<name>)
	# `docker compose down` tears down the whole project (all instances) --
	# stop+rm targets just this one service instead.
	docker compose stop $(SERVICE)
	docker compose rm -f $(SERVICE)

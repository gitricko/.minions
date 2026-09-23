
start-local:
	./install.sh

boot:
	~/.minions/boot.sh

self-check:
	~/.minions/self-check.sh

version-check:
	./scripts/admin-update.sh --dry-run

version-update:
	./scripts/admin-update.sh
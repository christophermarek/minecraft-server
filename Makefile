.PHONY: start stop restart logs console cmd setup-perms setup-spawn spawn-town backup-now pregen

COMPOSE ?= docker compose
CONTAINER_NAME ?= minecraft-server

# Generate .env (gitignored) with a random RCON password on first run.
.env:
	@echo "RCON_PASSWORD=$$(openssl rand -hex 16)" > .env
	@echo "Created .env with a random RCON password."

start: .env
	@mkdir -p server backups
	@$(COMPOSE) up -d
	@echo "Java Edition:    localhost:25565"
	@echo "Bedrock Edition: localhost:19132"
	@echo "Live map:        http://localhost:8100"
	@echo "Player stats:    http://localhost:8804"
	@echo "Attaching to logs (Ctrl+C to exit, server keeps running)..."
	@$(COMPOSE) logs -f mc

stop:
	@$(COMPOSE) down

restart: .env
	@$(COMPOSE) restart mc

logs:
	@$(COMPOSE) logs -f mc

console:
	@echo "Ctrl+P then Ctrl+Q to detach without stopping the server."
	@docker attach $(CONTAINER_NAME)

# Run one console command, e.g. make cmd C="lp user Steve parent set staff"
cmd:
	@docker exec $(CONTAINER_NAME) rcon-cli $(C)

# Grant ranks/permissions (idempotent; safe to re-run after editing the script).
setup-perms:
	@./scripts/setup-permissions.sh $(CONTAINER_NAME)

# Create the PvP-free WorldGuard region around world spawn (re-run after a world reset).
setup-spawn:
	@./scripts/setup-spawn.sh $(CONTAINER_NAME)

# Make spawn a server-owned Towny town. An admin must be online: make spawn-town PLAYER=<name>
spawn-town:
	@./scripts/setup-spawn-town.sh $(PLAYER) $(CONTAINER_NAME)

backup-now:
	@$(COMPOSE) exec backup backup now

# Set the world borders and pre-generate everything inside them. Run with no players online.
pregen:
	@./scripts/pregen.sh $(CONTAINER_NAME)

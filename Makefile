.PHONY: start stop console

IMAGE_NAME ?= papermc-server
CONTAINER_NAME ?= minecraft-server
PORT ?= 25565
SERVER_DIR ?= $(shell pwd)/server

MC_VERSION ?= latest
PAPER_BUILD ?= latest
EULA ?= true
MC_RAM ?=
JAVA_OPTS ?=

start:
	@echo "Building Docker image..."
	@docker build -t $(IMAGE_NAME) .
	@mkdir -p $(SERVER_DIR)
	@echo "Fixing permissions..."
	@docker run --rm \
		-v $(SERVER_DIR):/papermc \
		--user root \
		alpine:latest \
		sh -c "chown -R 1000:1000 /papermc || true"
	@echo "Starting Minecraft server..."
	@docker run -dit \
		--name $(CONTAINER_NAME) \
		-p $(PORT):25565 \
		-v $(SERVER_DIR):/papermc \
		-e EULA=$(EULA) \
		-e MC_VERSION=$(MC_VERSION) \
		-e PAPER_BUILD=$(PAPER_BUILD) \
		$(if $(strip $(MC_RAM)),-e MC_RAM=$(MC_RAM)) \
		$(if $(strip $(JAVA_OPTS)),-e JAVA_OPTS=$(JAVA_OPTS)) \
		--restart on-failure \
		$(IMAGE_NAME)
	@echo "Server started! Connect to localhost:$(PORT)"
	@echo "Server files: $(SERVER_DIR)"
	@echo "Attaching to logs (Ctrl+C to exit, server keeps running)..."
	@docker logs -f $(CONTAINER_NAME)

stop:
	@echo "Stopping and cleaning up server..."
	@docker stop $(CONTAINER_NAME) || true
	@docker rm $(CONTAINER_NAME) || true
	@docker rmi $(IMAGE_NAME) || true
	@echo "Server stopped and cleaned (world data preserved in: $(SERVER_DIR))"

console:
	@echo "Attaching to Minecraft server console..."
	@echo "Type 'stop' to stop the server, or Ctrl+P then Ctrl+Q to detach without stopping"
	@docker attach $(CONTAINER_NAME)


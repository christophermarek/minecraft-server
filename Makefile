.PHONY: start stop

IMAGE_NAME ?= papermc-server
CONTAINER_NAME ?= minecraft-server
PORT ?= 25565
WEBMAP_PORT ?= 8090
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
	@echo "Starting Minecraft server..."
	@docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(PORT):25565 \
		-p $(WEBMAP_PORT):8080 \
		-v $(SERVER_DIR):/papermc \
		-e EULA=$(EULA) \
		-e MC_VERSION=$(MC_VERSION) \
		-e PAPER_BUILD=$(PAPER_BUILD) \
		$(if $(strip $(MC_RAM)),-e MC_RAM=$(MC_RAM)) \
		$(if $(strip $(JAVA_OPTS)),-e JAVA_OPTS=$(JAVA_OPTS)) \
		--restart on-failure \
		-it \
		$(IMAGE_NAME)
	@echo "Server started! Connect to localhost:$(PORT)"
	@echo "Web map: http://localhost:$(WEBMAP_PORT)"
	@echo "Server files: $(SERVER_DIR)"
	@echo "Attaching to logs (Ctrl+C to exit, server keeps running)..."
	@docker logs -f $(CONTAINER_NAME)

stop:
	@echo "Stopping and cleaning up server..."
	@docker stop $(CONTAINER_NAME) || true
	@docker rm $(CONTAINER_NAME) || true
	@docker rmi $(IMAGE_NAME) || true
	@echo "Server stopped and cleaned (world data preserved in: $(SERVER_DIR))"


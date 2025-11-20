# We're no longer using openjdk:17-slim as a base due to several unpatched vulnerabilities.
# The results from basing off of alpine are a smaller (by 47%) and faster (by 17%) image.
# Even with bash installed.     
FROM alpine:latest


COPY start.sh .
RUN apk update \
    && apk add libstdc++ \
    && apk add openjdk21-jre \
    && apk add bash \
    && apk add wget \
    && apk add jq \
    && mkdir /papermc

# Start script
CMD ["bash", "./start.sh"]

# Container setup
EXPOSE 25565/tcp
EXPOSE 25565/udp
VOLUME /papermc
# Pl3xMap web map
EXPOSE 8050/tcp

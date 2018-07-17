# NSO base image
FROM ubuntu:18.10

ARG NSOVER

WORKDIR /app

# Install packages
RUN apt-get update -qq && \
    apt-get install -qq apt-utils openssh-client default-jdk-headless python && \
    apt-get -qq clean autoclean && \
    apt-get -qq autoremove 

# Install NSO
COPY nso-$NSOVER.linux.x86_64.installer.bin .
RUN sh nso-$NSOVER.linux.x86_64.installer.bin /app/nso && \
    rm nso-$NSOVER.linux.x86_64.installer.bin

# Setup basic ssh config
RUN mkdir /root/.ssh && chmod 700 /root/.ssh
COPY config /root/.ssh

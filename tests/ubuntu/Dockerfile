FROM ubuntu:22.04

ENV GIT_REPO=https://github.com/kitos9112/dotfiles.git
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    iproute2 \
    file \
    git \
    sudo

RUN useradd -m -s /bin/zsh -d /home/docker-qa docker-qa  && \
    echo "docker-qa ALL=NOPASSWD: ALL" >> /etc/sudoers

USER docker-qa

COPY --chown=docker-qa:docker-qa ./ /home/docker-qa/.dotfiles

WORKDIR /home/docker-qa

RUN DOTFILES_VERBOSE=true DOTFILES_NO_TTY=true .dotfiles/install

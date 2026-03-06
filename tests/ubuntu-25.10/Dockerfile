FROM ubuntu:25.10

ENV GIT_REPO=https://github.com/kitos9112/dotfiles.git
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    file \
    git \
    iproute2 \
    sudo

RUN useradd -m -s /bin/sh -d /home/docker-qa docker-qa  && \
    echo "docker-qa ALL=NOPASSWD: ALL" >> /etc/sudoers

USER docker-qa

COPY --chown=docker-qa:docker-qa ./ /home/docker-qa/.dotfiles

WORKDIR /home/docker-qa

RUN DOTFILES_TEST=true DOTFILES_VERBOSE=true DOTFILES_NO_TTY=true DOTFILES_CHEZMOI_EXCLUDE=scripts .dotfiles/install

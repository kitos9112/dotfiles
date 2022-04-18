FROM ubuntu:20.04

ENV GIT_REPO=https://github.com/kitos9112/dotfiles.git
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        build-essential \
        file \
        git \
        sudo \
        sed \
        findutils \
        software-properties-common \
        zsh

RUN useradd -m -s /bin/zsh -d /home/docker-qa docker-qa  && \
    echo "docker-qa ALL=NOPASSWD: ALL" >> /etc/sudoers

USER docker-qa

COPY ./ /home/docker-qa/.dotfiles

WORKDIR /home/docker-qa

RUN DOTFILES_VERBOSE=true .dotfiles/install

#ENTRYPOINT [ "/docker/entrypoint.sh" ]

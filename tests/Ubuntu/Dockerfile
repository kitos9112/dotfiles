FROM ubuntu

ENV GIT_REPO=https://github.com/kitos9112/dotfiles.git
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get -y install \
    curl \
    build-essential \
    file \
    git \
    sudo \
    sed \
    findutils \
    software-properties-common \
    zsh

RUN useradd -m -s /bin/zsh -d /docker docker
RUN echo "docker ALL=NOPASSWD: ALL" >> /etc/sudoers

COPY ./tests/entrypoint.sh /docker/

RUN chmod +x /docker/entrypoint.sh

USER docker

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"

RUN mkdir -p /docker/.config/chezmoi \
    && curl -sfL https://git.io/chezmoi | sudo sh

COPY ./tests/chezmoi.toml /docker/.config/chezmoi/

ENTRYPOINT [ "/docker/entrypoint.sh" ]

WORKDIR /docker

ENV PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
CMD ["sh", "-c", "chezmoi init --apply "]

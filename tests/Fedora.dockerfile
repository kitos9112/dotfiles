FROM fedora

RUN dnf update -y && dnf install -y \
    git \
    curl \
    file \
    sudo \
    sed \
    findutils \
    libxcrypt-compat \
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

CMD ["sh", "-c", "chezmoi apply"]
FROM fedora:33

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

WORKDIR /docker

ENV PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

ENTRYPOINT [ "/docker/entrypoint.sh" ]
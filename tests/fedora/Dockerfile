FROM fedora:35

RUN dnf update -y && dnf install -y \
    curl \
    sudo \
    sed \
    findutils \
    util-linux-user \
    libxcrypt-compat

RUN useradd -m -s /bin/zsh -d /docker docker
RUN echo "docker ALL=NOPASSWD: ALL" >> /etc/sudoers

COPY . /docker

RUN chmod +x /docker/tests/entrypoint.sh

USER docker

WORKDIR /docker

ENV PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
ENV LANG="en_GB.UTF-8"
ENV LANGUAGE="en_GB:en"
ENV LC_ALL="en_GB.UTF-8"

RUN tests/entrypoint.sh
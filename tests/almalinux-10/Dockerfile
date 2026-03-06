FROM almalinux:10

RUN dnf install -y \
    curl-minimal \
    findutils \
    sed \
    sudo \
    util-linux \
    util-linux-user \
    which && \
    dnf clean all

RUN useradd -m -s /bin/sh -d /home/docker-qa docker-qa && \
    echo "docker-qa ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER docker-qa

COPY ./ /home/docker-qa/.dotfiles

WORKDIR /home/docker-qa

RUN DOTFILES_TEST=true DOTFILES_VERBOSE=true DOTFILES_NO_TTY=true DOTFILES_CHEZMOI_EXCLUDE=scripts .dotfiles/install

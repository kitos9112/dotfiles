FROM fedora:42

RUN dnf update -y && \
    dnf install -y \
    curl \
    sudo \
    sed \
    findutils \
    util-linux-user \
    libxcrypt-compat && \
    sed -i 's/\(account     required      pam_unix.so\)/\1 broken_shadow/g' /etc/pam.d/system-auth

RUN useradd -m -s /bin/sh -d /home/docker-qa docker-qa  && \
    echo "docker-qa ALL=NOPASSWD: ALL" >> /etc/sudoers

USER docker-qa

RUN sudo -E whoami

COPY ./ /home/docker-qa/.dotfiles

WORKDIR /home/docker-qa

RUN DOTFILES_VERBOSE=true DOTFILES_NO_TTY=true .dotfiles/install

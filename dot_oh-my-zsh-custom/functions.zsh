# Create a Poetry Python directory within VSCODE
kalpinepod() {
	kubectl run -it --rm --restart=Never --image=alpine handytools -n ${1:-default} -- /bin/ash
}

# Creates a local Python project under Linux and spins up a VScode window
mkpoetryproj() {
	if [ $# -eq 1 ]; then
		poetry new "$1"
		cd "$1" || exit
		# get gitignore
		curl https://raw.githubusercontent.com/github/gitignore/master/Python.gitignore -o .gitignore
		{
			echo ""
			echo ".vscode/"
		} >>.gitignore
		mkdir -p .vscode
		touch .vscode/settings.json
		{
			echo "{"
			echo "    \"python.pythonPath\": \"$(poetry env info -p)/bin/python\","
			echo "    \"terminal.integrated.shellArgs.linux\": [\"poetry shell\"],"
			echo "    \"files.exclude\": {"
			echo "        \"**/.git\": true,"
			echo "        \"**/.DS_Store\": true,"
			echo "        \"**/*.pyc\": true,"
			echo "        \"**/__pycache__\": true,"
			echo "        \"**/.mypy_cache\": true"
			echo "    },"
			echo "    \"python.linting.enabled\": true,"
			echo "    \"python.linting.mypyEnabled\": true,"
			echo "    \"python.formatting.provider\": \"black\""
			echo "}"
		} >>.vscode/settings.json
		poetry add -D black mypy
		git init && git add . && git commit -m "ready to start"
		# shellcheck source=/dev/null
		source "$(poetry env info -p)/bin/activate" --prompt "poetry env"
		code .
	else
		echo "usage: mkpoetryproj FOLDER_TO_MAKE"
		echo ""
		echo "This inits a new project folder with poetry"
		echo "It adds the GitHub recommended .gitignore, connects VSCode to the poetry venv,"
		echo "and adds black and mypy, and makes sure VSCode knows about them"
		echo "it then inits a git repo, adds everything and commits it, then opens VSCode"
	fi
}

function get_latest_github_release {
	curl -s https://api.github.com/repos/$1/$2/releases/latest | grep -oP '"tag_name": "[v]\K(.*)(?=")'
}

function get_latest_github_tag {
	curl -s https://api.github.com/repos/$1/$2/tags | grep -m1 -oP '"name": "\K(.*)(?=")'
}

# Determine size of a file or total size of a directory
fs() {
	if du -b /dev/null >/dev/null 2>&1; then
		local arg=-sbh
	else
		local arg=-sh
	fi
	# shellcheck disable=SC2199
	if [[ -n "$@" ]]; then
		du $arg -- "$@"
	else
		du $arg -- .[^.]* *
	fi
}

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
targz() {
	local tmpFile="${1%/}.tar"
	tar -cvf "${tmpFile}" --exclude=".DS_Store" "${1}" || return 1

	size=$(
		stat -f"%z" "${tmpFile}" 2>/dev/null # OS X `stat`
		stat -c"%s" "${tmpFile}" 2>/dev/null # GNU `stat`
	)

	local cmd=""
	if ((size < 52428800)) && hash zopfli 2>/dev/null; then
		# the .tar file is smaller than 50 MB and Zopfli is available; use it
		cmd="zopfli"
	else
		if hash pigz 2>/dev/null; then
			cmd="pigz"
		else
			cmd="gzip"
		fi
	fi

	echo "Compressing .tar using \`${cmd}\`…"
	"${cmd}" -v "${tmpFile}" || return 1
	[ -f "${tmpFile}" ] && rm "${tmpFile}"
	echo "${tmpFile}.gz created successfully."
}

# Create a git.io short URL
gitio() {
	if [ -z "${1}" ] || [ -z "${2}" ]; then
		echo "Usage: \`gitio slug url\`"
		return 1
	fi
	curl -i https://git.io/ -F "url=${2}" -F "code=${1}"
}

# Start an HTTP server from a directory, optionally specifying the port
server() {
	local port="${1:-8000}"
	sleep 1 && open "http://localhost:${port}/" &
	# Set the default Content-Type to `text/plain` instead of `application/octet-stream`
	# And serve everything as UTF-8 (although not technically correct, this doesn’t break anything for binary files)
	python -c $'import SimpleHTTPServer;\nmap = SimpleHTTPServer.SimpleHTTPRequestHandler.extensions_map;\nmap[""] = "text/plain";\nfor key, value in map.items():\n\tmap[key] = value + ";charset=UTF-8";\nSimpleHTTPServer.test();' "$port"
}

restart_gpgagent() {
	# Restart the gpg agent.
	echo "Restarting gpg-agent and scdaemon..."
	echo -e "\tgpg-agent: $(pgrep gpg-agent) | scdaemon: $(pgrep scdaemon)"

	echo "Killing processes..."
	# shellcheck disable=SC2046
	kill -9 $(pgrep scdaemon) $(pgrep gpg-agent) >/dev/null 2>&1
	echo -e "\tgpg-agent: $(pgrep gpg-agent) | scdaemon: $(pgrep scdaemon)"

	gpgconf --reload gpg-agent
	gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

	echo "Restarted gpg-agent and scdaemon..."
}

deduplicate_env_path() {
	if [ -n "$PATH" ]; then
		old_PATH=$PATH:
		PATH=
		while [ -n "$old_PATH" ]; do
			x=${old_PATH%%:*} # the first remaining entry
			case $PATH: in
			*:"$x":*) ;;        # already there
			*) PATH=$PATH:$x ;; # not there yet
			esac
			old_PATH=${old_PATH#*:}
		done
		PATH=${PATH#:}
		unset old_PATH x
	fi
}

# Remove duplicated PATH entries
deduplicate_env_path
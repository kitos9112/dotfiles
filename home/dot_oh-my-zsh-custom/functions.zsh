# Create a Poetry Python directory within VSCODE
kalpinepod() {
	kubectl run -it --rm --restart=Never --image=alpine handytools -n ${1:-default} -- /bin/ash
}

# Make an ssh key if not exists, and copy ssh key to clipboard
# needs xclip to copy to system clipboard
ssh-key-now() {
	cat /dev/zero | ssh-keygen -t ed25519 -C "made with ssh-key-now" -q -N ""
	xclip -sel clip <~/.ssh/id_ed25519.pub
	echo "ssh-key copied to clipboard"
}

# Given the name of an EC2 instance, return the instance ID and open an SSMSession on it
function aws-ssh-instance {
	local instanceName=$1
	local instanceId=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${instanceName}" --query 'Reservations[*].Instances[*].{InstanceId:InstanceId}' --output text)

	aws ssm start-session --target ${instanceId}
}

function github-get-latest-release {
	curl -s https://api.github.com/repos/$1/$2/releases/latest | grep -oP '"tag_name": "[v]\K(.*)(?=")'
}

function github-get-latest-tag {
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

# Populates a local .gitignore file with the contents of a remote one
function gi() {
	curl -sL https://www.toptal.com/developers/gitignore/api/$@
}

_gitignoreio_get_command_list() {
	curl -sL https://www.toptal.com/developers/gitignore/api/list | tr "," "\n"
}

_gitignoreio() {
	compset -P '*,'
	compadd -S '' $(_gitignoreio_get_command_list)
}

compdef _gitignoreio gi
# Start an HTTP server from a directory, optionally specifying the port
server() {
	local port="${1:-8000}"
	sleep 1 && open "http://localhost:${port}/" &
	# Set the default Content-Type to `text/plain` instead of `application/octet-stream`
	# And serve everything as UTF-8 (although not technically correct, this doesn't break anything for binary files)
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

gitbd() {
	if [ $# -le 1 ]; then
		local branches_to_delete=$(git for-each-ref --format '%(refname:short)' refs/heads/ --no-contains $(git_main_branch) | grep "$1")
		printf "Matching branches:\n\n$branches_to_delete\n\nDelete? [Y/n] "
		read -n 1 # Immediately continue after getting 1 keypress
		echo      # Move to a new line
		if [[ ! $REPLY == 'N' && ! $REPLY == 'n' ]]; then
			echo $branches_to_delete | xargs git branch -D
		fi
	else
		echo "This command takes one arg (match pattern) or no args (match all)"
	fi
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

# Iterates over all lines of the default ~/.tool-versions file and removes all versions that are no longer needed
asdf-versions-cleanup() {
	while read -r line; do
		IFS=' ' read -r -a tool_and_versions <<< "$line"
		# Split out the tool name and versions
		tool_name="${tool_and_versions[0]}"
		global_versions=("${tool_and_versions[@]:1}")

		# Loop over each version of the tool name
		for version in $(asdf list $tool_name); do
			# When version not in `global_versions` array from .tool-versions file
			if [[ ! " ${global_versions[@]} " =~ " ${version} " ]]; then
				# Remove the version here if you want
				echo "$tool_name version $version not found in .tool-versions"
				asdf uninstall $tool_name $version
			fi
		done
	done < ~/.tool-versions
}
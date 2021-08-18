# Here lives all the aliases useful for me!
alias brewup="brew update && brew upgrade && brew upgrade --cask && brew cleanup -v -s && brew doctor"

# What's my public IP address via DNS?
alias get-public-ip-dns="host myip.opendns.com resolver1.opendns.com | grep -oP '\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}(?<!#53)$'"

# Another cool way using `dig` --> dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}'
alias get-public-ip-wget="wget -qO- http://ipecho.net/plain | xargs echo"

# AWS
alias aws-get-instanceid="export AWS_EC2_INSTANCE_ID=\`aws ec2 describe-instances --filters \"Name=tag:Name,Values=${AWS_EC2_INSTANCE_NAME}\" --output text --query \"Reservations[*].Instances[*].InstanceId\"\` && echo ${AWS_EC2_INSTANCE_ID}"

# GIT
alias git-branch-rn-all="git branch | grep -v $(git_main_branch) | xargs git branch -D"

# Make an ssh key if not exists, and copy ssh key to clipboard
# needs xclip to copy to system clipboard
ssh-key-now() {
	cat /dev/zero | ssh-keygen -t ed25519 -C "made with ssh-key-now" -q -N ""
	xclip -sel clip <~/.ssh/id_ed25519.pub
	echo "ssh-key copied to clipboard"
}

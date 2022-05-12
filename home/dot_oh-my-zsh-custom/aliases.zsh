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
alias git-rm-merged-dev="git branch --merged dev | grep -v '^[ *]*dev$' | xargs git branch -d; git remote prune origin"
alias git-branch-pmr="git push -o merge_request.create -o merge_request.remove_source_branch -o merge_request.target"

## GITLAB
# This alias is useful when you want to automatically create a merge request on gitlab and the source branch still does not exist in the remote repository.
alias gitlab-push-mr="git push --set-upstream \`git remote | tail -1\` \`git rev-parse --abbrev-ref HEAD\` -o merge_request.create -o merge_request.target=\`git remote show \$(git remote) | grep 'HEAD branch' | cut -d ' ' -f5\`"


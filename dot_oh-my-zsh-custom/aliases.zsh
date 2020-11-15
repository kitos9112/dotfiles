# Here lives all the aliases useful for me!
alias brewup="brew update && brew upgrade && brew upgrade --cask && brew cleanup -v -s && brew doctor"

# AWS
alias aws-get-instanceid='export AWS_EC2_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${AWS_EC2_INSTANCE_NAME}" --output text --query "Reservations[*].Instances[*].InstanceId") && echo ${AWS_EC2_INSTANCE_ID}'
# BREW

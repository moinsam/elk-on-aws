#!/bin/bash
STACK_NAME=elastic-es-bootstrap

while getopts a:u:d: flag
do
  case "${flag}" in
    a) action=${OPTARG};;
    u) update=${OPTARG};;
    d) destroy=${OPTARG};;
  esac
done

if [ "$action" = "destroy" ]; then
  aws cloudformation delete-stack --stack-name $STACK_NAME
else
  echo "For sure you don't want to delete this stack."
  if ! aws cloudformation describe-stacks --stack-name $STACK_NAME > /dev/null 2>&1; then
      aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://elastic-es-bootstrap.yaml --parameters file://elastic-es-bootstrap.params.json --capabilities CAPABILITY_IAM
  else
      aws cloudformation update-stack --stack-name $STACK_NAME --template-body file://elastic-es-bootstrap.yaml --parameters file://elastic-es-bootstrap.params.json --capabilities CAPABILITY_IAM
  fi
fi
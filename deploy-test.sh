#!/bin/zsh

export $(grep -v '^#' .env.deploy-test | xargs)
forge script script/DeployForMultisig.s.sol \
  --chain-id 1 \
  --broadcast \
  --legacy \
  --force \
  --private-key ${DEPLOYER_PRIVATE_KEY} \
  -vv


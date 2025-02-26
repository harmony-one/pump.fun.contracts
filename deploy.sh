#!/bin/zsh

export $(grep -v '^#' .env.deploy | xargs)
forge script script/Deploy.s.sol \
  --chain-id 1 \
  --broadcast \
  --legacy \
  --private-key ${DEPLOYER_PRIVATE_KEY} \
  -vv


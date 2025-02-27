#!/bin/zsh

export $(grep -v '^#' .env.deploy | xargs)
forge script script/Deploy.s.sol \
  --chain-id 1666600000 \
  --gas-price 100000000000 \
  --broadcast \
  --legacy \
  --private-key ${DEPLOYER_PRIVATE_KEY} \
  -vv


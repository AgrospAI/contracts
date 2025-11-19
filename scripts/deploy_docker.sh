#!/bin/bash

# default to false in case it is not set
DEPLOY_CONTRACTS="${DEPLOY_CONTRACTS:-false}"

if [ "${DEPLOY_CONTRACTS}" = "true" ]
then
    echo "Deploying Contracts..."

    export NETWORK="${NETWORK_NAME?Missing NETWORK_NAME var}"
    echo "Cleaning"
    npx hardhat clean
    echo "Compiling"
    npx hardhat compile
    #remove unneeded debug artifacts
    find /ocean-contracts/artifacts/* -name "*.dbg.json" -type f -delete
    #copy address.json
    if [ -e /ocean-contracts/addresses/address.json ]
        then cp -u /ocean-contracts/addresses/address.json /ocean-contracts/artifacts/
    fi
    echo "Starting deployment process..."
    node /ocean-contracts/scripts/deploy-contracts.js
fi
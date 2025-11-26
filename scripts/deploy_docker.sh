#!/bin/bash

if [ "${DEPLOY_CONTRACTS}" = "true" ]
then
    echo "Deploying Contracts..."
    rm /ocean-contracts/artifacts/ready

    npx hardhat clean
    npx hardhat compile
    #remove unneeded debug artifacts
    find /ocean-contracts/artifacts/* -name "*.dbg.json" -type f -delete
    #copy address.json
    if [ -e /ocean-contracts/addresses/address.json ]
        then cp -u /ocean-contracts/addresses/address.json /ocean-contracts/artifacts/
    fi
    echo "Starting deployment process..."
    node /ocean-contracts/scripts/deploy-contracts.js
    touch /ocean-contracts/artifacts/ready
fi

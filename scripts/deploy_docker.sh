#!/bin/bash

if [ -f "/ocean-contracts/ccache/deployed" ]
then
    echo "Contracts already deployed"
    exit 0
fi


if [ "${DEPLOY_CONTRACTS}" = "true" ]
then
    echo "Deploying Contracts..."
    rm -f /ocean-contracts/artifacts/ready

    #copy address.json
    if [ -e /ocean-contracts/addresses/address.json ]
        then cp -u /ocean-contracts/addresses/address.json /ocean-contracts/artifacts/
    fi
    echo "Starting deployment process..."
    node /ocean-contracts/scripts/deploy-contracts.js
    touch /ocean-contracts/artifacts/ready
    touch /ocean-contracts/ccache/deployed
fi

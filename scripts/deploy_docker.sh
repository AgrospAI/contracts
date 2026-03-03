#!/bin/bash

if [ -f "./ccache/deployed" ]; then
    echo "Contracts already deployed"
else

    if [ ! -e ./outputs/ ]; then
        mkdir ./outputs/
    fi

    if [ "${DEPLOY_CONTRACTS}" = "true" ]; then
        echo "Deploying Contracts..."
        rm -f ./outputs/ready

        echo "Starting deployment process..."

        node ./scripts/deploy-contracts.js
        
        # Copy updated addresses into the outputs
        if [ -e ./addresses/address.json ]; then 
            echo "Copying addresses"
            cp ./addresses/address.json ./outputs/
        else
            echo "Addresses not found"
        fi
        
        touch ./ccache/deployed
    fi

    # Copy to destination folder
    echo "Copying contracts..."

    cp -r ./artifacts/. ./outputs/

fi

if [ ! -e ./outputs/ready ]; then
    touch ./outputs/ready
fi
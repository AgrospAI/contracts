
FROM --platform=linux/amd64 ubuntu:22.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
ENV NVM_DIR=/usr/local/nvm
ENV NODE_VERSION=v20.16.0
RUN apt-get update &&\
    apt-get -y install curl bash    
RUN mkdir -p /usr/local/nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash &&\
    /bin/bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION && nvm use --delete-prefix $NODE_VERSION"
# add node and npm to the PATH
ENV NODE_PATH=$NVM_DIR/versions/node/$NODE_VERSION/bin
ENV PATH=$NODE_PATH:$PATH



FROM base AS builder
RUN apt-get update && apt-get install -y python3.9 python3-dev python3-pip build-essential git libffi-dev libssl-dev
RUN python3 -m pip install --upgrade pip setuptools wheel
RUN python3 -m pip install cython==0.29.36

COPY . /ocean-contracts
WORKDIR /ocean-contracts
RUN npm i




FROM base AS runner
ENV NETWORK=barge
ENV NETWORK_RPC_URL=127.0.0.1:8545
RUN mkdir -p /ocean-contracts /ocean-contracts/test/
COPY ./addresses /ocean-contracts/addresses/
COPY ./contracts /ocean-contracts/contracts/
COPY ./hardhat.config* /ocean-contracts/
COPY ./package.json /ocean-contracts/
COPY ./scripts /ocean-contracts/scripts/
COPY ./test /ocean-contracts/test/
WORKDIR /ocean-contracts
COPY --from=builder /ocean-contracts/node_modules/ /ocean-contracts/node_modules/
RUN cp hardhat.config.barge.js hardhat.config.js
RUN npx hardhat clean &&\
    npx hardhat compile --force &&\
    rm -rf /ocean-contracts/artifacts/*
ENTRYPOINT ["/ocean-contracts/scripts/deploy_docker.sh"]

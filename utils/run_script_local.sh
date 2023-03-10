#!/usr/bin/env bash

# Read the RPC URL
source .env

## Start Anvil
echo Please wait a few seconds for anvil to start...
anvil --silent &

# Wait for anvil to fork
sleep 2

# Read script
read -p "Enter script to run [default: Deploy]: " script
script=${script:-Deploy}

# Read script arguments
echo "Enter script arguments [default: none]: "
read -ra args

# Load deployer account
cast rpc --rpc-url http://localhost:8545 anvil_setBalance 0xBA5ED0f7622041FA6Ae4F7040f6865303ff6DbeD 0x99999999999999999999

# Run the script
echo Running Script: $script

# We specify the anvil url as http://localhost:8545
# We need to specify the sender for our local anvil node
forge script $script \
    --fork-url http://localhost:8545 \
    --broadcast \
    -vvvv \
    --sender 0xBA5ED0f7622041FA6Ae4F7040f6865303ff6DbeD \
    --private-key 0x43196f4dfd3c8dc66c7845313b8e025d567f6e53f921f48a8667ad123a40b501 \
    $args

# Once finished, we want to kill our anvil instance running in the background
trap "exit" INT TERM
trap "kill 0" EXIT
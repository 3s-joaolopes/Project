#!/usr/bin/env bash

# Read the private key
source .env

# Read script
read -p "Enter script to run [default: Deploy]: " script
script=${script:-Deploy}
echo $script

# Read script arguments
echo "Enter script arguments [default: none]: "
read -ra args

# Read network
read -p "Enter network name [default: goerli]: " network
network=${network:-goerli}
echo $network

# Run the script
echo Running Script: $script

# Run the script with interactive inputs
forge script $script \
    -f $network \
    --broadcast \
    -vvvv \
    --private-key $PRIVATE_KEY \
    $args
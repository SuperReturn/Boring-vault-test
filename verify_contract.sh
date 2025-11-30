#!/bin/bash

# Configuration variables
CHAIN_ID=1
ETHERSCAN_API_KEY=

DEPLOYER=0xb654e5d7F1dbFCe3945551a72764e7b06DB25994
ROLE_VAULT=0x0953c2E6c82633CdA982E90A6287f66493c5cF0B
PROXY_VAULT=0x15f3Ee2F609FBAe0bC48E3a071D66DD917C682EB
IMPLEMENTATION_VAULT=0xe9460F59824a047cCCd794af254c8A467c6D05fa
ACCOUNTANT=
FIXED_ACCOUNTANT=0x0427645BceA78A84A84eFBc26d51f87176581cd9
LEN=0x1E0f8Cad571643e52C1FAcDBB2C005141c2f4b66
MANAGER=0xA78e8Ae84BEc9E66486fbC0e87E720Fd6342ef39
TELLER=0xF62D61F304C9c65C96a94c2b0b93c8f93C96e91D
QUEUE=0xf3aA6324Aa5C9Ded16Eb7ED651152aC30588BAc1
SOLVER=0x1DB629316B3fB6B026f9ebD5c379a72235a4d5E9
ROLE_QUEUE=0x58A6481706E4260ef50D362401C7F0357b13AB53

# Function to verify contract with common parameters
verify_contract() {
    local contract_address=$1
    local contract_path=$2
    
    forge verify-contract \
        --chain-id $CHAIN_ID \
        --watch \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --compiler-version 0.8.21 \
        --optimizer-runs 200 \
        --verifier etherscan \
        --verifier-url "https://api.etherscan.io/v2/api" \
        $contract_address \
        $contract_path
}

# Verify contracts
verify_contract $DEPLOYER src/helper/Deployer.sol:Deployer
verify_contract $ROLE_VAULT lib/solmate/src/auth/authorities/RolesAuthority.sol:RolesAuthority
verify_contract $PROXY_VAULT src/base/BoringVault.sol:BoringVault
verify_contract $IMPLEMENTATION_VAULT src/base/BoringVault.sol:BoringVault
verify_contract $ACCOUNTANT src/base/Roles/AccountantWithRateProviders.sol:AccountantWithRateProviders
verify_contract $FIXED_ACCOUNTANT src/base/Roles/AccountantWithRateProviders2.sol:AccountantWithRateProviders2
verify_contract $LEN src/helper/ArcticArchitectureLens.sol:ArcticArchitectureLens
verify_contract $MANAGER src/base/Roles/ManagerWithMerkleVerification.sol:ManagerWithMerkleVerification
verify_contract $TELLER src/base/Roles/TellerWithMultiAssetSupport.sol:TellerWithMultiAssetSupport
verify_contract $QUEUE src/atomic-queue/AtomicQueue.sol:AtomicQueue
verify_contract $SOLVER src/atomic-queue/AtomicSolverV4.sol:AtomicSolverV4
verify_contract $ROLE_QUEUE lib/solmate/src/auth/authorities/RolesAuthority.sol:RolesAuthority
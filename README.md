## FL-Zerolend

A Solidity smart contract for managing leveraged positions in the Zerolend protocol.

### Todo

- [ ] Add more tests
- [ ] Add fuzzing
- [ ] Docs
- [ ] PoC UI
- [ ] Replace ugly imports with remappings

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

1. Clone the repository:

```bash
git clone https://github.com/Keyring-Network/fl-zerolend.git
cd fl-zerolend
```

2. Install dependencies:

```bash
forge soldeer install
```

3. Run all tests:

```bash
forge test --force
```

### Deployment

1. Copy the environment file and prepare your private key and other credentials:

```bash
cp .env.example .env
# Edit .env with your private key and API keys
```

2. Deploy the contract:

```bash
source .env && forge script script/DeployLeveragedPositionManagerScript.sol \
    --force \
    --broadcast \
    --rpc-url $RPC_URL \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verifier-url $ETHERSCAN_BASE_API_URL \
    --retries 20
```

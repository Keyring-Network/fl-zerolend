## FL-Zerolend

A Solidity smart contract for managing leveraged positions in the Zerolend protocol.

### Todo

- [ ] Add more tests
- [ ] Add fuzzing
- [ ] Docs
- [ ] PoC UI
- [ ] Replace ugly imports with remappings

### Logic

|                                                | **Flash Loan Amount > 0**<br>(Borrow extra funds)                                                                                                                                                                                                                                                         | **Flash Loan Amount < 0**<br>(Repay debt)                                                                                      | **Flash Loan Amount = 0**<br>(No extra adjustment) |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **tokenAmount > 0**<br>(User supplies tokens)  | **Action:**<br>- Supply the user’s tokens along with the flash loan funds as additional collateral.<br>- Then borrow an extra amount equal to the flash loan \(X\) so that overall debt increases accordingly (i.e. “top up” your borrowing to achieve the higher leverage).                              | **Action:**<br>- Supply the user’s tokens (deposit).<br>- Use available funds (or a flash loan that provides cash) to repay \( | X                                                  | \) of the debt, lowering overall debt to meet the lower target LTV.                                                                           | **Action:**<br>- Simply supply the tokens.<br>No extra flash loan operation is needed because the new deposit alone achieves the target LTV.       |
| **tokenAmount < 0**<br>(User withdraws tokens) | **Action:**<br>- Withdraw the specified tokens.<br>- Additionally, take a flash loan for \(X\) (a positive amount) to add extra collateral (by supplying the flash loan funds) and simultaneously borrow that amount so that overall debt increases to reach the higher target LTV even after withdrawal. | **Action:**<br>- Withdraw the specified tokens.<br>- Use available funds (or a flash loan that provides cash) to repay \(      | X                                                  | \) of your debt, reducing the debt to meet the lower target LTV.<br>_This occurs when the withdrawal alone would overshoot the target ratio._ | **Action:**<br>- Simply withdraw the tokens.<br>No additional adjustment is needed because the withdrawal alone naturally achieves the target LTV. |
| **tokenAmount = 0**<br>(No collateral change)  | **Action:**<br>- With no collateral movement, use a flash loan for \(X\) (positive) to “top up” your position.<br>- The flash loan funds are added to your collateral and reborrowed so that your debt increases to meet the higher target LTV.                                                           | **Action:**<br>- With no collateral movement, use a flash loan for \(                                                          | X                                                  | \) (negative) to repay part of your debt, thereby reducing the overall debt so that the LTV falls to the target level.                        | **Action:**<br>- Do nothing — the current position already meets the target LTV.                                                                   |

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

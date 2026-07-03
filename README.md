# ReputationAIBounty – Reputation-Based Verification

This contract uses a **reputation system** where participants earn reputation for honest participation. Winners are selected based on AI scores, votes, and reputation bonuses.

## How it works
1. **Register**: Users must register to get initial reputation (100 points)
2. **Commit phase**: Participants submit hashed answers
3. **Reveal phase**: Participants reveal answers (earns +10 reputation)
4. **AI scoring**: Owner sets AI scores for all submissions
5. **Vote phase**: Participants vote with weight = reputation / 10
6. **Finalization**: Winner = AI score + votes + reputation bonus

## Why reputation?
Incentivizes long-term honest participation without requiring economic deposits.

## Contract Address (Ritual Testnet)
 0xe29D82B3b3577b2867e8830D57B07eA7efF9120F

## Network
Ritual Chain Testnet (ID: 1979)

## Native Token
RIT (Ritual Token) – 18 decimals

# Test Plan – ReputationAIBounty

- Happy path: 3 participants register → commit → reveal → AI scores → vote → finalize
- Cannot commit without registration (reverts)
- Cannot reveal before deadline (reverts)
- Cannot vote without AI scores (reverts)
- Reputation changes correctly (+10 for reveal, +5 for vote, +25 for winner)
- Non-revealers lose reputation (-30)

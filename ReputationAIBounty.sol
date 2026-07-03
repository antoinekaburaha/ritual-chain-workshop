// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReputationAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 voteDeadline;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) votesReceived;
        uint256 totalVotes;
        bool judged;
        mapping(address => uint256) aiScores;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 voteDeadline;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        uint256 totalVotes;
        bool judged;
    }

    // Reputation tracking
    mapping(address => uint256) public reputation;
    mapping(address => uint256) public participationCount;
    mapping(address => bool) public isRegistered;

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    uint256 public constant INITIAL_REPUTATION = 100;
    uint256 public constant REPUTATION_REVEAL_BONUS = 10;
    uint256 public constant REPUTATION_VOTE_BONUS = 5;
    uint256 public constant REPUTATION_WINNER_BONUS = 25;
    uint256 public constant REPUTATION_NON_REVEAL_PENALTY = 30;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event VoteCast(uint256 indexed id, address indexed voter, address indexed candidate, uint256 weight);
    event WinnerFinalized(uint256 indexed id, address indexed winner);
    event ReputationChanged(address indexed participant, uint256 oldRep, uint256 newRep);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyVotePhase(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Not vote phase");
        require(block.timestamp <= challenges[id].voteDeadline, "Vote phase ended");
        _;
    }

    modifier onlyAfterVote(uint256 id) {
        require(block.timestamp > challenges[id].voteDeadline, "Vote phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function registerUser() external {
        require(!isRegistered[msg.sender], "Already registered");
        isRegistered[msg.sender] = true;
        reputation[msg.sender] = INITIAL_REPUTATION;
        emit ReputationChanged(msg.sender, 0, INITIAL_REPUTATION);
    }

    function getReputation(address user) external view returns (uint256) {
        if (!isRegistered[user]) return 0;
        return reputation[user];
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        uint256 voteDuration
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(voteDuration > 0, "Vote duration must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.voteDeadline = c.revealDeadline + voteDuration;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        require(isRegistered[msg.sender], "Must register first");
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealAnswer(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);

        // Award reputation for revealing
        uint256 oldRep = reputation[msg.sender];
        reputation[msg.sender] += REPUTATION_REVEAL_BONUS;
        participationCount[msg.sender]++;
        emit ReputationChanged(msg.sender, oldRep, reputation[msg.sender]);

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function setAIScores(
        uint256 id,
        address[] calldata participants,
        uint256[] calldata scores
    ) external 
        challengeExists(id)
        onlyOwner(id)
        onlyRevealPhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(!c.judged, "Already judged");
        require(participants.length == scores.length, "Length mismatch");

        for (uint i = 0; i < participants.length; i++) {
            require(c.hasRevealed[participants[i]], "Participant not revealed");
            c.aiScores[participants[i]] = scores[i];
        }

        c.judged = true;
    }

    function castVote(uint256 id, address candidate) external 
        challengeExists(id)
        onlyVotePhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.hasRevealed[msg.sender], "Must have revealed to vote");
        require(!c.hasVoted[msg.sender], "Already voted");
        require(c.hasRevealed[candidate], "Candidate must have revealed");
        require(c.judged, "AI must judge first");
        require(candidate != msg.sender, "Cannot vote for yourself");

        // Voting power = reputation / 10 (minimum 1)
        uint256 voteWeight = reputation[msg.sender] / 10;
        if (voteWeight < 1) voteWeight = 1;

        c.votesReceived[candidate] += voteWeight;
        c.totalVotes += voteWeight;
        c.hasVoted[msg.sender] = true;

        // Award reputation for voting
        uint256 oldRep = reputation[msg.sender];
        reputation[msg.sender] += REPUTATION_VOTE_BONUS;
        emit ReputationChanged(msg.sender, oldRep, reputation[msg.sender]);

        emit VoteCast(id, msg.sender, candidate, voteWeight);
    }

    function finalizeWinner(uint256 id) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterVote(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.judged, "AI must judge first");
        require(c.totalVotes > 0, "No votes cast");

        address winner = c.participants[0];
        uint256 maxScore = 0;

        // Calculate total score = AI score + votes + reputation bonus
        for (uint i = 0; i < c.participants.length; i++) {
            address participant = c.participants[i];
            if (!c.hasRevealed[participant]) {
                // Penalize non-revealers
                uint256 oldRep = reputation[participant];
                if (reputation[participant] >= REPUTATION_NON_REVEAL_PENALTY) {
                    reputation[participant] -= REPUTATION_NON_REVEAL_PENALTY;
                } else {
                    reputation[participant] = 0;
                }
                emit ReputationChanged(participant, oldRep, reputation[participant]);
                continue;
            }
            
            uint256 repBonus = reputation[participant] / 20;
            uint256 totalScore = c.aiScores[participant] + c.votesReceived[participant] + repBonus;
            if (totalScore > maxScore) {
                maxScore = totalScore;
                winner = participant;
            }
        }

        c.finalized = true;
        c.winner = winner;

        // Award reputation bonus to winner
        uint256 oldRep = reputation[winner];
        reputation[winner] += REPUTATION_WINNER_BONUS;
        emit ReputationChanged(winner, oldRep, reputation[winner]);

        // Send reward
        payable(winner).transfer(c.reward);

        emit WinnerFinalized(id, winner);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            voteDeadline: c.voteDeadline,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            totalVotes: c.totalVotes,
            judged: c.judged
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function getAIScore(uint256 id, address participant) external view returns (uint256) {
        return challenges[id].aiScores[participant];
    }

    function getVotes(uint256 id, address participant) external view returns (uint256) {
        return challenges[id].votesReceived[participant];
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function hasVoted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasVoted[participant];
    }
}

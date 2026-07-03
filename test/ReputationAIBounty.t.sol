// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/ReputationAIBounty.sol";

contract ReputationAIBountyTest is Test {
    ReputationAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 charlieCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    bytes32 charlieSalt = keccak256("charlie_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";
    string charlieAnswer = "Charlie's solution";
    uint256 reward = 1 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
        bounty = new ReputationAIBounty();
        
        // Register users
        vm.startPrank(alice);
        bounty.registerUser();
        vm.stopPrank();
        
        vm.startPrank(bob);
        bounty.registerUser();
        vm.stopPrank();
        
        vm.startPrank(charlie);
        bounty.registerUser();
        vm.stopPrank();

        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, 3 days);
        challengeId = 0;
        vm.stopPrank();
        
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
        charlieCommitment = keccak256(abi.encodePacked(charlieAnswer, charlieSalt, charlie, challengeId));
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        vm.startPrank(charlie);
        bounty.submitCommitment(challengeId, charlieCommitment);
        vm.stopPrank();

        // Reveal
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        vm.startPrank(charlie);
        bounty.revealAnswer(challengeId, charlieAnswer, charlieSalt);
        vm.stopPrank();

        // Set AI scores
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 85;
        scores[1] = 90;
        scores[2] = 80;

        vm.startPrank(owner);
        bounty.setAIScores(challengeId, participants, scores);
        vm.stopPrank();

        // Vote
        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.castVote(challengeId, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.castVote(challengeId, alice);
        vm.stopPrank();

        vm.startPrank(charlie);
        bounty.castVote(challengeId, bob);
        vm.stopPrank();

        // Finalize
        vm.warp(block.timestamp + 3 days + 1);
        vm.startPrank(owner);
        bounty.finalizeWinner(challengeId);
        vm.stopPrank();

        ReputationAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + reward);
    }

    function testCannotCommitWithoutRegistration() public {
        address unregistered = address(0x5);
        vm.startPrank(unregistered);
        vm.expectRevert("Must register first");
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }

    function testCannotVoteWithoutAI() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        vm.expectRevert("AI must judge first");
        bounty.castVote(challengeId, alice);
        vm.stopPrank();
    }

    function testReputationChanges() public {
        uint256 aliceRep = bounty.getReputation(alice);
        assertEq(aliceRep, 100);

        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        uint256 aliceRepAfterReveal = bounty.getReputation(alice);
        assertEq(aliceRepAfterReveal, 110); // 100 + 10
    }
}

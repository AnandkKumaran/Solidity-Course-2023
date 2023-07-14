// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Dao} from "../src/Dao.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Dao dao;
    TimeLock timelock;
    GovToken govToken;

    address public USER = makeAddr("User");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executers;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    uint256 public constant MIN_DELAY = 3600; // 1 hour
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);

        govToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executers);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));

        timelock.revokeRole(adminRole, USER);

        vm.stopPrank();

        dao = new Dao();
        dao.transferOwnership(address(timelock));
    }

    function testCantUpdateDaoWithoutGovernance() public {
        vm.expectRevert();
        dao.store(1);
    }

    function testGovernanceUpdatesDao() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(dao));

        // 1. Propose to the dao
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log(proposalId);
        // View the state
        console.log("Proposal State", uint256(governor.state(proposalId)));
        console.log(block.timestamp, block.number);

        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.roll(block.number + VOTING_DELAY + 1);

        console.log(block.timestamp, block.number);

        console.log("Proposal State", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "Its cool";

        uint8 voteWay = 1; // voting YES

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. QUEUE the Tx
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        assert(dao.getNumber() == valueToStore);

        console.log("Get Number", dao.getNumber());
    }
}

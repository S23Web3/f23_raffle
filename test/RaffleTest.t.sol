//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "./mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig helperConfig = new HelperConfig();

    event RequestedRaffleWinner(uint256 indexed requestId);
    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed player);

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinatorV2;
    bytes32 gasLane; //keyhash
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        (
            entranceFee,
            interval,
            vrfCoordinatorV2,
            gasLane, //keyhash
            subscriptionId,
            callbackGasLimit,
            link,
        ) = helperConfig.activeNetworkConfig();
    }

    //first let's test if the raffle starts as open
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////.........RaffleEntry..........////////////////////

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //arrange
        // we represent ourselves as a player
        vm.prank(PLAYER);

        //expecting the exact error to revert, in the next line to call
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSentToEnter.selector);
        raffle.enterRaffle();

        //assert
    }

    //      has to happen with PerformUpkeep and checkupkeep needs to be true so below is not allowed I guess
    //    function testRaffleRevertsWhenRaffleIsNotOpen() public {
    //     //Patrick skipped this because he mentioned it is not important/lazy now.
    //     // arrange
    //     // we represent ourselves as a player
    //     vm.prank(PLAYER);

    //     // Set the raffle state to CALCULATING
    //     raffle.setRaffleStateCalculating();

    //     // expecting the exact error to revert, in the next line to call
    //     vm.expectRevert(Raffle.Raffle__RaffleIsNotOpen.selector);
    //     raffle.enterRaffle{value: entranceFee}();

    //     // assert
    // }

    // function testSetRaffleStateCalculatingCanOnlyBeCalledByOwner() public {
    //     // Arrange
    //     // Representing as a player
    //     vm.prank(PLAYER);

    //     // Act & Assert
    //     // Expecting the exact error to revert, in the next line to call
    //     vm.expectRevert(Raffle__CallerIsNotTheOwner());
    //     raffle.setRaffleStateCalculating();
    // }

    function testRaffleRecordsWhenPlayerIsEntered() public {
        //see if the players array gets updated, create getter then see if the player is in the array at index 0
        //arrange
        // we represent ourselves as a player this time with money to enter, PLAYER is an address
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        //call raffle
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitEventsOnEntrance() public {
        //expecting the emit event at the end of the enterRaffle function with expectRevert from foundry
        //emit EnteredRaffle(msg.sender); with the address from the emitter( the raffle contract)
        vm.prank(PLAYER);
        //Act,Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        //final is to make the funciton the call that launches the event

        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        // player enters raffle
        // vm.prank(PLAYER);
        // raffle.enterRaffle{value: entranceFee}();

        // //block time set with vm.roll and vm.warp to speed up the time on anvil
        // vm.warp(block.timestamp + interval + 1);
        // vm.roll(block.number + 1);
        // raffle.performUpkeep("");
        // //now time passed and the raffle should not be open
        // vm.expectRevert(Raffle.Raffle__RaffleIsNotOpen.selector);
        // vm.prank(PLAYER);
        // raffle.enterRaffle{value: entranceFee}();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //had to add a whole shebang so the vrfCoordinatorV2 is expecting the call
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///now checkupkeep///
    function testCheckUpKeepFalseIfItHasNoBalanceOthersTrue() public {
        //Arrange
        //other variables are true
        //timeHasPassed is true bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //raffle is open by default in the constructor and tested prior at testRaffleInitializesInOpenState
        //Act
        //checkUpkeep has "" because there are no tweakings to check the upkeep
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        //upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        //raffle must be open because bool isOpen = RaffleState.OPEN == s_raffleState;
        //assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        //s_players must have an entry because bool hasPlayers = s_players.length > 0;
        //assert(raffle.getPlayerCount() > 0);
        //no money sent so should not run upkeepNeeded
        assert(!upkeepNeeded);

        //Assert
    }

    function testCheckupkeepisFalseWhenRaffleIsNotOpenOthersTrue() public {
        //Arrange
        //other variables are true
        //player entered the raffle so there is a player in the s_players length
        //because must be true bool hasBalance = address(this).balance > 0;

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        //timeHasPassed is true
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //raffle is open by default in the constructor and tested prior at testRaffleInitializesInOpenState

        //performUpkeep has "" because there are no tweakings to check the upkeep
        raffle.performUpkeep("");
        //now the calculating state is active
        //Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        //upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        //Assert
        //there should be a player in the players array so first I am doing that assert
        assert(raffle.getNumberOfPlayers() > 0);
        //now I can check if it returns false because the Raffle is not open
        assert(upkeepNeeded == false); //same as assert(!upkeepNeeded);
    }
    //there was one test to check in this which is it should fail if time did not pass

    function testCheckupkeepisFalseWhenTimeHasNotPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        //see test above for the comments on why I do the asserts
        assert(raffle.getNumberOfPlayers() > 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(address(this).balance > 0);
        assert(upkeepNeeded == false);
    }

    function testCheckupkeepReturnsTrueWhenAllParametersAreMet() public {
        //so first all needs to be true, explanations are in the tests above if needed
        //it is basically the previous test with enough time has passed
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //timeHasPassed is true
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        //Patrick does not assert the other conditions as true, so i commented them out.
        //there is a player in players testRaffleRecordsWhenPlayerIsEntered has tested that it works
        // assert(raffle.getPlayerCount() > 0);
        // //raffle state should be open by default when the function comes here
        // assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);

        // assert(address(this).balance > 0);
        //all should be good so the above is all true and so is the below
        assert(upkeepNeeded == true);
    }
    //////////////////////////
    ///   performUpkeep    ///
    //////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public RaffleEnteredAndTimePassed {
        /*
        This should return true  so and address(this).balance && s_players.length is valid && uint256 RaffleState = 0
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                //give the state in uint256 0,1 so it is typecasted
                uint256(s_raffleState)
            );
        }
        */
        //from the previous test all Checkupkeeps are true
        // used the modifier so refactored the commented below
        // vm.prank(PLAYER);
        // raffle.enterRaffle{value: entranceFee}();
        // vm.warp(block.timestamp + interval + 1);
        // vm.roll(block.number + 1);

        //do performUpkeep, there is no expect not revert in foundry, so if it does not revert, test is considered passed
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        //try just to run raffle.performUpkeep("") should expect false, but setting which reason it gave as 0

        uint256 currentBalance = 0; //address(this).balance
        uint256 numPlayers = 0; //s_players.length
        uint256 raffleOpen = 0; //Raffle_state is open so performUpkeep can not work because it only works on calculating which is 1
        // in foundry docs it is explained how to do this with abi.encode vm.expectRevert(Raffle.Raffle__UpkeepNotNeeded(/* reasons */))

        //Act/assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleOpen)
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public RaffleEnteredAndTimePassed {
        //using recordlogs for the first time which is a help in foundry tells VM to start recording all events, see it with getRecordLogs

        //Act (Arrange is done in modifier)
        vm.recordLogs();
        raffle.performUpkeep(""); //emitting the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //2nd entry because the first is the one of request in the mock requestrandomwords
        //we need to know the different type of events to find where in the array it is emitted, we can use debugger,
        bytes32 requestId = entries[1].topics[1]; //all events are recorded as bytes32 0 topic is the entire event, 1st topic is the requestId
        Raffle.RaffleState rState = raffle.getRaffleState(); // get the rafflestate and store in rstate
        assert(uint256(requestId) > 0); //wrap the bytes32 as uint256 to be able to evaluate if it is greater than 0
        assert(uint256(rState) == 1); //raffle State is 1 for calculating
    }

    ///////////////////////////////
    ///   fulfillRandomwords    ///
    ///////////////////////////////

    modifier RaffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        // isolates out test functions that will only run on anvil, particular ones where we are testing responses of the vrf
        //issue is particular because real mock wants to have Proof
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        RaffleEnteredAndTimePassed
        skipFork
    {
        //Arrange
        //call fulfillrandomwords and it should fail
        vm.expectRevert("nonexistent request"); //removed the space between non and existent and it passed
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(uint256(randomRequestId), address(raffle)); //pretending to be the vrfcoordinator, parameters are requestid AND address of the consumer
            // in the mock if there is no requestid then get nonexistent request
            // there are too many requestids so we need to do a fuzz test
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public RaffleEnteredAndTimePassed skipFork {
        //enter the lottery a couple of times, performupkeep, pretend vrfcoordinator, respond and call fulfillrandomwords
        //Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1; //one person already entered with RaffleEnteredAndTimePassed, not starting with index 0
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            //generate more people to enter
            address player = address(uint160(i)); //address of i
            hoax(player, STARTING_PLAYER_BALANCE); //equivalent to prank + deal
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); //kickoff requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        //pretend to be vrfcoordinator and get random number and pick winner, the consumer is the raffle contract, requestid is from last test
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(uint256(requestId), address(raffle));

        //some cleanup because of double use
        address recentWinner = raffle.getRecentWinner();
        uint256 winnerBalance = recentWinner.balance;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 playersInArray = raffle.getNumberOfPlayers();
        uint256 endingTimeStamp = raffle.getLastTimeStamp();

        // assert
        // best practice is to have 1 assert per test for when it breaks, it is clear where the error is
        //raffle is open, winner is picked, players array is empty time is updated, recentwinner is 0 after it is done
        assert(uint256(raffleState) == 0); //raffle needs to be open after the bonanza is done
        assert(raffle.getRecentWinner() != address(0)); //there should be a recent winner
        // already made a get players length being getPlayerCount to variable playersInArray
        assert(playersInArray == 0);
        assert(previousTimeStamp < endingTimeStamp);

        console.log(winnerBalance);
        console.log(prize + STARTING_PLAYER_BALANCE);
        assert(winnerBalance == STARTING_PLAYER_BALANCE + prize - entranceFee); //Pat got an error that the prize - entrancefee was the right answer...forge
    }

    //write a test that PickedWinner is emitted
}

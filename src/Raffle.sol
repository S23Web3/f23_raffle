//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    error Raffle__NotEnoughETHSentToEnter();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 numPlayers, uint256 raffleState);
    //error Raffle__CallerIsNotTheOwner();

    /*Type Declarations*/

    enum RaffleState {
        OPEN, // this will be
        CALCULATING // this will be 1

    }
    /*State variables*/
    // number of block confirmations for the random number to be considered good, needs to be uint16

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    //only need one word for number of random winners (1), needs to be uint32
    uint32 private constant NUM_WORDS = 1;

    //the price a player has to pay to enter the raffle
    uint256 private immutable i_entranceFee;
    // @dev duration of the lottery in seconds
    uint256 private immutable i_interval;
    //address of the vrfCoordinator typecasted as VRFCoordinatorV2Interface so we can use the things in the contract
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    //gasLane is a variable which is also immutable and blockchain different
    bytes32 private immutable i_gasLane;
    //chainlink subscription id
    uint64 private immutable i_subscriptionId;
    //max gas to use
    uint32 private immutable i_callbackGasLimit;

    //the array of the players that joined the raffle
    address payable[] private s_players;
    address[] private s_winners;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    // the state of the raffle is defaulted to open (0) at the start of the contract
    RaffleState private s_raffleState;

    event RequestedRaffleWinner(uint256 indexed requestId);
    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed player);

    constructor(
        uint256 raffleEntranceFee,
        uint256 interval,
        address vrfCoordinatorV2,
        bytes32 gasLane, //keyhash
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entranceFee = raffleEntranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        //conditions to enter the raffle
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSentToEnter();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));

        //after the player entered we log out of the contract that this player has joined
        emit EnteredRaffle(msg.sender);
    }

    function checkUpkeep(bytes memory /*checkdata*/ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /*performdata*/ )
    {
        //  1. The time interval has passed between raffle runs.
        //  2. The lottery is open.
        //  3. The contract has ETH.
        //  4. Implicit: subscription is funded with LINK.

        //check to see if enough time has passed
        //get current time is block.timestamp
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        //should there be no check if I have the link?

        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        //return an empty bytes
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        //check if conditions have meet, if not then return:
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                //give the state in uint256 0,1 so it is typecasted
                uint256(s_raffleState)
            );
        }
        //get random number, use to pick a player, once a lottery is done
        //now we change the RaffleState to calculating in order to pick a winner without new entries while it is being calculated
        s_raffleState = RaffleState.CALCULATING;

        //to proveably random pick a winner, we use chainlink vrf, we request a number and then use some formula to pick a winner
        //from the docs we get the variable, getting the chainlink vrf coordinator address (COORDINATOR) which is different chain to chain which is why it is in the constructor
        //returning a requestid uint256 requestId =  deleted for now
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane depending on the chain
            i_subscriptionId, // my id at chainlink
            REQUEST_CONFIRMATIONS, //number of block confirmations for the random number to be considered good
            i_callbackGasLimit, // to make sure we do not overspend on this call, different chains have different cost per gas so it is in the constructor
            NUM_WORDS // number of random words (numbers)
        );
        //using in test to find output of the Event since we can not access the log we do a requestId
        emit RequestedRaffleWinner(requestId);
    }
    //now that it is generated, we need to get the number back, needs a request id and temp randomwords array (I use 1 randomword but yeah, many can be requested and they need to be stored somewhere)
    //function is in vrfconsumerbase so that needs to be imported

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        //using modulo to find a remainder out of the randomnumber to pick a winner.
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        // once the index of the winner is clear, get the address of that winner and pay him/her/it
        address payable winner = s_players[indexOfWinner];
        //reset the players array after the winner is picked

        s_recentWinner = winner;
        //i want an array to keep track of the winners. Maybe also get a mapping in the future of how much they won?
        s_winners.push(winner);
        //I want to reset the array and timestamp  before I open the raffle, Patrick has it after, one might have an entry missing out on some fun in that millisecond
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        //once the winner is selected, the raffle is open to entries again
    }

    /////////////////getters/////////////////

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getPreviousWinner(uint256 index) public view returns (address) {
        return s_winners[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}

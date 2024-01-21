//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        //What are the input parameters for Raffle
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();

        ( //lesson 18 @ 1.03 deconstructing the Networkconfig object into the underlying variables
            uint256 raffleEntranceFee,
            uint256 interval,
            address vrfCoordinatorV2,
            bytes32 gasLane, //keyhash
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(vrfCoordinatorV2, deployerKey);

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(vrfCoordinatorV2, subscriptionId, link, deployerKey);
        }
        vm.startBroadcast(deployerKey);
        Raffle raffle = new Raffle(
            raffleEntranceFee,
            interval,
            vrfCoordinatorV2,
            gasLane, //keyhash
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();
        //We already have a broadcast in here
        addConsumer.addConsumer(address(raffle), vrfCoordinatorV2, subscriptionId, deployerKey);
        return (raffle, helperConfig);
    }
}

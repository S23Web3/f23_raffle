//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        uint256 raffleEntranceFee;
        uint256 interval;
        address vrfCoordinatorV2;
        bytes32 gasLane; //keyhash
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        uint256 deployerKey;
    }

    uint256 constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    event HelperConfig__CreatedMockVRFCoordinator(address VRFCoordinatorV2Mock);

    constructor() {
        if (block.chainid == 1155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            raffleEntranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            vrfCoordinatorV2: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            subscriptionId: 8481, // If left as 0, our scripts will create one!
            callbackGasLimit: 500000, // 500,000 gas
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    //anvilConfig will have more mocks

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        //check if activeNetworkConfig is populated to avoid creating multiple mocks
        if (activeNetworkConfig.vrfCoordinatorV2 != address(0)) {
            return activeNetworkConfig;
        }
        //paid to the VRFCoordinator in Link, set as mocks
        uint96 baseFee = 0.25 ether; //is actually link
        uint96 gasPriceLink = 1e9; // is 1 gwei of Link

        vm.startBroadcast();
        //create a mock of the VRFCoordinatorV2 which is imported
        VRFCoordinatorV2Mock vrfCoordinatorMockV2 = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        LinkToken link = new LinkToken();

        vm.stopBroadcast();

        emit HelperConfig__CreatedMockVRFCoordinator(address(vrfCoordinatorMockV2));

        anvilNetworkConfig = NetworkConfig({
            raffleEntranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            vrfCoordinatorV2: address(vrfCoordinatorMockV2),
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, //misc.
            subscriptionId: 0, // If left as 0, our scripts will create one!
            callbackGasLimit: 500000, // 500,000 gas
            link: address(link),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}

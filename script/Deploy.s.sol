// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {ClaimDepositFactory} from "../src/ClaimDepositFactory.sol";

/// Deploys the factory with the values of `.env.example`, each read from the environment, and the
/// key of DEPLOYER_KEY, which pays the gas (README.md, "Deploy").
contract Deploy is Script {
    function run() external returns (ClaimDepositFactory factory) {
        address token = vm.envAddress("TOKEN");
        address burnAddress = vm.envAddress("BURN_ADDRESS");
        uint256 burnAmount = vm.envUint("BURN_AMOUNT");
        address owner = vm.envAddress("OWNER");
        address operator = vm.envAddress("OPERATOR");
        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        factory = new ClaimDepositFactory(token, burnAddress, burnAmount, owner, operator);
        vm.stopBroadcast();
    }
}

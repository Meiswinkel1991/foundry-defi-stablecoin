// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DecentralizedStableCoin dsc = new DecentralizedStableCoin();

        DSCEngine dscEngine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));

        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}

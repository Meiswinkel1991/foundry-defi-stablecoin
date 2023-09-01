// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    uint256 constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaNetworkConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

        return sepoliaNetworkConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);

        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();

        vm.stopBroadcast();

        NetworkConfig memory anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(wethPriceFeed), // ETH / USD
            wbtcUsdPriceFeed: address(wbtcPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });

        return anvilNetworkConfig;
    }
}

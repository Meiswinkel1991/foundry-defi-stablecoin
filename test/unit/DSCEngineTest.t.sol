// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    uint256 deployerKey;

    function setUp() external {
        deployer = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    /* ======= constructor test ====== */
    address[] public tokenAddresses;
    address[] public pricefeedAddresses;

    function testConstructorRevertsIfTokenLengthDoesntMatchPriceFeeds() external {
        tokenAddresses.push(weth);
        pricefeedAddresses.push(ethUsdPriceFeed);
        pricefeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses,pricefeedAddresses,address(dsc));
    }

    /* ====== Price Tests ====== */

    function testGetUsdValue() external {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    function testGetTokenAmountFromUsd() external {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dscEngine.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    /* ====== despositCollateral Test ====== */
    function testDepositCollRevertsIfCollateralZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositColl(weth, 0);

        vm.stopPrank();
    }
}

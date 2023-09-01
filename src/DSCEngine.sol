// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author Florian Meiswinkel
 *
 * The system is designe to be as minimal as possible, and have the tokens mainatin 1 token == 1$ peg
 *
 * This stablecoin has the properties:
 *  - Exogenous Collateral
 *  - Dollar Pegged
 *  - Algoritmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should be always "overcollateralized". At no point should the value of all collateral < the $ value of Dsc
 *
 * @notice This contract is the core of the DSC system. It handles all of the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /* ====== Errors ====== */
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__DscMintFailed();
    error DSCEngine__HealthfactorIsPermissible();
    error DSCEngine__HealthFactorNotImproved();

    /* ====== State Variables ====== */

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUDITAION_THRESHOLD = 50;
    uint256 private constant LIQUIDIATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    mapping(address token => address pricefeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /* ====== Events ====== */
    event CollateralDeposited(address indexed user, address collToken, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed collToken, uint256 amount
    );

    /* ====== Modifiers ====== */
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedColl(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /* ====== FUNCTIONS ====== */

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /* ====== External Functions ====== */

    /**
     *
     * @param tokenCollAddress: The ERC20 token address of the collateral you're depositing
     * @param amountDeposit:  The amount of collateral you're depositing
     * @param amountToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollAndMintDsc(address tokenCollAddress, uint256 amountDeposit, uint256 amountToMint) external {
        depositColl(tokenCollAddress, amountDeposit);
        mintDsc(amountToMint);
    }

    /**
     * @param tokenCollAddress: The ERC20 token address of the collateral you're depositing
     * @param amountToRedeem: The amount of collateral you're depositing
     * @param amountToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    function redeemCollForDsc(address tokenCollAddress, uint256 amountToRedeem, uint256 amountToBurn) external {
        burnDsc(amountToBurn);
        redeemColl(tokenCollAddress, amountToRedeem);
    }

    /**
     * @param collateral: The erc20 collateral address to liquidate from the user
     * @param user: The user who has broken the healthfactor.
     * @param debtToCover: The amount of DSC want to burn to improve the users healthfactor
     * @notice You can partially liquidate the user
     * @notice You will get a liquidation bonus
     * @notice This function working assumes the protocol will roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocolol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        nonZeroAmount(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthfactorIsPermissible();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDIATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _checkForValidHealthFactor(user);
    }

    /* ====== Public Functions ====== */

    /**
     *
     * @param tokenCollAddress: The address of the token to deposit as collateral
     * @param amount: The amount of collateral to deposit
     */
    function depositColl(address tokenCollAddress, uint256 amount)
        public
        nonZeroAmount(amount)
        isAllowedColl(tokenCollAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollAddress] += amount;

        emit CollateralDeposited(msg.sender, tokenCollAddress, amount);

        bool success = IERC20(tokenCollAddress).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemColl(address tokenCollateralAddress, uint256 amount) public nonZeroAmount(amount) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amount);
        _checkForValidHealthFactor(msg.sender);
    }

    /**
     *
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice the caller must have more collateral value in $ than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public nonZeroAmount(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;

        _checkForValidHealthFactor(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__DscMintFailed();
        }
    }

    function burnDsc(uint256 amount) public nonZeroAmount(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);

        _checkForValidHealthFactor(msg.sender);
    }

    /* ====== Internal Functions ====== */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amount) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amount;

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];

        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Return how close to liquidation a user is. If a user is below 1, then they can liquidated.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAjustedForThreshold = collateralValueInUsd * LIQUDITAION_THRESHOLD / LIQUIDIATION_PRECISION;

        return collateralAjustedForThreshold * PRECISION / totalDscMinted;
    }

    function _checkForValidHealthFactor(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /* ====== External & Public View & Pure Functions ====== */

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 answer,,,) = pricefeed.latestRoundData();

        return usdAmountInWei * PRECISION / (uint256(answer) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 answer,,,) = pricefeed.latestRoundData();

        return (uint256(answer) * ADDITIONAL_FEED_PRECISION) * amount / PRECISION;
    }

    function getHealthFactor() external view {}
}

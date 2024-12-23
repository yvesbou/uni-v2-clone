// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.0.2/utils/ReentrancyGuard.sol";

// todo
/**
 * - find out where rounding down/up is required (always in favor of protocol)
 * - take care of inflation attack
 * - TWAP (price0CumulativeLast..)
 * - flashloan function
 * - fee for LPs à la V3?
 */

/**
 * assumptions
 *  - the precision of a supplied asset cannot change
 *  -
 */
contract Pair is ReentrancyGuard, ERC20 {
    using SafeERC20 for ERC20;

    ERC20 public asset0;
    ERC20 public asset1;

    uint256 public precisionAsset0;
    uint256 public precisionAsset1;
    uint256 constant LP_TOKEN_PRECISION = 1e18;
    uint256 constant FEE_NUMERATOR = 99; // 1%
    uint256 constant FEE_DENOMINATOR = 100; // 1%

    uint256 public reserve0;
    uint256 public reserve1;

    error ZeroAddressNotAllowed();
    error NotEnoughLPTokens();
    error InvalidAsset(address asset);
    error InsufficientAmountOut(uint256 amountOutRequired, uint256 amountOutEffective);
    error NotEnoughLiquidityForSwap();
    error ViolationConstantK(uint256 left, uint256 right);

    event LiquiditySupplied(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event LiquidityRedeemed(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event Swap(
        address indexed spender,
        address indexed receiver,
        address indexed buyingAsset,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(string memory name_, string memory symbol_, address asset0_, address asset1_) ERC20(name_, symbol_) {
        asset0 = ERC20(asset0_);
        asset1 = ERC20(asset1_);
        precisionAsset0 = 10 ** asset0.decimals();
        precisionAsset1 = 10 ** asset1.decimals();
    }

    /// @notice Allows a user to specify which asset he/she wants to buy/sell and how much he/she should get out of it
    /// @notice swapping takes a 1% fee
    /// @param buyingAsset specifies which asset is bought
    /// @param amountIn specifies the amount which is sold
    /// @param amountOutMin specifies the amount that the user wants to get out
    function swap(address receiver, address buyingAsset, uint256 amountIn, uint256 amountOutMin) public nonReentrant {
        // CEI

        // checks

        if (receiver == address(0)) revert ZeroAddressNotAllowed();

        if (buyingAsset != address(asset0) && buyingAsset != address(asset1)) revert InvalidAsset(buyingAsset);

        (uint256 reserve0_, uint256 reserve1_) = getReserves();

        uint256 currentPrice = reserve0_ * precisionAsset1 / reserve1_; // has precision of asset0, precision asset1 cancels out

        // if asset0 -> asset1, amountIn / price, since price = how much asset0 to get asset1
        // 3000USDC -> weth, price 3000 USDC per ether, 3000/price = 1
        //
        uint256 computedAmountOut = buyingAsset == address(asset1)
            ? (amountIn * FEE_NUMERATOR * reserve1_) / (reserve0_ * FEE_DENOMINATOR + FEE_NUMERATOR * amountIn)
            : (amountIn * reserve0_ * FEE_NUMERATOR) / (reserve1_ * FEE_DENOMINATOR + FEE_NUMERATOR * amountIn);
        if (computedAmountOut < amountOutMin) revert InsufficientAmountOut(amountOutMin, computedAmountOut);

        // check if pool has enough supply in both assets
        if (
            (buyingAsset == address(asset0) && computedAmountOut > reserve0_)
                || (buyingAsset == address(asset1) && computedAmountOut > reserve1_)
        ) {
            revert NotEnoughLiquidityForSwap();
        }

        // effects
        uint256 newReserve0 = buyingAsset == address(asset0) ? reserve0_ - computedAmountOut : reserve0_ + amountIn;
        uint256 newReserve1 = buyingAsset == address(asset1) ? reserve1_ - computedAmountOut : reserve1_ + amountIn;
        // check if K respected
        if (reserve0_ * reserve1_ > newReserve0 * newReserve1) {
            revert ViolationConstantK(reserve0_ * reserve1_, newReserve0 * newReserve1);
        }

        _update(newReserve0, newReserve1);

        // interactions
        // transfer buying asset to the user & transfer selling asset to the pool
        if (buyingAsset == address(asset0)) {
            asset0.safeTransfer(receiver, computedAmountOut);
            asset1.transferFrom(msg.sender, address(this), amountIn);
        } else {
            // buyingAsset == asset0
            asset1.safeTransfer(receiver, computedAmountOut);
            asset0.transferFrom(msg.sender, address(this), amountIn);
        }

        emit Swap(msg.sender, receiver, buyingAsset, amountIn, computedAmountOut);
    }

    /// @notice User can supply liquidity to a pool directly
    /// @dev The user needs to make sure that the ratio of the supplied asset is equal to the current ratio
    /// @param asset0_ amount of asset0 to be supplied to reserve0
    /// @param asset1_ amount of asset1 to be supplied to reserve1
    /// @param receiver account that will receive LP tokens
    function provideLiquidity(uint256 asset0_, uint256 asset1_, address receiver) public nonReentrant {
        // CEI

        // checks
        if (receiver == address(0)) revert ZeroAddressNotAllowed();

        (uint256 reserve0_, uint256 reserve1_) = getReserves();

        uint256 lpTokensToMint;
        if (reserve0_ == 0 && reserve1_ == 0) {
            // pool empty

            // assumption: give any amount of token
            lpTokensToMint += asset0_ + asset1_;
        } else {
            // pool already initiated
            // determine whether asset0 or asset1 amount is used for LP calculation
            // the smaller ratio is chosen to incentivise correct supply of assets according to the pool ratio, basically if you deviate you get the worse deal
            // the amount not reflecting the ratio is donated to the pool
            /**
             * current pool: 9000 usdc, 3 weth, 2000lp tokens
             *
             *         user wants to supply 4000 usdc and 1 ether, eg. for deeming ether worth more, or usdc worth less
             *
             *         4000/1 > 9000/3 ? asset0 over supplied ie asset1 taken for computing LP eligibility : asset1 over supplied ie asset0 taken for computing LP eligibility
             *
             *         asset0 taken for LP eligibility:
             *
             *         amount asset0 Supplied / reserve0
             *
             *          1000, 200 -> 1200 lp tokens
             */
            uint256 ratio;
            if (asset0_ * precisionAsset1 / asset1_ > reserve0_ * precisionAsset1 / reserve1_) {
                // asset1 undervalued
                ratio = asset1_ * precisionAsset1 / reserve1_;
                lpTokensToMint = ratio * totalSupply() / precisionAsset1;
            } else {
                // asset0 undervalued, or equal ratio (then it doesnt matter)
                ratio = asset0_ * precisionAsset0 / reserve0_;
                // if same amount as already in the pool, the total supply is doubled
                lpTokensToMint = ratio * totalSupply() / precisionAsset0;
            }
        }

        // effect

        // mint
        _mint(receiver, lpTokensToMint);

        uint256 newReserve0 = reserve0_ + asset0_;
        uint256 newReserve1 = reserve1_ + asset1_;
        _update(newReserve0, newReserve1); // supply old reserve values, supplied amounts

        emit LiquiditySupplied(msg.sender, asset0_, asset1_, receiver);

        // interactions

        // no safeTransferFrom as this contract is the receiver
        asset0.transferFrom(msg.sender, address(this), asset0_);
        asset1.transferFrom(msg.sender, address(this), asset1_);
    }

    /// @notice A user can redeem the supplied liquidity inclusive the accrued fees since deployment
    /// @param amountLPToken the amount of LP tokens the user wants to return
    /// @param receiverOfAssets the address where the funds should be sent to
    function redeemLiquidity(uint256 amountLPToken, address receiverOfAssets) public nonReentrant {
        // CEI

        // checks
        if (receiverOfAssets == address(0)) revert ZeroAddressNotAllowed();
        uint256 lpTokenAvailable = balanceOf(msg.sender);
        if (lpTokenAvailable < amountLPToken) revert NotEnoughLPTokens();

        // effect
        uint256 totalLPTokens = totalSupply();
        (uint256 reserve0_, uint256 reserve1_) = getReserves();

        uint256 amountOfAsset0ToReturn = reserve0_ * amountLPToken / totalLPTokens;
        uint256 amountOfAsset1ToReturn = reserve1_ * amountLPToken / totalLPTokens;

        // burn
        _burn(msg.sender, amountLPToken);

        emit LiquidityRedeemed(msg.sender, amountOfAsset0ToReturn, amountOfAsset1ToReturn, receiverOfAssets);

        // interactions

        // safeTransfer asset0
        asset0.safeTransfer(receiverOfAssets, amountOfAsset0ToReturn);
        // safeTransfer asset1
        asset1.safeTransfer(receiverOfAssets, amountOfAsset1ToReturn);
    }

    /////////////////////////////////
    /////////////////////////////////
    //////        VIEW          /////
    /////////////////////////////////
    /////////////////////////////////

    function getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    /////////////////////////////////
    /////////////////////////////////
    //////      Internal        /////
    /////////////////////////////////
    /////////////////////////////////

    function _update(uint256 newReserve0, uint256 newReserve1) internal {
        reserve0 = newReserve0;
        reserve1 = newReserve1;
    }
}

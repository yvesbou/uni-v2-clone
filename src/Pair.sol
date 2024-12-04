// SPDX-License-Identifier: MIT

import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";

// todo
/**
 * - add no-reentrant
 * - using safeerc20 to send tokens (redeem liquidity)
 * - using safeMint for minting to recepient (supplyLiquidity)
 * - emit events for every storage change
 * - find out where rounding down/up is required
 */

/**
 * assumptions
 *  - the precision of a supplied asset cannot change
 *  -
 */
contract Pair is ERC20 {
    IERC20 public asset0;
    IERC20 public asset1;

    uint256 public precisionAsset0;
    uint256 public precisionAsset1;
    uint256 constant LP_TOKEN_PRECISION = 1e18;

    uint256 public reserve0;
    uint256 public reserve1;

    error ZeroAddressNotAllowed();
    error NotEnoughLPTokens();

    event LiquiditySupplied(indexed address user, indexed uint256 amount0, indexed uint256 amount1, indexed address receiver);
    event LiquidityRedeemed(indexed address user, indexed uint256 amount0, indexed uint256 amount1, indexed address receiver);

    constructor(address asset0_, address asset1_) {
        asset0 = IERC20(asset0_);
        asset1 = IERC20(asset1_);
        precisionAsset0 = 10 ** asset0.decimals();
        precisionAsset1 = 10 ** asset1.decimals();
    }

    function swap() public {}

    /// @notice User can supply liquidity to a pool directly
    /// @dev The user needs to make sure that the ratio of the supplied asset is equal to the current ratio
    /// @param asset0 amount of asset0 to be supplied to reserve0
    /// @param asset1 amount of asset1 to be supplied to reserve1
    /// @param receiver account that will receive LP tokens
    function provideLiquidity(uint256 asset0_, uint256 asset1_, address receiver) public {
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
             */
            lpTokensToMint = asset0_ * precisionAsset1 / asset1_ > reserve0_ * precisionAsset0 / reserve1_
                ? asset0_ * precisionAsset0 / reserve0_
                : asset1_ * precisionAsset1 / reserve1_;
        }

        // effect

        // mint
        _mint(receiver, lpTokensToMint);

        uint256 newReserve0 = reserve0_ + asset0_;
        uint256 newReserve1 = reserve1_ + asset1_;
        _update(newReserve, newReserve1); // supply old reserve values, supplied amounts

        emit LiquiditySupplied(msg.sender, asset0_, asset1_, receiver);

        // interactions

        // safeTransferFrom asset0
        asset0.transferFrom(msg.sender, address(this), asset0_);
        // safeTransferFrom asset1
        asset1.transferFrom(msg.sender, address(this), asset1_);
    }

    /// @notice A user can redeem the supplied liquidity inclusive the accrued fees since deployment
    /// @param amountLPToken the amount of LP tokens the user wants to return
    /// @param receiverOfAssets the address where the funds should be sent to
    function redeemLiquidity(uint256 amountLPToken, address receiverOfAssets) public {
        // CEI

        // checks
        if (receiver == address(0)) revert ZeroAddressNotAllowed();
        uint256 lpTokenAvailable = balanceOf(msg.sender);
        if (lpTokenAvailable < amountLPToken) revert NotEnoughLPTokens();
        
        // effect
        uint256 totaLPTokens = totalSupply();
        (uint256 reserve0_, uint256 reserve1_) = getReserves();

        uint256 fractionOfBurning = amountLPToken * LP_TOKEN_PRECISION / totalLPTokens;

        uint256 amountOfAsset0ToReturn = reserve0 * fractionOfBurning / LP_TOKEN_PRECISION;
        uint256 amountOfAsset1ToReturn = reserve1 * fractionOfBurning / LP_TOKEN_PRECISION;

        // burn
        _burn(msg.sender, amountLPToken);

        emit LiquidityRedeemed(msg.sender, amountOfAsset0ToReturn, amountOfAsset1ToReturn, receiverOfAssets);

        // interactions

        // safeTransferFrom asset0
        asset0.transferFrom(address(this), receiverOfAssets, amountOfAsset0ToReturn);
        // safeTransferFrom asset1
        asset1.transferFrom(address(this), receiverOfAssets, amountOfAsset1ToReturn);
    }

    /////////////////////////////////
    /////////////////////////////////
    //////        VIEW          /////
    /////////////////////////////////
    /////////////////////////////////

    function getReserves() public view returns(uint256, uint256) {
        return (reserve0, reserve1);
    }

    /////////////////////////////////
    /////////////////////////////////
    //////      Internal        /////
    /////////////////////////////////
    /////////////////////////////////

    function _update(uint256 newReserve0_, uint256 newReserve1_) internal {
        reserve0 = newReserve0_;
        reserve1 = newReserve1_;
    }
}

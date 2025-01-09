// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

// import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {ERC20} from "@solady-0.0.287/tokens/ERC20.sol";
import {SafeTransferLib} from "@solady-0.0.287/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady-0.0.287/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.0.2/utils/ReentrancyGuard.sol";
import {IERC3156FlashLender} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashBorrower.sol";

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// todo
/**
 * - find out where rounding down/up is required (always in favor of protocol)
 * - protocol fee (mintFee)
 * - swap out (specify amountOut instead of amountIn)
 *
 * - show importance of skim with a test
 * - write a test with an inflation attack
 *
 * - improve documentation based on uni-v2 book
 * - gas improvements (packing price, timestamp)
 */

/**
 * assumptions
 *  - the precision of a supplied asset cannot change
 *  -
 */
contract Pair is ReentrancyGuard, ERC20, IERC3156FlashLender {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 constant LP_TOKEN_PRECISION = 1e18;
    uint256 constant FEE_NUMERATOR = 99; // 1%
    uint256 constant FEE_DENOMINATOR = 100; // 1%

    // initial supplier needs to donate, dead shares do not completely solve inflation attack
    // https://blog.openzeppelin.com/a-novel-defense-against-erc4626-inflation-attacks
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    ERC20 public asset0;
    ERC20 public asset1;

    address public factory;

    bool public feeSwitchOn;
    uint256 public kLast;

    string private _name;
    string private _symbol;

    uint256 public precisionAsset0;
    uint256 public precisionAsset1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public blockTimestampLast; // downsize to uint32 and pack with reserves?

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    error ZeroAddressNotAllowed();
    error InsufficientSupplied();
    error NotEnoughLPTokens();
    error InvalidAsset(address asset);
    error InsufficientAmountOut(uint256 amountOutRequired, uint256 amountOutEffective);
    error NotEnoughLiquidityForSwap();
    error ViolationConstantK(uint256 left, uint256 right);
    error FlashloanUnsupportedToken();
    error FlashloanAboveMaxAmount();
    error FlashloanFailed();

    event LiquiditySupplied(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event LiquidityRedeemed(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event Swap(
        address indexed spender,
        address indexed receiver,
        address indexed buyingAsset,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address factory_, address asset0_, address asset1_) ERC20() {
        factory = factory_;
        asset0 = ERC20(asset0_);
        asset1 = ERC20(asset1_);
        _name = string(abi.encodePacked(asset0.name(), "-", asset1.name()));
        _symbol = string(abi.encodePacked(asset0.symbol(), "-", asset1.symbol()));
        precisionAsset0 = 10 ** asset0.decimals();
        precisionAsset1 = 10 ** asset1.decimals();
    }

    function setFee(bool feeOn_) public {
        feeSwitchOn = feeOn_;
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
            SafeTransferLib.safeTransfer(address(asset0), receiver, computedAmountOut);
            asset1.transferFrom(msg.sender, address(this), amountIn);
        } else {
            // buyingAsset == asset0
            SafeTransferLib.safeTransfer(address(asset1), receiver, computedAmountOut);
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
        uint256 totalSupply_ = totalSupply(); // savings

        takeProtocolFee(reserve0_, reserve1_, totalSupply_);

        uint256 lpTokensToMint;
        if (reserve0_ == 0 && reserve1_ == 0) {
            // pool empty

            // surplus above MINIMUM_LIQUIDITY is given to the user
            lpTokensToMint = FixedPointMathLib.sqrt(asset0_ * asset1_) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
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
            lpTokensToMint = Math.min(asset0_ * totalSupply_ / reserve0_, asset1_ * totalSupply_ / reserve1_);
        }
        if (lpTokensToMint == 0) {
            revert InsufficientSupplied();
        }

        // effect

        // mint
        _mint(receiver, lpTokensToMint);

        uint256 newReserve0 = reserve0_ + asset0_;
        uint256 newReserve1 = reserve1_ + asset1_;
        _update(newReserve0, newReserve1); // supply old reserve values, supplied amounts

        if (feeSwitchOn) kLast = FixedPointMathLib.sqrt(newReserve0 * newReserve1);

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

        takeProtocolFee(reserve0_, reserve1_, totalLPTokens);

        uint256 amountOfAsset0ToReturn = reserve0_ * amountLPToken / totalLPTokens;
        uint256 amountOfAsset1ToReturn = reserve1_ * amountLPToken / totalLPTokens;

        // burn
        _burn(msg.sender, amountLPToken);

        uint256 newReserve0 = reserve0_ - amountOfAsset0ToReturn;
        uint256 newReserve1 = reserve1_ - amountOfAsset1ToReturn;
        _update(newReserve0, newReserve1); // supply old reserve values, supplied amounts

        if (feeSwitchOn) kLast = FixedPointMathLib.sqrt(newReserve0 * newReserve1);

        emit LiquidityRedeemed(msg.sender, amountOfAsset0ToReturn, amountOfAsset1ToReturn, receiverOfAssets);

        // interactions

        // safeTransfer asset0
        SafeTransferLib.safeTransfer(address(asset0), receiverOfAssets, amountOfAsset0ToReturn);
        // safeTransfer asset1
        SafeTransferLib.safeTransfer(address(asset1), receiverOfAssets, amountOfAsset1ToReturn);
    }

    function skim(address to) external nonReentrant {
        uint256 surplusAsset0 = asset0.balanceOf(address(this)) - reserve0;
        uint256 surplusAsset1 = asset1.balanceOf(address(this)) - reserve1;
        SafeTransferLib.safeTransfer(address(asset0), to, surplusAsset0);
        SafeTransferLib.safeTransfer(address(asset1), to, surplusAsset1);
    }

    function sync() external nonReentrant {
        _update(asset0.balanceOf(address(this)), asset1.balanceOf(address(this)));
    }

    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        if (amount > maxFlashLoan(token)) revert FlashloanAboveMaxAmount();

        SafeTransferLib.safeTransfer(token, address(receiver), amount); // reverts if not able to receive

        uint256 fee = flashFee(token, amount);

        // if not checked for return value (the function really handles flashloan),
        // a victim contract with a fallback could get drained
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != keccak256("ERC3156Flashborrower.onFlashLoan"))
        {
            revert FlashloanFailed();
        }

        // lender has to control the flow of tokens
        // a check that tokens are back in the contract is not sufficient
        // the borrower could just increase the LP position instead of returning the loan
        SafeTransferLib.safeTransferFrom(token, address(receiver), address(this), amount + fee);

        return true;
    }

    /////////////////////////////////
    /////////////////////////////////
    //////        VIEW          /////
    /////////////////////////////////
    /////////////////////////////////

    function getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    function maxFlashLoan(address token) public view returns (uint256) {
        if (token != address(asset0) && token != address(asset1)) revert FlashloanUnsupportedToken();
        uint256 currentSupply = ERC20(token).balanceOf(address(this));
        return currentSupply / 10; // max 10%, fails if balance below 10
    }

    function flashFee(address token, uint256 amount) public pure returns (uint256) {
        return amount / 100;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /////////////////////////////////
    /////////////////////////////////
    //////      Internal        /////
    /////////////////////////////////
    /////////////////////////////////

    function _update(uint256 newReserve0, uint256 newReserve1) internal {
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - uint32(blockTimestampLast); // overflow in 2106, intended
        }

        // savings
        uint256 reserve0_ = reserve0;
        uint256 reserve1_ = reserve1;

        if (timeElapsed > 0 && reserve0_ != 0 && reserve1_ != 0) {
            unchecked {
                // allow overflowing
                price0CumulativeLast += reserve1_ * timeElapsed / reserve0_;
                price1CumulativeLast += reserve0_ * timeElapsed / reserve1_;
            }
        }

        // new reserves
        reserve0 = newReserve0;
        reserve1 = newReserve1;

        blockTimestampLast = blockTimestamp;
    }

    function takeProtocolFee(uint256 reserve0_, uint256 reserve1_, uint256 totalSupply_) internal {
        uint256 kLast_ = kLast; // savings
        if (feeSwitchOn && kLast_ != 0) {
            // compute rootk
            uint256 rootK = FixedPointMathLib.sqrt(reserve0_ * reserve1_);
            // compute amount LP Tokens
            if (rootK > kLast) {
                uint256 lpTokensForProtocol = totalSupply_ * (rootK - kLast_) / (kLast_ + 5 * rootK);
                if (lpTokensForProtocol > 0) _mint(factory, lpTokensForProtocol);
            }
        } else {
            kLast = 0;
        }
    }
}

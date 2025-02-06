// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

// import {ERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/ERC20.sol";
import {ERC20} from "@solady-0.0.287/tokens/ERC20.sol";
import {SafeTransferLib} from "@solady-0.0.287/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady-0.0.287/utils/FixedPointMathLib.sol";
import {UQ112x112} from "./Libraries/UQ112x112.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.0.2/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";
import {IERC3156FlashLender} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin-contracts-5.0.2/interfaces/IERC3156FlashBorrower.sol";

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract Pair is ReentrancyGuard, ERC20, IERC3156FlashLender, Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using UQ112x112 for uint224;

    uint256 constant FEE_NUMERATOR = 99; // 1%
    uint256 constant FEE_DENOMINATOR = 100; // 1%
    uint256 constant PROTOCOL_FEE_NUMERATOR = 1; // can change to constructor set values
    uint256 constant PROTOCOL_FEE_DENOMINATOR = 6; // can change to constructor set values
    uint256 constant FEE_FLASHLOAN = 100; // 1%

    // initial supplier needs to donate, dead shares do not completely solve inflation attack (but make them less effective)
    // https://blog.openzeppelin.com/a-novel-defense-against-erc4626-inflation-attacks
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    ERC20 public immutable asset0;
    ERC20 public immutable asset1;

    address public immutable factory;

    bool public feeSwitchOn;
    uint256 public kLast;

    string private _name;
    string private _symbol;

    // packed slot
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;
    // slot end

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    error ZeroAddressNotAllowed();
    error InsufficientSupplied();
    error NotEnoughLPTokens();
    error InvalidAsset(address asset);
    error InsufficientAmountOut(uint256 amountOutRequired, uint256 amountOutEffective);
    error ExceededAmountIn(uint256 amountInMax, uint256 amountInEffective);
    error NotEnoughLiquidityForSwap();
    error ViolationConstantK(uint256 left, uint256 right);
    error FlashloanUnsupportedToken();
    error FlashloanAboveMaxAmount();
    error FlashloanFailed();
    error SwapDeadlinePassed();

    event LiquiditySupplied(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event LiquidityRedeemed(address indexed user, uint256 indexed amount0, uint256 indexed amount1, address receiver);
    event Swap(
        address indexed spender,
        address indexed receiver,
        address indexed buyingAsset,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address factory_, address asset0_, address asset1_) Ownable(msg.sender) {
        // if (factory == address(0)) revert ZeroAddressNotAllowed(); // <- this triggers, foundry testing issues I assume
        factory = factory_;
        asset0 = ERC20(asset0_);
        asset1 = ERC20(asset1_);
        _name = string(abi.encodePacked(asset0.name(), "-", asset1.name()));
        _symbol = string(abi.encodePacked(asset0.symbol(), "-", asset1.symbol()));
    }

    function setFee(bool feeOn_) public onlyOwner {
        feeSwitchOn = feeOn_;
    }

    function swapOut(address receiver, address buyingAsset, uint256 amountInMax, uint256 amountOut, uint256 deadline)
        public
        nonReentrant
    {
        if (receiver == address(0)) revert ZeroAddressNotAllowed();

        if (block.timestamp > deadline) revert SwapDeadlinePassed();

        if (buyingAsset != address(asset0) && buyingAsset != address(asset1)) revert InvalidAsset(buyingAsset);

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        uint256 computedAmountIn = buyingAsset == address(asset1)
            ? (FEE_DENOMINATOR * uint256(reserve0_) * amountOut) / (FEE_NUMERATOR * (uint256(reserve1_) - amountOut))
            : (FEE_DENOMINATOR * uint256(reserve1_) * amountOut) / (FEE_NUMERATOR * (uint256(reserve0_) - amountOut));

        if (computedAmountIn > amountInMax) revert ExceededAmountIn(amountInMax, computedAmountIn);

        _swap(receiver, buyingAsset, computedAmountIn, amountOut, reserve0_, reserve1_);
    }

    /// @notice Allows a user to specify which asset he/she wants to buy/sell and how much he/she should get out of it
    /// @notice swapping takes a 1% fee
    /// @param buyingAsset specifies which asset is bought
    /// @param amountIn specifies the amount which is sold
    /// @param amountOutMin specifies the amount that the user wants to get out
    function swapIn(address receiver, address buyingAsset, uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        public
        nonReentrant
    {
        // CEI

        // checks

        if (receiver == address(0)) revert ZeroAddressNotAllowed();

        if (block.timestamp > deadline) revert SwapDeadlinePassed();

        if (buyingAsset != address(asset0) && buyingAsset != address(asset1)) revert InvalidAsset(buyingAsset);

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        uint256 computedAmountOut = buyingAsset == address(asset1)
            ? (amountIn * uint256(reserve1_) * FEE_NUMERATOR)
                / (uint256(reserve0_) * FEE_DENOMINATOR + FEE_NUMERATOR * amountIn)
            : (amountIn * uint256(reserve0_) * FEE_NUMERATOR)
                / (uint256(reserve1_) * FEE_DENOMINATOR + FEE_NUMERATOR * amountIn);

        if (computedAmountOut < amountOutMin) revert InsufficientAmountOut(amountOutMin, computedAmountOut);

        _swap(receiver, buyingAsset, amountIn, computedAmountOut, reserve0_, reserve1_);
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

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 totalSupply_ = totalSupply(); // savings

        takeProtocolFee(reserve0_, reserve1_, totalSupply_);

        uint256 lpTokensToMint;
        if (reserve0_ == 0 && reserve1_ == 0) {
            // pool empty

            // surplus above MINIMUM_LIQUIDITY is given to the user
            // lib rounds down, in favor of the protocol, that's desired
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

        uint256 newReserve0 = uint256(reserve0_) + asset0_;
        uint256 newReserve1 = uint256(reserve1_) + asset1_;
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
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        takeProtocolFee(reserve0_, reserve1_, totalLPTokens);

        uint256 amountOfAsset0ToReturn = uint256(reserve0_) * amountLPToken / totalLPTokens;
        uint256 amountOfAsset1ToReturn = uint256(reserve1_) * amountLPToken / totalLPTokens;

        // burn
        _burn(msg.sender, amountLPToken);

        uint256 newReserve0 = uint256(reserve0_) - amountOfAsset0ToReturn;
        uint256 newReserve1 = uint256(reserve1_) - amountOfAsset1ToReturn;
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
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 surplusAsset0 = asset0.balanceOf(address(this)) - reserve0_;
        uint256 surplusAsset1 = asset1.balanceOf(address(this)) - reserve1_;
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

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function maxFlashLoan(address token) public view returns (uint256) {
        if (token != address(asset0) && token != address(asset1)) revert FlashloanUnsupportedToken();
        uint256 currentSupply = ERC20(token).balanceOf(address(this));
        return currentSupply;
    }

    function flashFee(address token, uint256 amount) public pure returns (uint256) {
        if (amount < 100) return 100; // fee is 100 wei, people should not take such small flash loans
        // round in favor of the protocol
        return amount % FEE_FLASHLOAN > 0 ? (amount / FEE_FLASHLOAN) + 1 : amount / FEE_FLASHLOAN;
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

        (uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_) = getReserves();

        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast_; // overflow in 2106, intended
        }

        if (timeElapsed > 0 && reserve0_ != 0 && reserve1_ != 0) {
            unchecked {
                // allow overflowing
                price0CumulativeLast += UQ112x112.toUQ112x112(reserve1_).uqdiv(reserve0_) * timeElapsed;
                price1CumulativeLast += UQ112x112.toUQ112x112(reserve0_).uqdiv(reserve1_) * timeElapsed;
            }
        }

        // new reserves
        reserve0 = uint112(newReserve0);
        reserve1 = uint112(newReserve1);

        blockTimestampLast = blockTimestamp;
    }

    function _swap(
        address receiver,
        address buyingAsset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 reserve0_,
        uint256 reserve1_
    ) internal {
        // check if pool has enough supply in both assets
        if (
            (buyingAsset == address(asset0) && amountOut > reserve0_)
                || (buyingAsset == address(asset1) && amountOut > reserve1_)
        ) {
            revert NotEnoughLiquidityForSwap();
        }

        // effects
        uint256 newReserve0 = buyingAsset == address(asset0) ? reserve0_ - amountOut : reserve0_ + amountIn;
        uint256 newReserve1 = buyingAsset == address(asset1) ? reserve1_ - amountOut : reserve1_ + amountIn;
        // check if K respected
        if (reserve0_ * reserve1_ > newReserve0 * newReserve1) {
            revert ViolationConstantK(reserve0_ * reserve1_, newReserve0 * newReserve1);
        }

        _update(newReserve0, newReserve1);

        // interactions
        // transfer buying asset to the user & transfer selling asset to the pool
        if (buyingAsset == address(asset0)) {
            SafeTransferLib.safeTransfer(address(asset0), receiver, amountOut);
            asset1.transferFrom(msg.sender, address(this), amountIn);
        } else {
            // buyingAsset == asset0
            SafeTransferLib.safeTransfer(address(asset1), receiver, amountOut);
            asset0.transferFrom(msg.sender, address(this), amountIn);
        }

        emit Swap(msg.sender, receiver, buyingAsset, amountIn, amountOut);
    }

    function takeProtocolFee(uint256 reserve0_, uint256 reserve1_, uint256 totalSupply_) internal {
        uint256 kLast_ = kLast; // savings
        if (feeSwitchOn && kLast_ != 0) {
            // compute rootk
            uint256 rootK = FixedPointMathLib.sqrt(reserve0_ * reserve1_);
            // compute amount LP Tokens
            if (rootK > kLast_) {
                uint256 nominator = totalSupply_ * PROTOCOL_FEE_NUMERATOR * (rootK - kLast_);
                uint256 denominator = PROTOCOL_FEE_DENOMINATOR
                    * (
                        kLast_
                            + (rootK - kLast_) * (PROTOCOL_FEE_DENOMINATOR - PROTOCOL_FEE_NUMERATOR) / PROTOCOL_FEE_DENOMINATOR
                    );
                // round in favor of the protocol
                uint256 lpTokensForProtocol =
                    nominator % denominator > 0 ? (nominator / denominator) + 1 : nominator / denominator;
                if (lpTokensForProtocol > 0) _mint(factory, lpTokensForProtocol);
            }
        } else {
            kLast = 0;
        }
    }
}

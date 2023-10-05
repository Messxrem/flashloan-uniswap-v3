// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IFlashLoanReceiver} from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import {FlashLoanSimpleReceiverBase} from "@aave/core-v3/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract FlashloanUniswapV3 is FlashLoanSimpleReceiverBase, IUniswapV3SwapCallback {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    address public immutable pool1;
    address public immutable pool2;

    address payable owner;

    event WasFlashLoan(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        address pool,
        address sender,
        address origin
    );

    constructor(
        address _addressProvider,
        address _owner,
        address _token0,
        address _token1,
        address _pool1,
        address _pool2
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        owner = payable(_owner);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        pool1 = _pool1;
        pool2 = _pool2;
    }

    function fn_RequestFlashLoan(address _token, uint256 _amount) public {
        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = "";
        uint16 referralCode = 0;

        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );

        token0.transfer(owner,token0.balanceOf(address(this)));
    }

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        
        require(tx.origin == owner);
        require(msg.sender == address(POOL));
        require(IERC20(asset).balanceOf(address(this)) >= amount);

        //Logic starts here

        uint slippage = 1;

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool2).slot0();
        sqrtPriceX96 = sqrtPriceX96 - (sqrtPriceX96 * uint160(slippage)) / uint160(100);

        IUniswapV3Pool(pool2).swap(
            address(this),
            true,
            int256(token0.balanceOf(address(this))),
            sqrtPriceX96,
            ""
        );

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool1).slot0();
        sqrtPriceX96 = sqrtPriceX96 + (sqrtPriceX96 * uint160(slippage)) / uint160(100);

        IUniswapV3Pool(pool1).swap(
            address(this),
            false,
            int256(token1.balanceOf(address(this))),
            sqrtPriceX96,
            ""
        );

        //end logic

        emit WasFlashLoan(
            asset,
            amount,
            premium,
            initiator,
            address(POOL),
            msg.sender,
            tx.origin
        );

        require(
            IERC20(asset).balanceOf(address(this)) >= amount + premium,
            "Not enough balance to pay back the debt"
        );

        uint256 totalAmount = amount + premium;
        IERC20(asset).approve(address(POOL), totalAmount);

        return true;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(msg.sender == address(pool1) || msg.sender == address(pool2));

        if (amount0Delta > 0)
            token0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0)
            token1.transfer(msg.sender, uint256(amount1Delta));
    }

    receive() external payable {}
}

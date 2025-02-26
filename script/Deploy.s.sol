// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {console2} from "forge-std/console2.sol";
import "forge-std/Script.sol";
import {TokenFactoryBase} from "@contracts/TokenFactoryBase.sol";
import {Token} from "@contracts/Token.sol";
import "@contracts/BancorBondingCurve.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UD60x18, ud, convert, unwrap, pow, add, mul, sub, div, convert} from "@prb/math/src/UD60x18.sol";

contract DeployScript is Script {
    function run() external {
        // Load addresses and parameters from env variables

        address uniswap = vm.envAddress("UNISWAP_V3_FACTORY");
        address positionMgr = vm.envAddress("UNISWAP_V3_NPM");
        address weth = vm.envAddress("WETH_ADDRESS");

        uint256 FEE_PERCENT = vm.envUint("FEE_PERCENT");
        uint256 SLOPE_SCALED = vm.envUint("SLOPE_SCALED");
        uint32 WEIGHT_SCALED = uint32(vm.envUint("WEIGHT_SCALED"));

        uint256 feePercent = vm.envUint("FEE_PERCENT"); // e.g., 100

        // For raw proxy data, use a placeholder admin address
        address placeholderAdmin = vm.envAddress("PLACEHOLDER_ADMIN");

        BancorBondingCurve boundingCurve = new BancorBondingCurve(SLOPE_SCALED, WEIGHT_SCALED);
        {
            UD60x18 weight = convert(WEIGHT_SCALED).div(convert(MAX_WEIGHT));
            console2.log("Bounding curve is deployed at: ", address(boundingCurve));
            console2.log("- slope %e", convert(SLOPE_SCALED).div(convert(SLOPE_SCALE)).unwrap());
            console2.log("- n %e", convert(1).div(weight).sub(convert(1)).unwrap());
            console2.log("-- (weight) %e", weight.unwrap());
        }
        Token tokenImpl = new Token();
        console2.log("Token implementation at ", address(tokenImpl));
        //
        //        // 1. Encode the initializer call for TokenFactoryBase.
        //        bytes memory initData = abi.encodeWithSignature(
        //            "initialize(address,address,address,address,address,uint256,string)",
        //            tokenImpl,
        //            uniswap,
        //            positionMgr,
        //            bondingCurve,
        //            weth,
        //            feePercent,
        //            initStr
        //        );
        //        console2.log("Initializer data:", toHex(initData));
        //
        //        // 2. Get raw deploy data for ProxyAdmin.
        //        bytes memory proxyAdminData = abi.encodePacked(type(ProxyAdmin).creationCode);
        //        console2.log("ProxyAdmin deploy data:", toHex(proxyAdminData));
        //
        //        // 3. Get raw deploy data for TransparentUpgradeableProxy.
        //        bytes memory proxyData = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(tokenImpl, placeholderAdmin, initData));
        //        console2.log("TransparentUpgradeableProxy deploy data:", toHex(proxyData));
        //
        //        // Optional: deploy the contracts.
        //        vm.startBroadcast();
        //        ProxyAdmin admin = new ProxyAdmin();
        //        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(tokenImpl, address(admin), initData);
        //        vm.stopBroadcast();
        //        console2.log("Deployed ProxyAdmin at:", address(admin));
        //        console2.log("Deployed Proxy at:", address(proxy));
    }
}

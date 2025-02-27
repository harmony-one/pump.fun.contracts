// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {console2} from "forge-std/console2.sol";
import "forge-std/Script.sol";
import {TokenFactory} from "@contracts/TokenFactory.sol";
import {Token} from "@contracts/Token.sol";
import "@contracts/BancorBondingCurve.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UD60x18, ud, unwrap, pow, add, mul, sub, div, convert} from "@prb/math/src/UD60x18.sol";

contract DeployScript is Script {
    function run() external {
        // Load addresses and parameters from env variables

        vm.startBroadcast();

        address uniswap = vm.envAddress("UNISWAP_V3_FACTORY");
        address positionMgr = vm.envAddress("UNISWAP_V3_NPM");
        address weth = vm.envAddress("WETH");

        uint256 FEE_PERCENT = vm.envUint("FEE_PERCENT");
        uint256 SLOPE_SCALED = vm.envUint("SLOPE_SCALED");
        uint32 WEIGHT_SCALED = uint32(vm.envUint("WEIGHT_SCALED"));

        uint256 feePercent = vm.envUint("FEE_PERCENT"); // e.g., 100

        // For raw proxy data, use a placeholder admin address
        address adminAddress = vm.envAddress("ADMIN_MULTISIG");

        BancorBondingCurve bondingCurve = new BancorBondingCurve(SLOPE_SCALED, WEIGHT_SCALED);
        {
            UD60x18 weight = convert(WEIGHT_SCALED).div(convert(MAX_WEIGHT));
            console2.log("Bounding curve is deployed at: ", address(bondingCurve));
            console2.log("- slope %e", convert(SLOPE_SCALED).div(convert(SLOPE_SCALE)).unwrap());
            console2.log("- n %e", convert(1).div(weight).sub(convert(1)).unwrap());
            console2.log("-- (weight) %e", weight.unwrap());
        }
        Token tokenImpl = new Token();
        console2.log("Token implementation at ", address(tokenImpl));
        TokenFactory tokenFactoryImpl = new TokenFactory();
        console2.log("TokenFactory implementation at ", address(tokenFactoryImpl));
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console2.log("ProxyAdmin deployed at ", address(proxyAdmin));
        proxyAdmin.transferOwnership(adminAddress);
        console2.log("ProxyAdmin ownership transferred to ", proxyAdmin.owner());
        vm.stopBroadcast();
        console2.log("All CLI deployment complete. Complete the rest on multisig");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,uint256)",
            address(tokenImpl),
            uniswap,
            positionMgr,
            bondingCurve,
            weth,
            feePercent
        );
        bytes memory proxyData = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, abi.encode(tokenFactoryImpl, address(proxyAdmin), initData));
        console2.log("1. [EXECUTE ON MULTISIG] [To: 0x0] [TransparentUpgradeableProxy deploy data] ", vm.toString(proxyData));
        console2.log("2. [EXECUTE ON MULTISIG] [To: (Factory Deployment Address)] [Initializer data] ", vm.toString(initData));



    }
}

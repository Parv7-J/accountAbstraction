// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {HelperConfig, NetworkConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOperation, PackedUserOperation, IEntryPoint, MessageHashUtils} from "script/SendPackedUserOp.s.sol";
// import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {console} from "forge-std/console.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOperation sendPackedUserOp;

    address randomUser = makeAddr("randomUser");

    // address constant FOUNDRY_DEFAULT_WALLET =
    //     0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    // this is the wallet used for deployments
    address constant ANVIL_DEFAULT_ADDRESS =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        //default account calls the setup. deployment contract is deployed with owner default account. the deployment contract deploys helper contract, whos owner is the deployment contract and the minimal account where the owner of the minimal account becomes the default wallet
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
        //test contract is the owner
        sendPackedUserOp = new SendPackedUserOperation();
        //test contract is the owner
    }

    function testOwnerCanExecuteCommands() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;

        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );
        vm.prank(randomUser);
        vm.expectRevert(
            MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector
        );
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoveredSignedOp() public {
        address dest = address(usdc);
        uint256 value = 0;

        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            dest,
            value,
            functionData
        );

        PackedUserOperation memory userOp = sendPackedUserOp
            .generatePackedOperation(
                helperConfig.getConfig(),
                executeCallData,
                address(minimalAccount)
            );

        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint)
            .getUserOpHash(userOp);
        address signer = ECDSA.recover(
            userOpHash.toEthSignedMessageHash(),
            userOp.signature
        );
        assertEq(signer, minimalAccount.owner());
    }

    function testValidationOfUserOps() public {
        NetworkConfig memory config = helperConfig.getConfig();
        address dest = address(usdc);
        uint256 value = 0;

        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            dest,
            value,
            functionData
        );

        PackedUserOperation memory userOp = sendPackedUserOp
            .generatePackedOperation(
                helperConfig.getConfig(),
                executeCallData,
                address(minimalAccount)
            );

        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint)
            .getUserOpHash(userOp);

        vm.deal(address(minimalAccount), 1e18);
        vm.prank(config.entryPoint);
        uint256 validation = minimalAccount.validateUserOp(
            userOp,
            userOpHash,
            1e18
        );
        assertEq(validation, 0);
    }

    function testEntryPointCanExecuteCommands() public {
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        NetworkConfig memory config = helperConfig.getConfig();
        address dest = address(usdc);
        uint256 value = 0;

        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            dest,
            value,
            functionData
        );

        PackedUserOperation memory userOp = sendPackedUserOp
            .generatePackedOperation(
                helperConfig.getConfig(),
                executeCallData,
                address(minimalAccount)
            );

        vm.deal(address(minimalAccount), 1e18);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.prank(randomUser);
        IEntryPoint(config.entryPoint).handleOps(ops, payable(randomUser));

        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}

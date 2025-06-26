// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SystemContractsCaller} from "@era/contracts/libraries/SystemContractsCaller.sol";
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@era/contracts/interfaces/IAccount.sol";
import {MemoryTransactionHelper, Transaction} from "@era/contracts/libraries/MemoryTransactionHelper.sol";
import {BOOTLOADER_FORMAL_ADDRESS, NONCE_HOLDER_SYSTEM_CONTRACT, DEPLOYER_SYSTEM_CONTRACT} from "@era/contracts/Constants.sol";
import {INonceHolder} from "@era/contracts/interfaces/INonceHolder.sol";
import {Utils} from "@era/contracts/libraries/Utils.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotFromBootloader();
    error ZkMinimalAccount__NotFromOwnerOrBootloader();
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__InvalidSignature();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__FailedToPay();

    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }

    modifier requireFromOwnerOrBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromOwnerOrBootloader();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    function validateTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction calldata _transaction
    ) external payable requireFromBootloader returns (bytes4 magic) {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction calldata _transaction
    ) external payable requireFromOwnerOrBootloader {
        //execute
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(
        Transaction calldata _transaction
    ) external payable {
        //verify
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkMinimalAccount__InvalidSignature();
        }
        //execute
        _executeTransaction(_transaction);
    }

    function payForTransaction(
        bytes32 /*_txHash*/,
        bytes32 /*_suggestedSignedHash*/,
        Transaction calldata _transaction
    ) external payable {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(
        bytes32 /*_txHash*/,
        bytes32 _possibleSignedHash,
        Transaction calldata _transaction
    ) external payable {}

    function _validateTransaction(
        Transaction calldata _transaction
    ) internal returns (bytes4 magic) {
        //verify the nonce
        SystemContractsCaller.systemCallWithPropagatedRevert(
            Utils.safeCastToU32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(
                INonceHolder.incrementMinNonceIfEquals,
                (_transaction.nonce)
            )
        );
        //check if we have the enough balance
        uint256 requiredBalance = _transaction.totalRequiredBalance();
        if (requiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }
        //verify the signature
        bytes32 txnHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txnHash, _transaction.signature);

        bool isValid = signer == owner();
        if (isValid) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
    }

    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        bytes memory callData = _transaction.data;
        uint128 value = Utils.safeCastToU128(_transaction.value);

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            SystemContractsCaller.systemCallWithPropagatedRevert(
                Utils.safeCastToU32(gasleft()),
                to,
                value,
                callData
            );
        } else {
            bool success;
            assembly {
                success := call(
                    gas(),
                    to,
                    value,
                    add(callData, 0x20),
                    mload(callData),
                    0,
                    0
                )
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}

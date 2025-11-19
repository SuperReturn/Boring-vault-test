// SPDX-License-Identifier: none
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";


/// @title Ownable2StepWTR
/// @author SuperFi Labs
/// @notice An extention of Ownable2Step that allows the contract owner to rescue tokens that may have been transferred into this contract.
contract Ownable2StepWTR is Ownable2Step {

    /***************************************
    ERRORS
    ***************************************/

    /// @notice Thrown when a token transfer fails
    error TransferFailed();

    /***************************************
    CONSTRUCTOR
    ***************************************/

    /// @notice Constructs the Ownable2StepWTR contract.
    /// @param initialOwner The initial owner of the contract.
    constructor(address initialOwner) Ownable(initialOwner){}

    /***************************************
    RESCUE TOKEN FUNCTION
    ***************************************/

    struct RescueTokenParam {
        address token;
        uint256 amount; // For ETH and ERC20s, the amount to transfer. For ERC721s, the tokenId
        address receiver;
    }

    /// @notice Rescues tokens that may have been transferred into this contract.
    /// Supports the gas token, ERC20s, and ERC721s.
    /// Can only be called by the contract owner.
    /// @param params The tokens to rescue.
    function rescueTokens(RescueTokenParam[] calldata params) external onlyOwner {
        for(uint256 i = 0; i < params.length; ++i) {
            address token = params[i].token;
            // if transferring the gas token
            if(token == address(0)) {
                Address.sendValue(payable(params[i].receiver), params[i].amount);
            }
            // if transferring an erc20 or erc721
            else {
                _transferToken(token, params[i].amount, params[i].receiver);
            }
        }
    }

    /***************************************
    HELPER FUNCTIONS
    ***************************************/

    /// @notice Transfers a token. Supports both ERC20 and ERC721.
    /// @param token The address of the token contract.
    /// @param amountOrID For ERC20s, the amount to transfer. For ERC721s, the tokenId.
    /// @param receiver The receiver of tokens.
    function _transferToken(address token, uint256 amountOrID, address receiver) internal {
        // try transfer()
        bool success = _callOptionalReturnBool(token, abi.encodeCall(IERC20.transfer, (receiver, amountOrID)));
        // return if transfer() was successful
        if(success) return;
        // try transferFrom()
        success = _callOptionalReturnBool(token, abi.encodeCall(IERC20.transferFrom, (address(this), receiver, amountOrID)));
        // return if transferFrom() was successful
        if(success) return;
        // revert
        revert TransferFailed();
    }

    /// @notice Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
    /// on the return value: the return value is optional (but if data is returned, it must not be false).
    /// This is a variant of _callOptionalReturn that silently catches all reverts and returns a bool instead.
    /// @param token The token targeted by the call.
    /// @param data The call data (encoded using abi.encode or one of its variants).
    function _callOptionalReturnBool(address token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? token.code.length > 0 : returnValue == 1);
    }
}

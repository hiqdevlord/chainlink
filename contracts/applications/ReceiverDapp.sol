// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ITypeAndVersion} from "../interfaces/ITypeAndVersion.sol";

import {CCIPReceiver} from "./CCIPReceiver.sol";
import {Client} from "../libraries/Client.sol";

import {IERC20} from "../../vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";

/// @title ReceiverDapp - Application contract for receiving messages from the OffRamp on behalf of an EOA
/// @dev For test purposes only, not to be used as an example or production code.
contract ReceiverDapp is CCIPReceiver, ITypeAndVersion {
  // solhint-disable-next-line chainlink-solidity/all-caps-constant-storage-variables
  string public constant override typeAndVersion = "ReceiverDapp 2.0.0";

  constructor(address router) CCIPReceiver(router) {}

  /// @inheritdoc CCIPReceiver
  function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
    _handleMessage(message.data, message.destTokenAmounts);
  }

  function _handleMessage(bytes memory data, Client.EVMTokenAmount[] memory tokenAmounts) internal {
    (
      ,
      // address originalSender
      address destinationAddress
    ) = abi.decode(data, (address, address));
    for (uint256 i = 0; i < tokenAmounts.length; ++i) {
      uint256 amount = tokenAmounts[i].amount;
      if (destinationAddress != address(0) && amount != 0) {
        IERC20(tokenAmounts[i].token).transfer(destinationAddress, amount);
      }
    }
  }
}

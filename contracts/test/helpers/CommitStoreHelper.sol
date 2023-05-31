// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../../CommitStore.sol";

contract CommitStoreHelper is CommitStore {
  constructor(StaticConfig memory staticConfig) CommitStore(staticConfig) {}

  /// @dev Expose _report for tests
  function report(bytes memory commitReport) external {
    _report(commitReport);
  }
}

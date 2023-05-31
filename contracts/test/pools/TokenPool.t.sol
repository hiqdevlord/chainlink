// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.t.sol";
import {TokenPoolHelper} from "../helpers/TokenPoolHelper.sol";
import {TokenPool} from "../../pools/TokenPool.sol";
import {BurnMintERC677} from "../../pools/tokens/BurnMintERC677.sol";

contract TokenPoolSetup is BaseTest {
  IERC20 internal s_token;
  TokenPoolHelper internal s_tokenPool;

  function setUp() public virtual override {
    BaseTest.setUp();
    s_token = new BurnMintERC677("LINK", "LNK", 18);
    deal(address(s_token), OWNER, type(uint256).max);

    s_tokenPool = new TokenPoolHelper(s_token, rateLimiterConfig());
  }
}

contract TokenPool_constructor is TokenPoolSetup {
  // Reverts
  function testNullAddressNotAllowedReverts() public {
    vm.expectRevert(TokenPool.NullAddressNotAllowed.selector);

    s_tokenPool = new TokenPoolHelper(IERC20(address(0)), rateLimiterConfig());
  }
}

contract TokenPool_applyRampUpdates is TokenPoolSetup {
  event OnRampAllowanceSet(address onRamp, bool allowed);
  event OffRampAllowanceSet(address onRamp, bool allowed);

  function testApplyRampUpdatesSuccess() public {
    TokenPool.RampUpdate[] memory onRamps = new TokenPool.RampUpdate[](2);
    onRamps[0] = TokenPool.RampUpdate({ramp: address(1), allowed: true});
    onRamps[1] = TokenPool.RampUpdate({ramp: address(2), allowed: true});
    TokenPool.RampUpdate[] memory offRamps = new TokenPool.RampUpdate[](2);
    offRamps[0] = TokenPool.RampUpdate({ramp: address(11), allowed: true});
    offRamps[1] = TokenPool.RampUpdate({ramp: address(12), allowed: true});

    vm.expectEmit();
    emit OnRampAllowanceSet(onRamps[0].ramp, onRamps[0].allowed);
    vm.expectEmit();
    emit OnRampAllowanceSet(onRamps[1].ramp, onRamps[1].allowed);

    vm.expectEmit();
    emit OffRampAllowanceSet(offRamps[0].ramp, offRamps[0].allowed);
    vm.expectEmit();
    emit OffRampAllowanceSet(offRamps[1].ramp, offRamps[1].allowed);

    s_tokenPool.applyRampUpdates(onRamps, offRamps);

    assertTrue(s_tokenPool.isOnRamp(onRamps[0].ramp));
    assertTrue(s_tokenPool.isOnRamp(onRamps[1].ramp));

    assertTrue(s_tokenPool.isOffRamp(offRamps[0].ramp));
    assertTrue(s_tokenPool.isOffRamp(offRamps[1].ramp));

    onRamps[0].allowed = false;
    offRamps[1].allowed = false;

    vm.expectEmit();
    emit OnRampAllowanceSet(onRamps[0].ramp, onRamps[0].allowed);

    vm.expectEmit();
    emit OffRampAllowanceSet(offRamps[1].ramp, offRamps[1].allowed);

    s_tokenPool.applyRampUpdates(onRamps, offRamps);

    assertFalse(s_tokenPool.isOnRamp(onRamps[0].ramp));
    assertTrue(s_tokenPool.isOnRamp(onRamps[1].ramp));

    assertTrue(s_tokenPool.isOffRamp(offRamps[0].ramp));
    assertFalse(s_tokenPool.isOffRamp(offRamps[1].ramp));
  }

  // Reverts
  function testOnlyCallableByOwnerReverts() public {
    changePrank(STRANGER);
    vm.expectRevert("Only callable by owner");
    s_tokenPool.applyRampUpdates(new TokenPool.RampUpdate[](0), new TokenPool.RampUpdate[](0));
  }
}

contract TokenPool_currentRateLimiterState is TokenPoolSetup {
  function testCurrentRateLimiterStateSuccess() public {
    RateLimiter.TokenBucket memory bucket = s_tokenPool.currentRateLimiterState();
    RateLimiter.Config memory expectedConfig = rateLimiterConfig();
    assertEq(bucket.capacity, expectedConfig.capacity);
    assertEq(bucket.rate, expectedConfig.rate);
    assertEq(bucket.tokens, expectedConfig.capacity);
    assertEq(bucket.lastUpdated, uint32(block.timestamp));
  }
}

contract TokenPool_setRateLimiterConfig is TokenPoolSetup {
  event ConfigChanged(RateLimiter.Config);

  function testSetRateLimiterConfigSuccess(uint128 capacity, uint128 rate, uint32 newTime) public {
    // Bucket updates only work on increasing time
    vm.assume(newTime >= block.timestamp);
    vm.warp(newTime);

    uint256 oldTokens = s_tokenPool.currentRateLimiterState().tokens;

    RateLimiter.Config memory newConfig = RateLimiter.Config({isEnabled: true, capacity: capacity, rate: rate});

    vm.expectEmit();
    emit ConfigChanged(newConfig);

    s_tokenPool.setRateLimiterConfig(newConfig);

    uint256 expectedTokens = RateLimiter._min(newConfig.capacity, oldTokens);

    RateLimiter.TokenBucket memory bucket = s_tokenPool.currentRateLimiterState();
    assertEq(bucket.capacity, newConfig.capacity);
    assertEq(bucket.rate, newConfig.rate);
    assertEq(bucket.tokens, expectedTokens);
    assertEq(bucket.lastUpdated, newTime);
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert("Only callable by owner");
    s_tokenPool.setRateLimiterConfig(rateLimiterConfig());
  }
}

contract TokenPool_pause is TokenPoolSetup {
  function testPauseSuccess() public {
    s_tokenPool.pause();
    assertTrue(s_tokenPool.paused());
  }

  // Reverts
  function testPauseReverts() public {
    s_tokenPool.pause();
    vm.expectRevert("Pausable: paused");
    s_tokenPool.pause();
  }

  function testNonOwnerReverts() public {
    changePrank(STRANGER);
    vm.expectRevert("Only callable by owner");
    s_tokenPool.pause();
  }
}

contract TokenPool_unpause is TokenPoolSetup {
  function testUnpauseSuccess() public {
    s_tokenPool.pause();
    s_tokenPool.unpause();
    assertFalse(s_tokenPool.paused());
  }

  // Reverts
  function testUnpauseReverts() public {
    vm.expectRevert("Pausable: not paused");
    s_tokenPool.unpause();
  }

  function testNonOwnerReverts() public {
    s_tokenPool.pause();
    changePrank(STRANGER);
    vm.expectRevert("Only callable by owner");
    s_tokenPool.unpause();
  }
}
